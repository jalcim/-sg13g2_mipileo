// Renvoi RX -> TX (prompt 056), niveau N3 pixels : sorties de llp_pix_rx (rx_sol, rx_pix, rx_eol, rx_short) vers
// l'entrée de llp_pix_tx (tx_req, tx_pix), qui réempaquette ; llp_tx refait en-tête et CRC ; renvoi_marque rend faux
// le CRC d'une ligne reçue en erreur.
//
// - Début de ligne : largeur en pixels tirée du WC et du format (llp_pix_regles.vh) : RAW6 WC / 3 × 4, RAW8 WC,
//   RAW10 WC / 5 × 4, RAW12 WC / 3 × 2, RAW14 WC / 7 × 4 ; brut et image non dépaquetée : WC octets. Divisions par
//   produit avec une constante, exactes sur les multiples (vérifié pour les 65 536 WC). Taille hors groupe
//   (size_bad), ou RAW6 de plus de 65 535 pixels : la ligne ne peut pas partir (llp_pix_tx la refuserait) ; perdue et
//   comptée.
// - Pixels : rx_pix en porte 0 à 6 par battement, llp_pix_tx en veut 4 (8 en RAW6) : file de 16 cases de 14 bits.
//   File pleine : pixels jetés, remplacés par le bourrage, ligne marquée.
// - Fin de ligne : statut non nul (CRC, tronquée, jetée) : ligne marquée ; pixels manquants : bourrage de zéros
//   jusqu'à la largeur annoncée (le burst TX ne s'écourte pas).
// - Paquets courts (FS, FE, LS, LE, génériques) : requête courte, le champ de données dans la largeur.
// Le RX ne s'arrête pas : un début de ligne ou un paquet court qui trouve la requête occupée, ou une ligne précédente
// pas encore passée à llp_pix_tx, est perdu et compté. Ordre au même cycle (llp_pix_rx) : une fin ferme d'abord la
// ligne ouverte avant ce cycle ; sans ligne ouverte, celle du début du même cycle ; des pixels au cycle d'un début
// sont à la nouvelle ligne.
`default_nettype none

module renvoi_n3 (
    input  wire         clk,
    input  wire         rst_n,
    input  wire         i_actif,        // renvoi_mode = N3
    // llp_pix_rx
    input  wire         i_sol,
    input  wire [1:0]   i_sol_vc,
    input  wire [5:0]   i_sol_dt,
    input  wire [15:0]  i_sol_wc,
    input  wire [2:0]   i_sol_fmt,
    input  wire         i_pix_valid,
    input  wire [2:0]   i_pix_nb,
    input  wire [83:0]  i_pix_data,
    input  wire         i_eol,
    input  wire [2:0]   i_eol_status,
    input  wire         i_short_valid,
    input  wire [1:0]   i_short_vc,
    input  wire [5:0]   i_short_dt,
    input  wire [15:0]  i_short_data,
    // statut à renvoyer (paquet court)
    input  wire         i_st_valid,
    output wire         o_st_ready,
    input  wire [1:0]   i_st_vc,
    input  wire [5:0]   i_st_dt,
    input  wire [15:0]  i_st_data,
    // llp_pix_tx
    output wire         o_req_valid,
    input  wire         i_req_ready,
    output wire [1:0]   o_req_vc,
    output wire [5:0]   o_req_dt,
    output wire [15:0]  o_req_width,
    output wire         o_pix_valid,
    input  wire         i_pix_ready,
    output wire [111:0] o_pix_data,
    output wire [3:0]   o_pix_nb,
    // verdicts et événements (une période)
    output reg          o_verdict,
    output reg          o_mauvais,
    output reg          o_evt_perdu,
    output reg          o_evt_bourre
);
`include "llp_pix_regles.vh"

    localparam [1:0] LIBRE = 2'd0, LIGNE = 2'd1, IGNORE = 2'd2;

    reg  [1:0]   r_rx;
    reg          r_req_valid;
    reg  [1:0]   r_req_vc;
    reg  [5:0]   r_req_dt;
    reg  [15:0]  r_req_width;
    reg          r_tx;                  // ligne renvoyée, verdict pas encore rendu
    reg  [15:0]  r_entrer;              // pixels à mettre dans la file
    reg  [15:0]  r_sortir;              // pixels à donner à llp_pix_tx
    reg  [3:0]   r_ppb;                 // pixels d'un battement plein : 4, ou 8 en RAW6
    reg          r_fin_vue;
    reg          r_mauvais;
    reg          r_ko;
    reg  [223:0] r_file;                // 16 cases de 14 bits, la plus ancienne en [13:0]
    reg  [4:0]   r_n;

    // largeur de la ligne
    wire [33:0] w_p3 = {18'd0, i_sol_wc} * 34'h0AAAB;
    wire [33:0] w_p5 = {18'd0, i_sol_wc} * 34'h0CCCD;
    wire [33:0] w_p7 = {18'd0, i_sol_wc} * 34'h12493;
    wire [15:0] w_q3 = w_p3[32:17];
    wire [15:0] w_q5 = w_p5[33:18];
    wire [14:0] w_q7 = w_p7[33:19];
    wire [15:0] w_largeur = i_sol_fmt == FMT_RAW6  ? {w_q3[13:0], 2'b00}
                          : i_sol_fmt == FMT_RAW10 ? {w_q5[13:0], 2'b00}
                          : i_sol_fmt == FMT_RAW12 ? {w_q3[14:0], 1'b0}
                          : i_sol_fmt == FMT_RAW14 ? {w_q7[13:0], 2'b00}
                          :                          i_sol_wc;
    // RAW6 au-delà de 49 149 octets : plus de 65 535 pixels, hors de la largeur de llp_pix_tx
    wire        w_taille_ko = size_bad(i_sol_fmt, i_sol_wc) || (i_sol_fmt == FMT_RAW6 && w_q3[15:14] != 2'd0);

    wire       w_sol      = i_actif & i_sol;
    wire       w_short    = i_actif & i_short_valid;
    wire       w_eol      = i_actif & i_eol;
    wire       w_eol_vieux = w_eol & (r_rx != LIBRE);
    wire       w_eol_neuf  = w_eol & (r_rx == LIBRE);
    wire       w_libre    = ~r_req_valid & ~r_tx & (r_sortir == 16'd0) & (r_n == 5'd0);
    wire       w_prend    = w_sol & w_libre & ~w_taille_ko;
    wire       w_prend_c  = w_short & ~r_req_valid;
    // sortie vers llp_pix_tx
    wire [3:0] w_out_nb   = r_sortir >= {12'd0, r_ppb} ? r_ppb : r_sortir[3:0];
    wire       w_out_ok   = r_sortir != 16'd0 && r_n >= {1'b0, w_out_nb};
    wire [3:0] w_sort_n   = (w_out_ok & i_pix_ready) ? w_out_nb : 4'd0;
    wire [4:0] w_n_d      = r_n - {1'b0, w_sort_n};
    // entrée de la file : pixels de la ligne renvoyée (hors cycle d'un début), ou zéros du bourrage
    wire       w_pix      = i_actif & i_pix_valid & ~i_sol & (r_rx == LIGNE);
    wire       w_bourre   = r_tx & r_fin_vue & (r_entrer != 16'd0);
    wire       w_ajout_p  = w_pix & ~r_ko & ({1'b0, w_n_d} + {3'b0, i_pix_nb} <= 6'd16);
    wire [3:0] w_bour_n   = r_entrer >= {12'd0, r_ppb} ? r_ppb : r_entrer[3:0];
    wire       w_ajout_b  = w_bourre & ({1'b0, w_n_d} + {2'b0, w_bour_n} <= 6'd16);
    wire [3:0] w_ajout_n  = w_ajout_p ? {1'b0, i_pix_nb} : w_ajout_b ? w_bour_n : 4'd0;
    wire [111:0] w_ajout_d = w_ajout_p ? {28'd0, i_pix_data} : 112'd0;
    wire [15:0] w_entrer_d = r_entrer - {12'd0, w_ajout_n};
    wire [2:0] w_pix0     = (w_prend & i_pix_valid) ? i_pix_nb : 3'd0;
    wire       w_st       = i_actif & i_st_valid & ~r_req_valid & ~r_tx & (r_rx == LIBRE) & ~w_sol & ~w_short;

    assign o_st_ready  = w_st;
    assign o_req_valid = r_req_valid;
    assign o_req_vc    = r_req_vc;
    assign o_req_dt    = r_req_dt;
    assign o_req_width = r_req_width;
    assign o_pix_valid = w_out_ok;
    assign o_pix_data  = r_file[111:0] & ~({112{1'b1}} << (w_out_nb * 14));
    assign o_pix_nb    = w_out_nb;

    always @(posedge clk or negedge rst_n)
        if (!rst_n) begin
            r_rx         <= LIBRE;
            r_req_valid  <= 1'b0;
            r_req_vc     <= 2'd0;
            r_req_dt     <= 6'd0;
            r_req_width  <= 16'd0;
            r_tx         <= 1'b0;
            r_entrer     <= 16'd0;
            r_sortir     <= 16'd0;
            r_ppb        <= 4'd4;
            r_fin_vue    <= 1'b0;
            r_mauvais    <= 1'b0;
            r_ko         <= 1'b0;
            r_file       <= 224'd0;
            r_n          <= 5'd0;
            o_verdict    <= 1'b0;
            o_mauvais    <= 1'b0;
            o_evt_perdu  <= 1'b0;
            o_evt_bourre <= 1'b0;
        end else begin
            o_verdict    <= 1'b0;
            o_evt_perdu  <= (w_sol & ~w_prend) | (w_short & ~w_prend_c);
            o_evt_bourre <= 1'b0;

            // requête vers llp_pix_tx (un début de ligne et un paquet court ne tombent jamais au même cycle)
            if (r_req_valid & i_req_ready)
                r_req_valid <= 1'b0;
            if (w_prend | w_prend_c | w_st) begin
                r_req_valid <= 1'b1;
                r_req_vc    <= w_st ? i_st_vc : w_prend ? i_sol_vc : i_short_vc;
                r_req_dt    <= w_st ? i_st_dt : w_prend ? i_sol_dt : i_short_dt;
                r_req_width <= w_st ? i_st_data : w_prend ? w_largeur : i_short_data;
            end

            // file de pixels
            r_file   <= (r_file >> (w_sort_n * 14)) | ({112'd0, w_ajout_d} << (w_n_d * 14));
            r_n      <= w_n_d + {1'b0, w_ajout_n};
            r_sortir <= r_sortir - {12'd0, w_sort_n};
            r_entrer <= w_entrer_d;
            if (w_pix & ~w_ajout_p) begin
                r_ko      <= 1'b1;
                r_mauvais <= 1'b1;
            end

            // fin de la ligne ouverte avant ce cycle
            if (w_eol_vieux) begin
                r_rx <= LIBRE;
                if (r_rx == LIGNE) begin
                    r_fin_vue <= 1'b1;
                    if (i_eol_status != 3'd0 || w_entrer_d != 16'd0 || r_ko)
                        r_mauvais <= 1'b1;
                    o_evt_bourre <= w_entrer_d != 16'd0;
                end
            end

            // verdict
            if (r_tx & r_fin_vue & (r_entrer == 16'd0)) begin
                o_verdict <= 1'b1;
                o_mauvais <= r_mauvais;
                r_tx      <= 1'b0;
                r_fin_vue <= 1'b0;
                r_ko      <= 1'b0;
                r_mauvais <= 1'b0;
            end

            // début de ligne
            if (w_sol) begin
                if (!w_prend)
                    r_rx <= w_eol_neuf ? LIBRE : IGNORE;
                else begin
                    r_rx      <= w_eol_neuf ? LIBRE : LIGNE;
                    r_tx      <= 1'b1;
                    r_ppb     <= i_sol_fmt == FMT_RAW6 ? 4'd8 : 4'd4;
                    r_entrer  <= w_largeur - {13'd0, w_pix0};
                    r_sortir  <= w_largeur;
                    r_file    <= {140'd0, w_pix0 != 3'd0 ? i_pix_data : 84'd0};
                    r_n       <= {2'b0, w_pix0};
                    r_ko      <= 1'b0;
                    r_fin_vue <= w_eol_neuf;
                    r_mauvais <= w_eol_neuf & (i_eol_status != 3'd0 || w_largeur != {13'd0, w_pix0});
                    o_evt_bourre <= w_eol_neuf & (w_largeur != {13'd0, w_pix0});
                end
            end
        end
endmodule

`default_nettype wire
