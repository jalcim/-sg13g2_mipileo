// Renvoi RX -> TX (prompt 056), niveau N2 paquets : sorties RX de llp_top (o_rx_hdr/pay/end_*) vers son entrée TX
// (i_tx_req/pay_*). llp_tx refait l'en-tête (ECC) et le CRC ; renvoi_marque rend faux le CRC d'un paquet long reçu en
// erreur. Ce que llp_rx ne publie pas (ECC non corrigeable, type réservé, paquet court douteux P50) n'est pas renvoyé :
// les compteurs de llp_top le signalent.
//
// Le RX ne s'arrête pas : chaque battement est pris, ou sa perte est comptée.
// - En-tête : rangé dans r_req (une requête) si r_req est libre et, pour un paquet long, si le paquet précédent est
//   entièrement passé à llp_tx ; sinon le paquet est perdu (o_evt_perdu), sa charge et sa fin sont ignorées.
// - Charge : ses octets (1 à 4 par battement selon les lanes) sont remis en mots de 4 octets pour llp_tx (qui compte la
//   charge d'après le WC), dans un tampon de 16 octets. Tampon plein : les octets suivants du paquet sont jetés, le
//   bourrage les remplace, le paquet est marqué.
// - Fin : statut non nul (CRC faux, tronqué, burst en erreur) : paquet marqué. Charge incomplète (tronqué, jeté) :
//   bourrée de zéros jusqu'au WC (o_evt_bourre), car un burst TX annoncé (tailles en tête de la FIFO TX) ne s'écourte
//   pas. Les paquets RX qui arrivent pendant ce bourrage sont perdus et comptés.
// Verdict (o_verdict, o_mauvais) : à la fin RX d'un paquet long, charge entière, pour renvoi_marque.
// Ordre au même cycle (llp_rx) : une fin ferme d'abord le paquet ouvert avant ce cycle ; sans paquet ouvert, elle ferme
// celui de l'en-tête du même cycle. Les octets d'un battement qui porte un en-tête sont à ce nouveau paquet.
//
// ERREUR (variante d'erreur) :
// - 0, E_CRC : tout paquet publié par llp_rx est renvoyé ; un paquet long en erreur part avec un CRC faux ;
// - 1, E_SUP : un paquet dont l'en-tête est douteux (corrigé par l'ECC, ou burst marqué sot_err) n'est pas renvoyé
//   (o_evt_supprime) ; un paquet long dont l'erreur n'apparaît qu'à sa fin (CRC, troncature) est déjà parti quand
//   son statut arrive : sans mémoire de paquet, il ne peut pas être supprimé, il part marqué comme en E_CRC.
//
// Statut (renvoi_statut) : une requête de paquet court, prise quand aucun paquet n'est en cours (i_st_*).
`default_nettype none

module renvoi_n2 #(
    parameter ERREUR = 0
) (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        i_actif,         // renvoi_mode = N2
    // RX de llp_top
    input  wire        i_hdr_valid,
    input  wire [1:0]  i_hdr_vc,
    input  wire [5:0]  i_hdr_dt,
    input  wire [15:0] i_hdr_wc,
    input  wire        i_hdr_short,
    input  wire        i_hdr_ecc_corrected,
    input  wire        i_hdr_sot_err,
    input  wire        i_pay_valid,
    input  wire [31:0] i_pay_data,      // octets tassés vers [7:0], à 0 au-delà de i_pay_nb
    input  wire [2:0]  i_pay_nb,
    input  wire        i_end_valid,
    input  wire [1:0]  i_end_status,
    // statut à renvoyer (paquet court)
    input  wire        i_st_valid,
    output wire        o_st_ready,
    input  wire [1:0]  i_st_vc,
    input  wire [5:0]  i_st_dt,
    input  wire [15:0] i_st_data,
    // TX de llp_top
    output wire        o_req_valid,
    input  wire        i_req_ready,
    output wire [1:0]  o_req_vc,
    output wire [5:0]  o_req_dt,
    output wire [15:0] o_req_wc,
    output wire        o_pay_valid,
    input  wire        i_pay_ready,
    output wire [31:0] o_pay_data,
    output wire [2:0]  o_pay_nb,
    // verdicts et événements (une période)
    output reg         o_verdict,
    output reg         o_mauvais,
    output reg         o_evt_perdu,
    output reg         o_evt_supprime,
    output reg         o_evt_bourre
);
    localparam [1:0] LIBRE = 2'd0, CHARGE = 2'd1, IGNORE = 2'd2;

    reg  [1:0]   r_rx;                  // paquet RX en cours : aucun, renvoyé, ignoré
    reg          r_req_valid;
    reg  [1:0]   r_req_vc;
    reg  [5:0]   r_req_dt;
    reg  [15:0]  r_req_wc;
    reg          r_tx;                  // paquet long renvoyé, verdict pas encore rendu
    reg  [15:0]  r_reste;               // octets de charge à mettre dans le tampon
    reg  [15:0]  r_sortir;              // octets de charge à donner à llp_tx
    reg          r_fin_vue;             // fin RX vue pour le paquet renvoyé
    reg          r_mauvais;
    reg          r_ko;                  // octets jetés (tampon plein) : le reste vient du bourrage
    reg  [127:0] r_tas;                 // tampon de charge, premier octet en [7:0]
    reg  [4:0]   r_n;

    wire       w_hdr      = i_actif & i_hdr_valid;
    wire       w_end      = i_actif & i_end_valid;
    wire       w_end_vieux = w_end & (r_rx != LIBRE);               // ferme le paquet ouvert avant ce cycle
    wire       w_end_neuf  = w_end & (r_rx == LIBRE);               // ferme celui de l'en-tête de ce cycle
    wire       w_douteux  = ERREUR != 0 && (i_hdr_ecc_corrected || i_hdr_sot_err);
    wire       w_libre    = ~r_req_valid & (i_hdr_short | (~r_tx & (r_sortir == 16'd0) & (r_n == 5'd0)));
    wire       w_prend    = w_hdr & w_libre & ~w_douteux;
    wire       w_long     = w_prend & ~i_hdr_short;
    // sortie vers llp_tx : 4 octets, ou le reste en fin de charge
    wire [2:0] w_out_nb   = r_sortir >= 16'd4 ? 3'd4 : r_sortir[2:0];
    wire       w_out_ok   = r_sortir != 16'd0 && {1'b0, r_n} >= {3'b0, w_out_nb};
    wire [2:0] w_sort_n   = (w_out_ok & i_pay_ready) ? w_out_nb : 3'd0;
    wire [4:0] w_n_d      = r_n - {2'b0, w_sort_n};
    // entrée du tampon : charge du paquet renvoyé (hors battement d'un nouvel en-tête), ou zéros du bourrage
    wire       w_pay      = i_actif & i_pay_valid & ~i_hdr_valid & (r_rx == CHARGE);
    wire       w_bourre   = r_tx & r_fin_vue & (r_reste != 16'd0);
    wire       w_tient_p  = {1'b0, w_n_d} + {3'b0, i_pay_nb} <= 6'd16;
    wire       w_ajout_p  = w_pay & ~r_ko & w_tient_p;
    wire [2:0] w_bour_n   = r_reste >= 16'd4 ? 3'd4 : r_reste[2:0];
    wire       w_ajout_b  = w_bourre & ({1'b0, w_n_d} + {3'b0, w_bour_n} <= 6'd16);
    wire [2:0] w_ajout_n  = w_ajout_p ? i_pay_nb : w_ajout_b ? w_bour_n : 3'd0;
    wire [31:0] w_ajout_d = w_ajout_p ? i_pay_data & (32'hFFFFFFFF >> {3'd4 - i_pay_nb, 3'b000}) : 32'd0;
    wire [15:0] w_reste_d = r_reste - {13'd0, w_ajout_n};
    // charge portée par le battement de l'en-tête pris
    wire [2:0] w_pay0     = (w_long & i_pay_valid) ? i_pay_nb : 3'd0;
    wire       w_st       = i_actif & i_st_valid & ~r_req_valid & ~r_tx & (r_rx == LIBRE) & ~w_hdr;

    assign o_st_ready  = w_st;
    assign o_req_valid = r_req_valid;
    assign o_req_vc    = r_req_vc;
    assign o_req_dt    = r_req_dt;
    assign o_req_wc    = r_req_wc;
    assign o_pay_valid = w_out_ok;
    assign o_pay_data  = r_tas[31:0] & (32'hFFFFFFFF >> {3'd4 - w_out_nb, 3'b000});
    assign o_pay_nb    = w_out_nb;

    always @(posedge clk or negedge rst_n)
        if (!rst_n) begin
            r_rx           <= LIBRE;
            r_req_valid    <= 1'b0;
            r_req_vc       <= 2'd0;
            r_req_dt       <= 6'd0;
            r_req_wc       <= 16'd0;
            r_tx           <= 1'b0;
            r_reste        <= 16'd0;
            r_sortir       <= 16'd0;
            r_fin_vue      <= 1'b0;
            r_mauvais      <= 1'b0;
            r_ko           <= 1'b0;
            r_tas          <= 128'd0;
            r_n            <= 5'd0;
            o_verdict      <= 1'b0;
            o_mauvais      <= 1'b0;
            o_evt_perdu    <= 1'b0;
            o_evt_supprime <= 1'b0;
            o_evt_bourre   <= 1'b0;
        end else begin
            o_verdict      <= 1'b0;
            o_evt_perdu    <= w_hdr & ~w_douteux & ~w_libre;
            o_evt_supprime <= w_hdr & w_douteux;
            o_evt_bourre   <= 1'b0;

            // requête vers llp_tx
            if (r_req_valid & i_req_ready)
                r_req_valid <= 1'b0;
            if (w_prend | w_st) begin
                r_req_valid <= 1'b1;
                r_req_vc    <= w_st ? i_st_vc : i_hdr_vc;
                r_req_dt    <= w_st ? i_st_dt : i_hdr_dt;
                r_req_wc    <= w_st ? i_st_data : i_hdr_wc;
            end

            // tampon de charge et comptes du paquet renvoyé
            r_tas    <= (r_tas >> {w_sort_n, 3'b000}) | ({96'd0, w_ajout_d} << {w_n_d, 3'b000});
            r_n      <= w_n_d + {2'b0, w_ajout_n};
            r_sortir <= r_sortir - {13'd0, w_sort_n};
            r_reste  <= w_reste_d;
            if (w_pay & ~w_ajout_p) begin
                r_ko      <= 1'b1;
                r_mauvais <= 1'b1;
            end

            // fin du paquet RX ouvert avant ce cycle
            if (w_end_vieux) begin
                r_rx <= LIBRE;
                if (r_rx == CHARGE) begin
                    r_fin_vue <= 1'b1;
                    if (i_end_status != 2'd0 || w_reste_d != 16'd0 || r_ko)
                        r_mauvais <= 1'b1;
                    o_evt_bourre <= w_reste_d != 16'd0;
                end
            end

            // verdict : fin vue et charge entière dans le tampon
            if (r_tx & r_fin_vue & (r_reste == 16'd0)) begin
                o_verdict <= 1'b1;
                o_mauvais <= r_mauvais;
                r_tx      <= 1'b0;
                r_fin_vue <= 1'b0;
                r_ko      <= 1'b0;
                r_mauvais <= 1'b0;
            end

            // nouvel en-tête (le tampon est vide s'il est pris, w_libre)
            if (w_hdr) begin
                if (i_hdr_short)
                    r_rx <= LIBRE;
                else if (!w_long)
                    r_rx <= w_end_neuf ? LIBRE : IGNORE;
                else begin
                    r_rx      <= w_end_neuf ? LIBRE : CHARGE;
                    r_tx      <= 1'b1;
                    r_reste   <= i_hdr_wc - {13'd0, w_pay0};
                    r_sortir  <= i_hdr_wc;
                    r_tas     <= {96'd0, w_pay0 != 3'd0 ? i_pay_data : 32'd0};
                    r_n       <= {2'b0, w_pay0};
                    r_ko      <= 1'b0;
                    r_fin_vue <= w_end_neuf;
                    r_mauvais <= w_end_neuf & (i_end_status != 2'd0 || i_hdr_wc != {13'd0, w_pay0});
                    o_evt_bourre <= w_end_neuf & (i_hdr_wc != {13'd0, w_pay0});
                end
            end
        end
endmodule

`default_nettype wire
