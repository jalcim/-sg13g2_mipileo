// Renvoi RX -> TX (prompt 056), niveau N1 mots : flux d'octets du LM (rx_out_*) renvoyé tel quel vers l'entrée TX du LM
// (tx_in_*), LLP contourné. Rien n'est vérifié ni corrigé : les octets reçus repartent, erreurs comprises.
//
// La LDF veut la taille du paquet avec son premier battement (tx_in_total, REMISE_TAILLE = 1) : elle est lue dans
// l'en-tête reçu, sans correction par l'ECC : 4 si le type est court (DT < 0x10), WC + 6 sinon. Un burst porte un paquet
// (llp_rx de même) : les octets qui suivent la fin du paquet (traîne) sont jetés jusqu'au sot suivant. Les battements
// du LM commencent un burst sur un battement neuf et portent N octets (N = 1, 2 ou 4) : l'en-tête finit toujours à la
// fin d'un battement ; sinon le paquet est perdu et compté.
//
// Les octets de charge sont remis en battements de 4 octets (N = 1 ou 2 : 4 ou 2 battements du LM par battement
// envoyé) : le tampon qui suit en tient 4 fois plus à 1 lane.
//
// Le RX ne s'arrête pas :
// - burst coupé (sot ou rx_out_err avant la fin du paquet), ou battement que le tampon ne peut pas prendre : le paquet
//   est bourré de zéros jusqu'à sa taille (le burst TX annoncé ne s'écourte pas), et son CRC est remplacé par l'inverse
//   du CRC des octets envoyés : il est faux à coup sûr (o_evt_bourre). Tout ce qui arrive pendant le bourrage est
//   perdu, et chaque burst perdu compté (o_evt_perdu) ;
// - burst trop court pour un en-tête, ou en-tête que le tampon ne peut pas prendre : perdu et compté.
//
// Statut (renvoi_statut) : paquet court fabriqué ici (ECC calculée), un battement, entre deux paquets.
`default_nettype none

module renvoi_n1 (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        i_actif,         // renvoi_mode = N1
    // LM, RX
    input  wire        i_valid,
    input  wire [31:0] i_data,
    input  wire [2:0]  i_nb,
    input  wire        i_sot,
    input  wire        i_err,
    // statut à renvoyer (paquet court)
    input  wire        i_st_valid,
    output wire        o_st_ready,
    input  wire [1:0]  i_st_vc,
    input  wire [5:0]  i_st_dt,
    input  wire [15:0] i_st_data,
    // vers le tampon (tx_in_*)
    output reg         o_valid,
    input  wire        i_ready,
    output reg  [31:0] o_data,
    output reg  [2:0]  o_nb,
    output reg         o_last,
    output reg  [16:0] o_total,
    // événements (une période)
    output reg         o_evt_perdu,
    output reg         o_evt_bourre
);
    localparam [1:0] ATTENTE = 2'd0, ENTETE = 2'd1, CORPS = 2'd2, BOURRE = 2'd3;

    reg  [1:0]  r_etat;
    reg  [23:0] r_hdr;                  // octets d'en-tête reçus (DI, WC)
    reg  [2:0]  r_hn;
    reg  [16:0] r_attendu;              // octets du paquet encore attendus du RX (charge et CRC)
    reg  [16:0] r_reste;                // octets du paquet encore à envoyer (charge et CRC)
    reg  [15:0] r_charge;               // octets de charge encore à envoyer
    reg  [15:0] r_crc;                  // CRC des octets de charge envoyés
    reg  [23:0] r_acc;                  // octets reçus pas encore envoyés, 0 à 3
    reg  [2:0]  r_acc_n;

    wire        w_b     = i_actif & i_valid;
    wire        w_sot   = w_b & i_sot;
    wire        w_err   = w_b & i_err;
    // en-tête : octets reçus, puis ceux du battement
    wire [2:0]  w_hn0   = w_sot ? 3'd0 : r_hn;
    wire [31:0] w_hdr_s = ({8'd0, w_sot ? 24'd0 : r_hdr} | (i_data << {w_hn0[1:0], 3'b000}));
    wire [3:0]  w_cumul = {1'b0, w_hn0} + {1'b0, i_nb};
    wire        w_ent   = w_b & ~w_err & (r_etat == ENTETE | (w_sot & r_etat == ATTENTE));
    wire        w_hdr_ok = w_ent & (w_cumul == 4'd4);
    wire        w_hdr_ko = w_ent & (w_cumul > 4'd4);
    wire        w_court = w_hdr_s[5:4] == 2'b00;
    wire [16:0] w_total = w_court ? 17'd4 : {1'b0, w_hdr_s[23:8]} + 17'd6;
    // corps : octets du battement qui sont au paquet, ajoutés aux octets retenus ; un battement part à 4 octets ou à
    // la fin du paquet, avec ses octets de charge comptés pour le CRC
    wire        w_corps = w_b & ~i_sot & ~i_err & (r_etat == CORPS);
    wire [16:0] w_k17   = {14'd0, i_nb} < r_attendu ? {14'd0, i_nb} : r_attendu;
    wire [2:0]  w_k     = w_k17[2:0];
    wire        w_fin_p = w_k17 == r_attendu;
    wire [3:0]  w_n     = {1'b0, r_acc_n} + {1'b0, w_k};
    wire        w_envoi = w_corps & (w_n >= 4'd4 | w_fin_p);
    wire [23:0] w_acc   = r_acc & ~(24'hFFFFFF << {r_acc_n[1:0], 3'b000});
    wire [31:0] w_cdata = {8'd0, w_acc} | ((i_data & (32'hFFFFFFFF >> {3'd4 - w_k, 3'b000})) << {r_acc_n[1:0], 3'b000});
    wire [2:0]  w_cnb   = w_n[2:0];
    wire [2:0]  w_pc    = r_charge < {13'd0, w_cnb} ? r_charge[2:0] : w_cnb;
    // bourrage : zéros de charge, puis le CRC inversé (octet 0 en premier)
    wire [2:0]  w_bz    = r_charge >= 16'd4 ? 3'd4 : r_charge[2:0];
    wire [15:0] w_icrc  = ~r_crc;
    wire [2:0]  w_bnb   = r_charge != 16'd0 ? w_bz : r_reste[2:0];
    wire [31:0] w_bdata = r_charge != 16'd0 ? 32'd0
                        : r_reste == 17'd2 ? {16'd0, w_icrc} : {24'd0, w_icrc[15:8]};
    wire        w_st_ok = i_actif & i_st_valid & (r_etat == ATTENTE) & ~w_hdr_ok;
    wire [5:0]  w_st_ecc;
    wire [15:0] w_crc_n;

    llp_ecc_gen u_ecc (.i_data({i_st_data, i_st_vc, i_st_dt}), .o_ecc(w_st_ecc));
    llp_crc_step u_crc (
        .i_crc  (r_crc),
        .i_data (r_etat == BOURRE ? 32'd0 : w_cdata),
        .i_nb   (r_etat == BOURRE ? w_bz : w_pc),
        .o_crc  (w_crc_n)
    );

    always @* begin
        o_valid = 1'b0;
        o_data  = 32'd0;
        o_nb    = 3'd0;
        o_last  = 1'b0;
        o_total = 17'd4;
        if (w_hdr_ok) begin
            o_valid = 1'b1;
            o_data  = w_hdr_s;
            o_nb    = 3'd4;
            o_last  = w_court;
            o_total = w_total;
        end else if (w_envoi) begin
            o_valid = 1'b1;
            o_data  = w_cdata;
            o_nb    = w_cnb;
            o_last  = w_fin_p;
        end else if (r_etat == BOURRE) begin
            o_valid = 1'b1;
            o_data  = w_bdata;
            o_nb    = w_bnb;
            o_last  = {14'd0, w_bnb} == r_reste;
        end else if (w_st_ok) begin
            o_valid = 1'b1;
            o_data  = {2'b00, w_st_ecc, i_st_data, i_st_vc, i_st_dt};
            o_nb    = 3'd4;
            o_last  = 1'b1;
        end
    end
    assign o_st_ready = w_st_ok & i_ready;

    always @(posedge clk or negedge rst_n)
        if (!rst_n) begin
            r_etat       <= ATTENTE;
            r_hdr        <= 24'd0;
            r_hn         <= 3'd0;
            r_attendu    <= 17'd0;
            r_acc        <= 24'd0;
            r_acc_n      <= 3'd0;
            r_reste      <= 17'd0;
            r_charge     <= 16'd0;
            r_crc        <= 16'hFFFF;
            o_evt_perdu  <= 1'b0;
            o_evt_bourre <= 1'b0;
        end else begin
            o_evt_perdu  <= 1'b0;
            o_evt_bourre <= 1'b0;
            case (r_etat)
                BOURRE:
                    if (i_ready) begin
                        r_reste  <= r_reste - {14'd0, w_bnb};
                        r_charge <= r_charge - {13'd0, w_bz};
                        r_crc    <= w_crc_n;
                        if ({14'd0, w_bnb} == r_reste)
                            r_etat <= ATTENTE;
                    end
                CORPS:
                    if (w_sot || w_err || (w_envoi && !i_ready)) begin
                        r_etat       <= BOURRE;     // coupé, ou battement refusé : bourrage des octets pas envoyés
                        r_acc_n      <= 3'd0;
                        o_evt_bourre <= 1'b1;
                    end else if (w_corps) begin
                        r_attendu <= r_attendu - w_k17;
                        if (w_envoi) begin
                            r_reste  <= r_reste - {14'd0, w_cnb};
                            r_charge <= r_charge - {13'd0, w_pc};
                            r_crc    <= w_crc_n;
                            r_acc_n  <= 3'd0;
                            if (w_fin_p)
                                r_etat <= ATTENTE;
                        end else begin
                            r_acc   <= w_cdata[23:0];
                            r_acc_n <= w_cnb;
                        end
                    end
                default: ;
            endcase
            // en-tête (sot : dans tout état sauf BOURRE, où le burst est perdu ; le paquet coupé part en bourrage)
            if (w_sot && !i_err && r_etat == BOURRE)
                o_evt_perdu <= 1'b1;            // un burst en erreur est déjà compté par llp_top (o_cnt_burst)
            if (w_sot && r_etat == ENTETE)
                o_evt_perdu <= 1'b1;            // burst précédent trop court pour un en-tête
            if (w_ent) begin
                if (w_hdr_ok) begin
                    if (i_ready) begin
                        r_etat    <= w_court ? ATTENTE : CORPS;
                        r_attendu <= w_total - 17'd4;
                        r_acc_n   <= 3'd0;
                        r_reste   <= w_total - 17'd4;
                        r_charge <= w_hdr_s[23:8];
                        r_crc    <= 16'hFFFF;
                    end else begin
                        r_etat      <= ATTENTE;
                        o_evt_perdu <= 1'b1;
                    end
                end else if (w_hdr_ko) begin
                    r_etat      <= ATTENTE;
                    o_evt_perdu <= 1'b1;
                end else begin
                    r_etat <= ENTETE;
                    r_hdr  <= w_hdr_s[23:0];
                    r_hn   <= w_cumul[2:0];
                end
            end else if (w_sot && !i_err && r_etat == CORPS)
                o_evt_perdu <= 1'b1;            // le burst qui coupe le paquet est perdu pendant le bourrage
            if (w_err && r_etat == ENTETE) begin
                r_etat      <= ATTENTE;
                o_evt_perdu <= 1'b1;
            end
        end
endmodule

`default_nettype wire
