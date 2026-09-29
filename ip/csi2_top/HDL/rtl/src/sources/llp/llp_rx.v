// Tête RX du LLP CSI-2 (v1.3 chapitre 9) sur le flux du Lane Management : règles R1 à R13 de
// ../../spec/interface_lm_llp.md. Un battement par cycle, 0 à 4 octets, pris sans contre-pression (R1).
//
// Deux étages de bascules, aucune sortie combinatoire :
// - étage 1, des entrées aux registres r_* (état du burst) et a_* (battement classé). Assemblage de l'en-tête sur
//   un à quatre battements, puis ECC. Le syndrome ne passe pas par l'assemblage : il est linéaire, et se somme
//   d'une part rangée avec les octets déjà reçus (r_part_ecc) et de la part des octets du battement, calculée aux
//   quatre places possibles puis choisie par r_nb_entete et le sot. Avec ENTREE = 1, le battement passe d'abord par
//   des bascules, et sa part du syndrome est calculée avant elles : un cycle de latence de plus. L'assemblage ne sert plus qu'aux données à
//   corriger, en parallèle. Le WC corrigé est chargé tel quel dans r_reste, sans calcul, et le verdict
//   (non corrigeable, court, réservé) dans r_ko, lu au battement suivant plutôt que chaîné derrière l'ECC.
//   Les octets qui suivent l'en-tête dans son propre battement sont décomptés au battement suivant (r_decale).
//   Les battements de charge sont classés (charge, pied, traîne) en comparant r_reste à de petites constantes,
//   sans soustraction ; la soustraction qui met r_reste à jour court en parallèle. Le type corrigé (court,
//   réservé) se lit sans attendre la correction, et l'acceptation de l'en-tête est rangée dans a_publie et a_long.
// - étage 2, des registres a_* aux sorties. Champs de l'en-tête ; octets qui suivent l'en-tête dans son battement,
//   classés sur le WC corrigé déjà rangé ; charge tassée vers [7:0] ; CRC-16 avancé sur la charge puis sur le pied.
//   Le pied est bon si le registre retombe à 0 (résidu d'un CRC sans inversion finale) : pas de comparateur 16 bits
//   derrière un pied à cheval sur deux battements.
// L'ECC, le classement par le WC et le CRC sont ainsi dans trois cônes distincts.
//
// Latence fixe de 2 cycles pour toutes les sorties, 3 avec ENTREE = 1. Un paquet court n'a pas de o_end_valid :
// un sot ne ferme donc jamais deux paquets au même cycle (fin 2 de l'ancien, et au plus l'en-tête du nouveau).
`ifndef __LLP_RX__
`define __LLP_RX__
`default_nettype none

module llp_rx #(
    parameter ENTREE = 0                // 1 : battement rangé dans des bascules d'entrée, sa part du syndrome calculée avant
) (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        i_rx_valid,
    input  wire [31:0] i_rx_data,       // octet k en [8k +: 8]
    input  wire [2:0]  i_rx_nb,         // 1 à 4, 0 sur le battement vide
    input  wire        i_rx_sot,
    input  wire        i_rx_err,
    input  wire        i_rx_sot_err,
    output reg         o_hdr_valid,
    output reg  [1:0]  o_hdr_vc,
    output reg  [5:0]  o_hdr_dt,
    output reg  [15:0] o_hdr_wc,
    output reg         o_hdr_short,
    output reg         o_hdr_ecc_corrected,
    output reg         o_hdr_sot_err,
    output reg         o_pay_valid,
    output reg  [31:0] o_pay_data,
    output reg  [2:0]  o_pay_nb,
    output reg         o_end_valid,
    output reg  [1:0]  o_end_status,
    output reg         o_evt_ecc,
    output reg         o_evt_burst,
    output reg         o_evt_burst_late,   // o_evt_burst d'un burst dont le paquet était déjà sorti (R9)
    output reg         o_evt_short_burst,
    output reg         o_evt_dt,
    output reg  [1:0]  o_evt_dt_vc,        // VC de l'en-tête corrigé du type réservé
    output reg         o_evt_sot_err       // rx_out_sot_err sur un sot pris (R11), une période, avec ou sans en-tête
);
    localparam [1:0] JETTE  = 2'd0;     // rien à lire jusqu'au sot suivant : traîne, burst en erreur, avant le 1er sot
    localparam [1:0] ENTETE = 2'd1;     // en-tête en cours d'assemblage, r_nb_entete octets reçus
    localparam [1:0] CORPS  = 2'd2;     // en-tête lu : sans r_ko, r_reste octets de charge restants, moins r_decale

    // Types réservés (R5, CSI-2 v1.3 Table 3) : 0x04 à 0x07, 0x13 à 0x17, 0x1B, 0x25 à 0x27, 0x2E, 0x2F, 0x38 à 0x3F
    localparam [63:0] RESERVES = 64'hFF00_C0E0_08F8_00F0;

    function automatic [2:0] compte(input [3:0] prefixe);   // nombre de 1 d'un masque de la forme 0..01..1
        compte = prefixe[3] ? 3'd4 : prefixe[2] ? 3'd3 : prefixe[1] ? 3'd2 : {2'b00, prefixe[0]};
    endfunction

    // État du burst
    reg        r_vu_sot;                // un sot est passé depuis le reset (R2)
    reg [1:0]  r_etat;
    reg [1:0]  r_nb_entete;
    reg [23:0] r_entete;                // octets 0 à 2 de l'en-tête, valides sous r_nb_entete
    reg [5:0]  r_part_ecc;              // part de ces octets valides dans le syndrome de l'ECC
    reg [16:0] r_reste;                 // signé, de -1 à 65 535 en CORPS
    reg [1:0]  r_decale;                // octets du battement d'en-tête qui suivent l'en-tête, pas encore décomptés
    reg        r_ko;                    // en CORPS : en-tête non corrigeable, court ou réservé, rien à lire
    reg        r_err_burst;             // o_evt_burst déjà levé pour ce burst
    reg        r_sot_err;

    // Battement classé, entre les deux étages
    reg        a_entete;                // l'en-tête s'achève dans ce battement
    reg        a_ecc_ko;
    reg        a_ecc_corrige;
    reg        a_court;
    reg        a_reserve;
    reg [23:0] a_hdr;                   // DI et WC corrigés
    reg        a_sot_err;
    reg        a_publie;                // en-tête accepté : ECC bonne ou corrigée, type non réservé
    reg        a_long;                  // en-tête accepté d'un paquet long
    reg [1:0]  a_apres;                 // octets qui suivent l'en-tête dans son battement
    reg [2:0]  a_nb_charge;             // battement de charge : octets de charge, à partir de l'octet 0
    reg [2:0]  a_nb_paquet;             // battement de charge : octets de charge et de pied
    reg        a_fin;                   // battement de charge : le dernier octet du pied y est
    reg [31:0] a_data;                  // octets qui suivent l'en-tête, ramenés en [7:0]
    reg        a_ferme;                 // un sot ou une erreur ferme le paquet long ouvert
    reg        a_ferme_err;             // fermé par rx_out_err (fin 3), sinon par un sot (fin 2)
    reg        a_evt_burst;
    reg        a_evt_court;
    reg        a_evt_sot_err;
    reg        a_sot;                   // le battement est un sot pris

    reg [15:0] r_crc;
    reg        r_livre;                 // le burst en cours a déjà sorti son paquet (LlpHead._delivered)

    // --- étage 1 ---------------------------------------------------------------------------------------------------

    // Battement vu par la tête : l'entrée, ou l'entrée un cycle plus tard (ENTREE = 1). Sa part dans le syndrome de
    // l'ECC, à chacune des 4 places possibles, est calculée sur l'entrée : avec ENTREE = 1, avant les bascules.
    wire        w_rx_valid;
    wire [31:0] w_rx_data;
    wire [2:0]  w_rx_nb;
    wire        w_rx_sot;
    wire        w_rx_err;
    wire        w_rx_sot_err;
    wire [23:0] w_synd_entree;          // [6k +: 6] : part des octets de l'entrée placés après k octets reçus
    wire [23:0] w_synd_place;           // la même, pour le battement vu par la tête

    genvar rang;
    generate
        for (rang = 0; rang < 4; rang = rang + 1)
        begin : g_place
            wire [29:0] w_place = i_rx_data[29:0] << (8 * rang);
            wire [5:0]  w_ecc_place;

            llp_ecc_gen u_ecc_place (
                .i_data (w_place[23:0]),
                .o_ecc  (w_ecc_place)
            );

            assign w_synd_entree[6 * rang +: 6] = w_place[29:24] ^ w_ecc_place;
        end

        if (ENTREE)
        begin : g_entree
            reg        r_in_valid;
            reg [31:0] r_in_data;
            reg [2:0]  r_in_nb;
            reg        r_in_sot;
            reg        r_in_err;
            reg        r_in_sot_err;
            reg [23:0] r_in_synd;

            always @(posedge clk or negedge rst_n)
                if (!rst_n) begin
                    r_in_valid   <= 1'b0;
                    r_in_data    <= 32'd0;
                    r_in_nb      <= 3'd0;
                    r_in_sot     <= 1'b0;
                    r_in_err     <= 1'b0;
                    r_in_sot_err <= 1'b0;
                    r_in_synd    <= 24'd0;
                end else begin
                    r_in_valid   <= i_rx_valid;
                    r_in_data    <= i_rx_data;
                    r_in_nb      <= i_rx_nb;
                    r_in_sot     <= i_rx_sot;
                    r_in_err     <= i_rx_err;
                    r_in_sot_err <= i_rx_sot_err;
                    r_in_synd    <= w_synd_entree;
                end

            assign {w_rx_valid, w_rx_data, w_rx_nb, w_rx_sot, w_rx_err, w_rx_sot_err, w_synd_place}
                = {r_in_valid, r_in_data, r_in_nb, r_in_sot, r_in_err, r_in_sot_err, r_in_synd};
        end
        else
        begin : g_direct
            assign {w_rx_valid, w_rx_data, w_rx_nb, w_rx_sot, w_rx_err, w_rx_sot_err, w_synd_place}
                = {i_rx_valid, i_rx_data, i_rx_nb, i_rx_sot, i_rx_err, i_rx_sot_err, w_synd_entree};
        end
    endgenerate

    wire        w_pris      = w_rx_valid & (w_rx_sot | r_vu_sot);
    wire        w_octets    = w_pris & ~w_rx_err;                  // R8 : octets d'un battement en erreur ignorés
    wire [1:0]  w_etat      = w_rx_sot ? ENTETE : r_etat;
    wire [1:0]  w_nb_entete = w_rx_sot ? 2'd0 : r_nb_entete;
    wire        w_sot_err   = w_rx_sot ? w_rx_sot_err : r_sot_err;

    // En-tête : octets déjà reçus, puis ceux du battement. Le sot, qui arrive tard, choisit en dernier.
    wire [23:0] w_entete_suite = (w_rx_data[23:0] << {r_nb_entete, 3'b000})
                               | (r_entete & ~(24'hFFFFFF << {r_nb_entete, 3'b000}));
    wire [23:0] w_entete = w_rx_sot ? w_rx_data[23:0] : w_entete_suite;       // DI et WC, l'ECC à part
    wire [3:0]  w_cumul    = {2'b00, w_nb_entete} + {1'b0, w_rx_nb};
    wire        w_complet  = w_octets & w_etat == ENTETE & w_cumul >= 4'd4;
    wire [23:0] w_recus    = w_entete & ~(24'hFFFFFF << {w_cumul[1:0], 3'b000});  // rangés si incomplet
    wire [5:0]  w_ecc_recus;
    wire [5:0]  w_synd     = w_rx_sot ? w_synd_place[5:0] : r_part_ecc ^ w_synd_place[6 * r_nb_entete +: 6];
    wire [23:0] w_hdr;
    wire        w_ecc_corrige;
    wire        w_ecc_ko;
    wire [23:0] w_flip;                 // bit de données que corrige l'ECC, un au plus
    wire [6:0]  w_court_si;             // [k] : DT reçu au bit k inversé de 0x00 à 0x0F (R5), [6] : DT reçu tel quel
    wire [6:0]  w_reserve_si;           // de même : DT réservé
    wire        w_juste    = w_flip[5:0] == 6'd0;
    wire        w_court    = w_juste ? w_court_si[6] : |(w_flip[5:0] & w_court_si[5:0]);
    wire        w_reserve  = w_juste ? w_reserve_si[6] : |(w_flip[5:0] & w_reserve_si[5:0]);

    llp_ecc_gen u_ecc_recus (
        .i_data (w_recus),
        .o_ecc  (w_ecc_recus)
    );

    // Type après correction : l'ECC change au plus un bit du DT. Le DT reçu est classé tel quel et à chacun de ses
    // bits inversé, en parallèle du syndrome, qui choisit ensuite.
    generate
        for (rang = 0; rang < 7; rang = rang + 1)
        begin : g_dt
            wire [5:0] w_dt = w_entete[5:0] ^ (6'd1 << rang);   // rang 6 : aucun bit inversé

            assign w_court_si[rang]   = w_dt[5:4] == 2'b00;
            assign w_reserve_si[rang] = RESERVES[w_dt];
        end
    endgenerate

    llp_ecc_correct u_ecc (
        .i_data          (w_entete),
        .i_syndrome      (w_synd),
        .o_data          (w_hdr),
        .o_flip          (w_flip),
        .o_corrected     (w_ecc_corrige),
        .o_uncorrectable (w_ecc_ko)
    );

    // Charge : w_sup_dec[m] = (r_reste - r_decale > m - 2). L'octet j du battement est de la charge
    // si w_sup_dec[j + 2], du paquet (charge ou pied) si w_sup_dec[j] ; le paquet reste ouvert après nb octets
    // si w_sup_dec[nb].
    wire [10:0] w_sup;
    wire [7:0]  w_sup_dec;

    generate
        for (rang = 0; rang < 11; rang = rang + 1)
        begin : g_sup
            localparam signed [16:0] SEUIL = rang - 2;
            assign w_sup[rang] = $signed(r_reste) > SEUIL;
        end
        for (rang = 0; rang < 8; rang = rang + 1)
        begin : g_dec
            localparam [3:0] RANG = rang;
            assign w_sup_dec[rang] = w_sup[RANG + {2'b00, r_decale}];
        end
    endgenerate

    wire [3:0]  w_valides   = {w_rx_nb > 3'd3, w_rx_nb > 3'd2, w_rx_nb > 3'd1, w_rx_nb > 3'd0};
    wire        w_ouvert    = r_etat == CORPS & ~r_ko & w_sup_dec[0];  // en-tête publié, pied pas encore fini
    wire        w_corps     = w_octets & ~w_rx_sot & w_ouvert;
    wire        w_encore    = w_sup_dec[w_rx_nb];
    wire [3:0]  w_conso     = {2'b00, r_decale} + {1'b0, w_rx_nb};

    // En-tête accepté, rangé dès l'étage 1 : à l'étage 2, le CRC suit un registre plutôt que a_entete et ses verdicts
    wire        w_publie    = w_complet & ~w_ecc_ko & ~w_reserve;

    // Fermetures décidées par l'état du burst
    wire        w_ferme     = w_pris & w_ouvert & (w_rx_sot | w_rx_err);       // fin 2 (R3) ou 3 (R8)
    wire        w_evt_burst = w_pris & w_rx_err & (w_rx_sot | ~r_err_burst);   // R8, R9, R10
    wire        w_evt_court = w_pris & w_rx_sot & r_etat == ENTETE & r_nb_entete != 2'd0;

    always @(posedge clk or negedge rst_n)
        if (!rst_n) begin
            r_vu_sot    <= 1'b0;
            r_etat      <= JETTE;
            r_nb_entete <= 2'd0;
            r_entete    <= 24'd0;
            r_part_ecc  <= 6'd0;
            r_reste     <= 17'd0;
            r_decale    <= 2'd0;
            r_ko        <= 1'b0;
            r_err_burst <= 1'b0;
            r_sot_err   <= 1'b0;
        end else if (w_pris) begin
            r_vu_sot    <= 1'b1;
            r_err_burst <= w_rx_err | (r_err_burst & ~w_rx_sot);
            r_sot_err   <= w_sot_err;
            r_decale    <= 2'd0;
            if (w_rx_err)
                r_etat <= JETTE;
            else if (w_etat == ENTETE) begin
                if (w_complet) begin
                    r_etat   <= CORPS;
                    r_ko     <= w_ecc_ko | w_court | w_reserve;
                    r_reste  <= {1'b0, w_hdr[23:8]};
                    r_decale <= w_cumul[1:0];
                end else begin
                    r_etat      <= ENTETE;
                    r_nb_entete <= w_cumul[1:0];
                    r_entete    <= w_entete;
                    r_part_ecc  <= w_ecc_recus;
                end
            end else if (w_etat == CORPS) begin
                r_reste <= r_reste - {13'd0, w_conso};
                if (!w_encore | r_ko)
                    r_etat <= JETTE;
            end
        end

    always @(posedge clk or negedge rst_n)
        if (!rst_n) begin
            a_entete      <= 1'b0;
            a_ecc_ko      <= 1'b0;
            a_ecc_corrige <= 1'b0;
            a_court       <= 1'b0;
            a_reserve     <= 1'b0;
            a_hdr         <= 24'd0;
            a_sot_err     <= 1'b0;
            a_publie      <= 1'b0;
            a_long        <= 1'b0;
            a_apres       <= 2'd0;
            a_nb_charge   <= 3'd0;
            a_nb_paquet   <= 3'd0;
            a_fin         <= 1'b0;
            a_data        <= 32'd0;
            a_ferme       <= 1'b0;
            a_ferme_err   <= 1'b0;
            a_evt_burst   <= 1'b0;
            a_evt_court   <= 1'b0;
            a_evt_sot_err <= 1'b0;
            a_sot         <= 1'b0;
        end else begin
            a_entete      <= w_complet;
            a_ecc_ko      <= w_ecc_ko;
            a_ecc_corrige <= w_ecc_corrige;
            a_court       <= w_court;
            a_reserve     <= w_reserve;
            a_hdr         <= w_hdr;
            a_sot_err     <= w_sot_err;
            a_publie      <= w_publie;
            a_long        <= w_publie & ~w_court;
            a_apres       <= w_cumul[1:0];
            a_nb_charge   <= w_corps ? compte(w_valides & w_sup_dec[5:2]) : 3'd0;
            a_nb_paquet   <= w_corps ? compte(w_valides & w_sup_dec[3:0]) : 3'd0;
            a_fin         <= w_corps & ~w_encore;
            a_data        <= w_complet ? w_rx_data >> {3'd4 - {1'b0, w_nb_entete}, 3'b000} : w_rx_data;
            a_ferme       <= w_ferme;
            a_ferme_err   <= ~w_rx_sot;
            a_evt_burst   <= w_evt_burst;
            a_evt_court   <= w_evt_court;
            a_evt_sot_err <= w_pris & w_rx_sot & w_rx_sot_err;
            a_sot         <= w_pris & w_rx_sot;
        end

    // --- étage 2 ---------------------------------------------------------------------------------------------------

    // Battement d'en-tête d'un paquet long : min(apres, WC) octets de charge, min(apres, WC + 2) octets du paquet
    wire [15:0] w_wc        = a_hdr[23:8];
    wire        w_douteux   = a_court & a_ecc_corrige & a_sot_err;   // P50 : court, sot_err et ECC corrigée
    wire        w_wc_nul    = w_wc == 16'd0;
    wire        w_wc_couvre = w_wc >= {14'd0, a_apres};
    wire [2:0]  w_charge    = !a_long ? a_nb_charge : w_wc_couvre ? {1'b0, a_apres} : {1'b0, w_wc[1:0]};
    wire [2:0]  w_paquet    = !a_long ? a_nb_paquet : a_apres == 2'd3 & w_wc_nul ? 3'd2 : {1'b0, a_apres};
    wire        w_fin       = !a_long ? a_fin : a_apres == 2'd2 & w_wc_nul | a_apres == 2'd3 & w_wc <= 16'd1;
    wire [15:0] w_crc;
    // Le battement sort le paquet de son burst : en-tête court, non corrigeable ou réservé, ou dernier octet du pied
    // d'un paquet long. Un battement en erreur ne sort rien (R8, R9) : ses octets sont ignorés.
    wire        w_livre     = a_entete & (a_ecc_ko | a_reserve | a_court) | w_fin;

    llp_crc_step u_crc (
        .i_crc  (a_entete ? 16'hFFFF : r_crc),
        .i_data (a_data),
        .i_nb   (w_paquet),
        .o_crc  (w_crc)
    );

    always @(posedge clk or negedge rst_n)
        if (!rst_n) begin
            r_crc               <= 16'hFFFF;
            r_livre             <= 1'b0;
            o_evt_burst_late    <= 1'b0;
            o_hdr_valid         <= 1'b0;
            o_hdr_vc            <= 2'd0;
            o_hdr_dt            <= 6'd0;
            o_hdr_wc            <= 16'd0;
            o_hdr_short         <= 1'b0;
            o_hdr_ecc_corrected <= 1'b0;
            o_hdr_sot_err       <= 1'b0;
            o_pay_valid         <= 1'b0;
            o_pay_data          <= 32'd0;
            o_pay_nb            <= 3'd0;
            o_end_valid         <= 1'b0;
            o_end_status        <= 2'd0;
            o_evt_ecc           <= 1'b0;
            o_evt_burst         <= 1'b0;
            o_evt_short_burst   <= 1'b0;
            o_evt_dt            <= 1'b0;
            o_evt_dt_vc         <= 2'd0;
            o_evt_sot_err       <= 1'b0;
        end else begin
            r_crc               <= w_crc;
            r_livre             <= (r_livre & ~a_sot) | w_livre;
            // P50 (revues 21/LR1, 31/N2) : un paquet court n'a pas de CRC, l'ECC seule le juge. Porté par un burst
            // marqué rx_out_sot_err (verrou pris à un bit près, R11) et « corrigé » par l'ECC, il cumule deux signes
            // de corruption, et une correction ne prouve rien (31 syndromes sur 64 sont décodables ; une lane à 0xFF
            // donne des FS et FE faux corrigés). Il n'est pas publié : traité comme un en-tête non corrigeable
            // (o_evt_ecc). Un paquet long dans le même cas reste publié : son CRC décide. Pris à l'étage 2, sur des
            // registres : ni a_long ni le CRC n'en dépendent (un paquet douteux est court).
            o_hdr_valid         <= a_publie & ~w_douteux;
            o_hdr_vc            <= a_hdr[7:6];
            o_hdr_dt            <= a_hdr[5:0];
            o_hdr_wc            <= w_wc;
            o_hdr_short         <= a_court;
            o_hdr_ecc_corrected <= a_ecc_corrige;
            o_hdr_sot_err       <= a_sot_err;
            o_pay_valid         <= w_charge != 3'd0;
            o_pay_data          <= a_data & ~(32'hFFFFFFFF << {w_charge, 3'b000});
            o_pay_nb            <= w_charge;
            o_evt_ecc           <= a_entete & (a_ecc_ko | w_douteux);
            o_evt_dt            <= a_entete & ~a_ecc_ko & ~w_douteux & a_reserve;
            o_evt_dt_vc         <= a_hdr[7:6];
            // a_ferme ne ferme qu'un paquet ouvert avant ce battement, qui n'y finit donc pas : jamais avec w_fin
            o_end_valid         <= a_ferme | w_fin;
            o_end_status        <= a_ferme ? {1'b1, a_ferme_err} : {1'b0, w_crc != 16'd0};
            o_evt_burst         <= a_evt_burst;
            o_evt_burst_late    <= a_evt_burst & ~a_sot & r_livre;
            o_evt_short_burst   <= a_evt_court;
            o_evt_sot_err       <= a_evt_sot_err;
        end
endmodule

`default_nettype wire
`endif
