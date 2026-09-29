// Contrôle de trame en réception (CSI-2 v1.3 §9.8, §9.11), derrière llp_rx, calqué sur _Receiver de mipi_csi2.rx
// (mipi-csi master d738c80). Toutes les sorties sortent de bascules, aucune contre-pression.
//
// Un état par VC (0 à NB_VC - 1), comme _OpenFrame, _last_frame_number et _lost_since : trame ouverte et son numéro,
// dernier numéro de trame, paquets perdus depuis, LS ouvert, perte depuis le dernier LS ou LE, perte depuis le FS,
// ligne image ou user vue, numéros de ligne nuls ou non, numéro du LS en attente de sa ligne, largeur de la première
// ligne RAW6, RAW8 et RAW10, et une table de numérotation des lignes par DT (LINE_DT_SLOTS entrées).
//
// Un paquet court compte à son en-tête. Un paquet long compte à sa fin (o_end_valid, état 0, 1 ou 2) : un paquet
// jeté par rx_out_err (état 3) n'existe pas pour le modèle, c'est une perte. Une fin au cycle de son propre en-tête
// (paquet très court, aucune ligne ouverte avant) est appliquée au cycle suivant, avant tout ce qui arrive alors :
// l'ordre du modèle est gardé.
//
// Ordre dans un cycle, celui des publications de llp_rx :
// 1. la fin du paquet long ouvert (ou différé) ;
// 2. les pertes, lose() du modèle (rx.py:398-413) : o_evt_short_burst, o_evt_ecc, o_evt_burst sans
//    o_evt_burst_late, et la fin 3, comptée une fois avec son o_evt_burst ;
// 3. l'en-tête court : FS, FE, LS, LE (rx.py:428-538), ou le type réservé (o_evt_dt, sur o_evt_dt_vc).
// Un burst_error tardif (o_evt_burst_late) ne relâche rien : il marque la trame du dernier paquet (late_error).
//
// Deux étages : E range les sorties de llp_rx et classe le DT, S met à jour l'état et sort. Latence 2 cycles depuis
// llp_rx, 3 pour les erreurs d'un paquet long qui finit au cycle de son en-tête.
//
// Variante t2 (prompt 053, timing de llp_trame dans csi2_top), sur llp_trame.v de b09a6a09 (md5 406fc255) : t1 (une
// copie de e_wc par VC, keep), plus trois précalculs hors du chemin de e_wc. Latence et comportement identiques.
// - Distance w_dist (w_num - r_lfn en tournant, 17 bits) rangée à l'étage E (e_dist), contre r_lfn du cycle suivant
//   (écrit ce cycle par un FS de ce VC) : après les pertes du cycle, seule la comparaison à w_marge reste. Au reset,
//   e_wc et r_lfn valent 0 : e_dist vaut 65535.
// - Comparaisons de e_wc rangées à l'étage E : e_wc nul, égal à r_ls_num, égal à r_fnum, contre la valeur de ces
//   registres au cycle suivant (écrits ce cycle par un LS ou un FS de ce VC). Au reset, e_wc et ces registres valent
//   0 : égalités à 1.
// - Pas de ligne : r_pend - r_s_last calculé pour chaque entrée de la table, puis choisi par l'entrée trouvée (la
//   même, dernière trouvée), au lieu de choisir r_s_last puis de soustraire.
// FRAME_WRAP = 1 garde le calcul d'origine de w_dist (8 bits).
//
// Variante t2b (prompt 053, étape 0 : chemin des pertes dans les runs de graine 13 du 045), sur llp_trame.v de
// b09a6a09 (md5 406fc255) : t2, plus les comparaisons à w_marge faites pour chaque valeur possible des pertes du
// cycle. Latence et comportement identiques.
// - w_marge = min(r_lost_since + k, 0xFFFF) + 1, k = r_lfn_v ? w_nb_loss : 0 (0 à 3). e_dist <= w_marge revient à
//   e_dist = 0, ou e_dist - 1 <= 0xFFFF et (e_dist - 1) - r_lost_since <= k ; w_num <= w_marge (w_num non nul) à
//   (w_num - 1) - r_lost_since <= k. Les quatre résultats se calculent sur l'état seul ; les pertes du cycle
//   (fin de paquet, ECC, burst) ne font plus que choisir k, au lieu de passer par l'additionneur, la saturation et
//   les comparaisons sur 17 bits.
// - FRAME_WRAP = 1 garde le calcul d'origine (w_marge et w_dist sur 8 bits).
//
// Variante t4 (prompt 053, décision de la session principale du 29/09 14:02 UTC : latence de trame_* et des compteurs
// de trame +1 cycle acceptée) : t2b, plus l'étage de sortie de t3 (toutes les sorties un cycle plus tard, i_cnt_clear
// compris), plus r_lost_since + k saturé calculé pour k = 0 à 3 sur l'état seul (les pertes du cycle ne font que
// choisir). Toutes les sorties sont celles de l'origine un cycle plus tard.
`ifndef __LLP_TRAME__
`define __LLP_TRAME__
`default_nettype none

module llp_trame #(
    parameter NB_VC         = 4,        // VC suivis, 1 à 4 : un paquet d'un VC au-delà est ignoré
    parameter FRAME_WRAP    = 0,        // 1 : numéro de trame modulo 256, 0 numéro ordinaire (IMX219 supposé, README)
    parameter LINE_DT_SLOTS = 2,        // DT dont les numéros de ligne sont suivis, par VC
    parameter CNT_WIDTH     = 16
) (
    input  wire                     clk,
    input  wire                     rst_n,
    input  wire                     i_hdr_valid,
    input  wire [1:0]               i_hdr_vc,
    input  wire [5:0]               i_hdr_dt,
    input  wire [15:0]              i_hdr_wc,
    input  wire                     i_hdr_short,
    input  wire                     i_end_valid,
    input  wire [1:0]               i_end_status,
    input  wire                     i_evt_ecc,
    input  wire                     i_evt_burst,
    input  wire                     i_evt_burst_late,
    input  wire                     i_evt_short_burst,
    input  wire                     i_evt_dt,
    input  wire [1:0]               i_evt_dt_vc,
    input  wire                     i_cnt_clear,
    output reg                      o_fs,
    output reg                      o_fe,
    output reg                      o_fe_ok,        // avec o_fe : trame fermée sans aucune erreur
    output reg  [1:0]               o_frame_vc,
    output reg  [15:0]              o_frame_number,
    output reg  [6:0]               o_err_hdr,      // voir ERR_* ; erreurs d'un paquet court
    output reg  [1:0]               o_err_hdr_vc,
    output reg  [2:0]               o_err_end,      // voir END_* ; erreurs de la fin d'un paquet long
    output reg  [1:0]               o_err_end_vc,
    output reg  [2:0]               o_loss,         // [0] short_burst, [1] ecc_uncorrectable, [2] burst_error
    output reg  [NB_VC-1:0]         o_loss_mask,    // trames ouvertes, chargées de la perte
    output reg                      o_late,         // burst_error tardif
    output reg  [NB_VC-1:0]         o_late_mask,    // VC de la trame du dernier paquet
    output reg                      o_line_slots_full,
    output wire [CNT_WIDTH-1:0]     o_cnt_frame_ok,
    output wire [CNT_WIDTH-1:0]     o_cnt_frame_err,
    output wire [CNT_WIDTH-1:0]     o_cnt_line_err
);
    // o_err_hdr
    localparam ERR_MISSING_FE  = 0;     // missing_frame_end : FS dans une trame ouverte (chargé à l'ancienne trame)
    localparam ERR_MISSING_FS  = 1;     // missing_frame_start : FE, LS ou LE hors trame
    localparam ERR_FN_SEQUENCE = 2;     // frame_number_sequence
    localparam ERR_FN_MISMATCH = 3;     // frame_number_mismatch
    localparam ERR_EMPTY       = 4;     // empty_frame
    localparam ERR_LINE_SYNC   = 5;     // line_sync_mismatch
    localparam ERR_LN_SEQUENCE = 6;     // line_number_sequence : numéros nuls et non nuls mêlés
    // o_err_end
    localparam END_MISSING_FS  = 0;     // missing_frame_start : ligne image hors trame
    localparam END_LN_SEQUENCE = 1;     // line_number_sequence : pas du numéro de ligne
    localparam END_LINE_LENGTH = 2;     // line_length_mismatch
    localparam S = LINE_DT_SLOTS;

    // --- E : entrées rangées, DT classé ----------------------------------------------------------------------------

    reg        e_hdr_valid;
    reg [1:0]  e_vc;
    reg [5:0]  e_dt;
    reg [15:0] e_wc;
    reg        e_short;
    reg        e_end_valid;
    reg [1:0]  e_end_status;
    reg        e_ecc;
    reg        e_burst;
    reg        e_late;
    reg        e_short_burst;
    reg        e_dt_evt;
    reg [1:0]  e_dt_vc;
    reg        e_payload;                   // classe image ou user defined (_PAYLOAD_CLASSES)
    reg        e_image;
    reg [2:0]  e_raw;                       // 1 RAW6, 2 RAW8, 3 RAW10, 4 RAW12, 5 RAW14, 0 autre
    reg        e_size_ok;                   // payload_size accepte le WC (RAW6, RAW8, RAW10)

`include "llp_pix_regles.vh"

    // Rang de la largeur de ligne suivie : 1 RAW6, 2 RAW8, 3 RAW10, 4 RAW12, 5 RAW14, 0 pour un type non dépaqueté
    function automatic [2:0] rang_raw(input [2:0] fmt);
        case (fmt)
            FMT_RAW6:  rang_raw = 3'd1;
            FMT_RAW8:  rang_raw = 3'd2;
            FMT_RAW10: rang_raw = 3'd3;
            FMT_RAW12: rang_raw = 3'd4;
            FMT_RAW14: rang_raw = 3'd5;
            default:   rang_raw = 3'd0;
        endcase
    endfunction

    // Classe IMAGE de mipi_csi2.packet : 0x18 à 0x1A, 0x1C à 0x1F, 0x20 à 0x24, 0x28 à 0x2D
    function automatic est_image(input [5:0] dt);
        est_image = (dt >= 6'h18 && dt <= 6'h24 && dt != 6'h1B) || (dt >= 6'h28 && dt <= 6'h2D);
    endfunction

    (* keep *)
    always @(posedge clk or negedge rst_n)
        if (!rst_n) begin
            e_hdr_valid   <= 1'b0;
            e_vc          <= 2'd0;
            e_dt          <= 6'd0;
            e_wc          <= 16'd0;
            e_short       <= 1'b0;
            e_end_valid   <= 1'b0;
            e_end_status  <= 2'd0;
            e_ecc         <= 1'b0;
            e_burst       <= 1'b0;
            e_late        <= 1'b0;
            e_short_burst <= 1'b0;
            e_dt_evt      <= 1'b0;
            e_dt_vc       <= 2'd0;
            e_payload     <= 1'b0;
            e_image       <= 1'b0;
            e_raw         <= 3'd0;
            e_size_ok     <= 1'b0;
        end else begin
            e_hdr_valid   <= i_hdr_valid;
            e_short       <= i_hdr_short;
            e_end_valid   <= i_end_valid;
            e_end_status  <= i_end_status;
            e_ecc         <= i_evt_ecc;
            e_burst       <= i_evt_burst;
            e_late        <= i_evt_burst_late;
            e_short_burst <= i_evt_short_burst;
            e_dt_evt      <= i_evt_dt;
            e_dt_vc       <= i_evt_dt_vc;
            if (i_hdr_valid) begin
                e_vc      <= i_hdr_vc;
                e_dt      <= i_hdr_dt;
                e_wc      <= i_hdr_wc;
                e_payload <= est_image(i_hdr_dt) || i_hdr_dt[5:3] == 3'b110;
                e_image   <= est_image(i_hdr_dt);
                e_raw     <= rang_raw(format_of(i_hdr_dt));
                e_size_ok <= !size_bad(format_of(i_hdr_dt), i_hdr_wc);
            end
        end

    // --- S : paquet long ouvert, événements du cycle ----------------------------------------------------------------

    reg        r_pk_valid;                  // paquet long dont la fin n'est pas encore arrivée
    reg        r_pk_defer;                  // sa fin est arrivée avec son en-tête : à appliquer ce cycle
    reg [1:0]  r_pk_defer_status;
    reg [1:0]  r_pk_vc;
    reg [5:0]  r_pk_dt;
    reg [15:0] r_pk_wc;
    reg        r_pk_payload;
    reg        r_pk_image;
    reg [2:0]  r_pk_raw;
    reg        r_pk_size_ok;
    reg [NB_VC-1:0] r_lr_mask;              // trames du dernier paquet (_last_report)

    wire       w_hdr_long = e_hdr_valid & ~e_short;
    // 1. fin appliquée ce cycle : différée, ou fin du paquet ouvert avant ce cycle
    wire       w_end_prev = e_end_valid & r_pk_valid & ~r_pk_defer;
    wire       w_e1       = r_pk_defer | w_end_prev;
    wire [1:0] w_e1_st    = r_pk_defer ? r_pk_defer_status : e_end_status;
    wire       w_e1_perte = w_e1 & (w_e1_st == 2'd3);
    wire       w_e1_bon   = w_e1 & (w_e1_st != 2'd3);
    // fin au cycle de son propre en-tête : différée
    wire       w_own_end  = e_end_valid & w_hdr_long & ~w_end_prev;
    // 2. pertes
    wire       w_loss_short = e_short_burst;
    wire       w_loss_ecc   = e_ecc;
    wire       w_loss_burst = w_e1_perte | (e_burst & ~e_late);
    wire [1:0] w_nb_loss    = {1'b0, w_loss_short} + {1'b0, w_loss_ecc} + {1'b0, w_loss_burst};
    wire       w_late       = e_burst & e_late;
    // 3. en-tête court
    wire       w_sh         = e_hdr_valid & e_short;
    wire       w_fs         = w_sh & (e_dt == 6'h00);
    wire       w_fe         = w_sh & (e_dt == 6'h01);
    wire       w_ls         = w_sh & (e_dt == 6'h02);
    wire       w_le         = w_sh & (e_dt == 6'h03);

    wire [NB_VC-1:0] w_open;                // trames ouvertes avant ce cycle
    wire [NB_VC*7-1:0] w_err_hdr;
    wire [NB_VC*3-1:0] w_err_end;
    wire [NB_VC-1:0] w_frame_ok;
    wire [NB_VC-1:0] w_slots_full;

    genvar vc;
    generate
        for (vc = 0; vc < NB_VC; vc = vc + 1)
        begin : g_vc
            localparam [1:0] VC = vc;

            reg        r_open;
            reg [15:0] r_fnum;
            reg        r_bad;               // une erreur est chargée à la trame ouverte
            reg        r_lfn_v;
            reg [15:0] r_lfn;
            reg [15:0] r_lost_since;
            reg        r_ls_v;
            reg [15:0] r_ls_num;
            reg        r_ls_lost;
            reg        r_losses;
            reg        r_seen;
            reg        r_lz_v;
            reg        r_lz_zero;
            reg        r_pend_v;
            reg [15:0] r_pend;
            reg [4:0]  r_w_v;               // largeur connue, RAW6, RAW8, RAW10, RAW12, RAW14
            reg [79:0] r_w;
            reg [S-1:0]    r_s_v;
            reg [6*S-1:0]  r_s_dt;
            reg [S-1:0]    r_s_first_v;
            reg [16*S-1:0] r_s_first;
            reg [16*S-1:0] r_s_last;
            reg [S-1:0]    r_s_step_v;
            reg [17*S-1:0] r_s_step;
            reg [S-1:0]    r_s_lost;

            wire w_moi_e1  = w_e1_bon & (r_pk_vc == VC);
            wire w_moi_sh  = w_sh & (e_vc == VC);
            wire w_moi_dt  = e_dt_evt & (e_dt_vc == VC);
            wire w_moi_late = w_late & r_lr_mask[vc];

            // 1. fin d'un paquet long de ce VC ------------------------------------------------------------------
            wire w_st_ok   = w_e1_st != 2'd2;           // ni tronqué : la ligne est lue (états 0 et 1)
            wire w_ln      = w_moi_e1 & r_open & r_pk_payload;
            wire w_ln_go   = w_ln & r_pend_v;
            wire [S-1:0] w_hit;
            wire [S-1:0] w_libre;
            wire [S-1:0] w_prem_libre;              // première entrée libre, un bit au plus
            wire [17*S-1:0] w_this_s;               // r_pend - r_s_last, par entrée
            genvar sl;
            for (sl = 0; sl < S; sl = sl + 1)
            begin : g_sl
                assign w_hit[sl]   = r_s_v[sl] & (r_s_dt[6*sl +: 6] == r_pk_dt);
                assign w_this_s[17*sl +: 17] = {1'b0, r_pend} - {1'b0, r_s_last[16*sl +: 16]};
                assign w_libre[sl] = ~r_s_v[sl];
                if (sl == 0)
                begin : g_p0
                    assign w_prem_libre[sl] = w_libre[sl];
                end
                else
                begin : g_pn
                    assign w_prem_libre[sl] = w_libre[sl] & ~|w_libre[sl-1:0];
                end
            end
            wire        w_trouve = |w_hit;
            reg  [15:0] w_first_h;
            reg  [16:0] w_this_h, w_step_h;
            reg         w_first_v_h, w_step_v_h, w_lost_h;
            integer     k;
            always @(*) begin
                w_this_h = {1'b0, r_pend}; w_first_h = 16'd0; w_step_h = 17'd0;
                w_first_v_h = 1'b0; w_step_v_h = 1'b0; w_lost_h = 1'b0;
                for (k = 0; k < S; k = k + 1)
                    if (w_hit[k]) begin
                        w_this_h    = w_this_s[17*k +: 17];
                        w_first_h   = r_s_first[16*k +: 16];
                        w_step_h    = r_s_step[17*k +: 17];
                        w_first_v_h = r_s_first_v[k];
                        w_step_v_h  = r_s_step_v[k];
                        w_lost_h    = r_s_lost[k];
                    end
            end
            wire [16:0] w_this   = w_this_h;                                    // signé
            wire        w_ln_err = w_ln_go & w_trouve & ~w_lost_h
                                   & ( $signed(w_this) <= 0
                                     | (w_step_v_h & w_this != w_step_h)
                                     | (~w_step_v_h & w_this == 17'd1 & w_first_v_h & w_first_h != 16'd1));
            wire        w_full   = w_ln_go & ~w_trouve & ~|w_libre;
            wire        w_img_out = w_moi_e1 & ~r_open & r_pk_image & w_st_ok;   // ligne image hors trame
            wire        w_lu     = w_moi_e1 & r_open & r_pk_image & w_st_ok & (r_pk_raw != 3'd0);
            reg         w_len_v;
            reg  [15:0] w_len;
            always @(*) begin
                case (r_pk_raw)
                    3'd1:    begin w_len_v = r_w_v[0]; w_len = r_w[15:0];  end
                    3'd2:    begin w_len_v = r_w_v[1]; w_len = r_w[31:16]; end
                    3'd3:    begin w_len_v = r_w_v[2]; w_len = r_w[47:32]; end
                    3'd4:    begin w_len_v = r_w_v[3]; w_len = r_w[63:48]; end
                    default: begin w_len_v = r_w_v[4]; w_len = r_w[79:64]; end
                endcase
            end
            wire        w_len_err = w_lu & r_pk_size_ok & w_len_v & (w_len != r_pk_wc);
            // erreur de paquet chargée à la trame : CRC, troncature, taille (payload_size)
            wire        w_pk_err = w_moi_e1 & r_open
                                   & (w_e1_st != 2'd0 | (r_pk_image & (r_pk_raw != 3'd0) & ~r_pk_size_ok));
            wire        w_bad1   = w_ln_err | w_len_err | w_pk_err;
            wire        w_pend_v1 = r_pend_v & ~w_ln;       // _line_number consomme le LS en attente

            // 2. pertes ----------------------------------------------------------------------------------------
            wire        w_perte  = w_nb_loss != 2'd0;
            wire        w_bad2   = r_bad | w_bad1 | (w_perte & r_open);
            wire        w_losses2 = r_losses | (w_perte & r_open);
            wire        w_ls_lost2 = r_ls_lost | (w_perte & r_open);
            // r_lost_since + k saturé pour k = 0 à 3, sur l'état seul ; les pertes du cycle choisissent k
            wire [16:0] w_lost_k1 = {1'b0, r_lost_since} + 17'd1;
            wire [16:0] w_lost_k2 = {1'b0, r_lost_since} + 17'd2;
            wire [16:0] w_lost_k3 = {1'b0, r_lost_since} + 17'd3;
            reg  [15:0] w_lost2s;                   // saturé
            always @(*)
                case (r_lfn_v ? w_nb_loss : 2'd0)
                    2'd0:    w_lost2s = r_lost_since;
                    2'd1:    w_lost2s = w_lost_k1[16] ? 16'hFFFF : w_lost_k1[15:0];
                    2'd2:    w_lost2s = w_lost_k2[16] ? 16'hFFFF : w_lost_k2[15:0];
                    default: w_lost2s = w_lost_k3[16] ? 16'hFFFF : w_lost_k3[15:0];
                endcase
            wire        w_seen2  = r_seen | w_ln;

            // 3. en-tête court de ce VC --------------------------------------------------------------------------
            wire        w_fs_moi = w_fs & w_moi_sh;
            wire        w_fe_moi = w_fe & w_moi_sh;
            wire        w_ls_moi = w_ls & w_moi_sh;
            wire        w_le_moi = w_le & w_moi_sh;
            // copie de e_wc propre à ce VC (keep : la synthèse ne la fusionne ni avec e_wc ni avec les autres)
            reg [15:0] e_wc_vc;
            (* keep *)
            always @(posedge clk or negedge rst_n)
                if (!rst_n)
                    e_wc_vc <= 16'd0;
                else if (i_hdr_valid)
                    e_wc_vc <= i_hdr_wc;
            wire [15:0] w_num    = e_wc_vc;
            // comparaisons de e_wc rangées à l'étage E, contre r_ls_num et r_fnum du cycle suivant
            reg         e_zero, e_eq_ls, e_eq_fn;
            wire        w_zero   = e_zero;
            wire [15:0] w_wc_suiv = i_hdr_valid ? i_hdr_wc : e_wc_vc;
            wire [15:0] w_ls_suiv = w_ls_moi & r_open ? e_wc_vc : r_ls_num;
            wire [15:0] w_fn_suiv = w_fs_moi ? e_wc_vc : r_fnum;
            always @(posedge clk or negedge rst_n)
                if (!rst_n) begin
                    e_zero <= 1'b1; e_eq_ls <= 1'b1; e_eq_fn <= 1'b1;
                end else begin
                    e_zero  <= w_wc_suiv == 16'd0;
                    e_eq_ls <= w_wc_suiv == w_ls_suiv;
                    e_eq_fn <= w_wc_suiv == w_fn_suiv;
                end
            // Numéros attendus après r_lfn (l. 772-778, _frame_number_expected) : r_lfn + 1 à r_lfn + lost + 1 en
            // tournant de 0xFFFF à 1, ou une remise de 1 à lost + 1. Un 0 reste 0. FRAME_WRAP : modulo 256, 0 ordinaire.
            wire        w_attendu;
            if (FRAME_WRAP)
            begin : g_wrap
                wire [16:0] w_marge  = {1'b0, w_lost2s} + 17'd1;
                wire [16:0] w_dist;
                wire [7:0] w_d8 = w_num[7:0] - r_lfn[7:0];
                assign w_dist    = w_d8 == 8'd0 ? 17'd256 : {9'd0, w_d8};
                assign w_attendu = w_num[15:8] == 8'd0
                                   && (w_dist <= w_marge || (w_num != 16'd0 && {1'b0, w_num} <= w_marge));
            end
            else
            begin : g_strict
                // w_dist rangé à l'étage E, contre r_lfn du cycle suivant ; 65535 au reset (e_wc = r_lfn = 0)
                reg  [16:0] e_dist;
                wire [15:0] w_lfn_suiv = w_fs_moi ? e_wc_vc : r_lfn;
                always @(posedge clk or negedge rst_n)
                    if (!rst_n)
                        e_dist <= 17'd65535;
                    else
                        e_dist <= w_wc_suiv > w_lfn_suiv ? {1'b0, w_wc_suiv} - {1'b0, w_lfn_suiv}
                                                         : {1'b0, w_wc_suiv} + 17'd65535 - {1'b0, w_lfn_suiv};
                // comparaisons à w_marge pour chaque k (0 à 3), sur l'état seul ; les pertes du cycle choisissent k
                wire [16:0] w_dm  = e_dist - 17'd1;
                wire [17:0] w_del = {1'b0, w_dm} - {2'b0, r_lost_since};
                wire [17:0] w_eps = {2'b0, w_num} - 18'd1 - {2'b0, r_lost_since};
                wire [3:0]  w_dans;
                genvar kk;
                for (kk = 0; kk < 4; kk = kk + 1)
                begin : g_k
                    localparam [17:0] K = kk;
                    assign w_dans[kk] = (e_dist == 17'd0) | (~w_dm[16] & ($signed(w_del) <= $signed(K)))
                                        | ($signed(w_eps) <= $signed(K));
                end
                wire [1:0]  w_k = r_lfn_v ? w_nb_loss : 2'd0;
                assign w_attendu = r_lfn == 16'd0 ? w_zero : ~w_zero && w_dans[w_k];
            end

            wire        w_hors   = ~r_open & (w_fe_moi | w_ls_moi | w_le_moi);
            wire        w_e_mfe  = w_fs_moi & r_open;
            wire        w_e_fns  = w_fs_moi & r_lfn_v & ~w_attendu;
            wire        w_e_fnm  = w_fe_moi & r_open & ~e_eq_fn;
            wire        w_e_empty = w_fe_moi & r_open & ~w_losses2 & ~w_seen2;
            wire        w_ls_pb  = (w_ls_moi & r_ls_v) | (w_le_moi & (~r_ls_v | ~e_eq_ls));
            wire        w_e_lsm  = r_open & ((w_fe_moi & r_ls_v & ~w_ls_lost2)
                                           | ((w_ls_moi | w_le_moi) & w_ls_pb & ~w_ls_lost2));
            wire        w_e_lns  = w_ls_moi & r_open & r_lz_v & (w_zero != r_lz_zero);
            wire        w_bad_late = (w_moi_dt | w_moi_late) & r_open;

            assign w_open[vc] = r_open;
            assign w_err_hdr[7*vc +: 7] = {w_e_lns, w_e_lsm, w_e_empty, w_e_fnm, w_e_fns, w_hors, w_e_mfe};
            assign w_err_end[3*vc +: 3] = {w_len_err, w_ln_err, w_img_out};
            assign w_frame_ok[vc] = w_fe_moi & r_open & ~(w_bad2 | w_e_fnm | w_e_lsm | w_e_empty);
            assign w_slots_full[vc] = w_full;

            always @(posedge clk or negedge rst_n)
                if (!rst_n) begin
                    r_open <= 1'b0; r_fnum <= 16'd0; r_bad <= 1'b0; r_lfn_v <= 1'b0; r_lfn <= 16'd0;
                    r_lost_since <= 16'd0; r_ls_v <= 1'b0; r_ls_num <= 16'd0; r_ls_lost <= 1'b0; r_losses <= 1'b0;
                    r_seen <= 1'b0; r_lz_v <= 1'b0; r_lz_zero <= 1'b0; r_pend_v <= 1'b0; r_pend <= 16'd0;
                    r_w_v <= 5'd0; r_w <= 80'd0;
                    r_s_v <= {S{1'b0}}; r_s_dt <= {6*S{1'b0}}; r_s_first_v <= {S{1'b0}}; r_s_first <= {16*S{1'b0}};
                    r_s_last <= {16*S{1'b0}}; r_s_step_v <= {S{1'b0}}; r_s_step <= {17*S{1'b0}}; r_s_lost <= {S{1'b0}};
                end else begin
                    // 1 et 2 : trame en cours
                    r_bad        <= w_bad2 | w_bad_late | w_e_lns | w_e_lsm;   // erreurs de LS et LE : sur la trame
                    r_losses     <= w_losses2;
                    r_ls_lost    <= w_ls_lost2;
                    r_lost_since <= w_lost2s;
                    r_seen       <= w_seen2;
                    // une perte oublie aussi le LS en attente (lose(), mipi-csi d738c80)
                    r_pend_v     <= w_pend_v1 & ~(w_perte & r_open);
                    if (w_ln_go && w_trouve) begin : maj_table
                        integer j;
                        for (j = 0; j < S; j = j + 1)
                            if (w_hit[j]) begin
                                r_s_last[16*j +: 16] <= r_pend;
                                r_s_lost[j]          <= 1'b0;
                                // pas appris seulement s'il croît : un pas nul ou négatif est signalé, jamais appris
                                if (!w_lost_h && !w_step_v_h && !w_this[16] && w_this != 17'd0) begin
                                    r_s_step[17*j +: 17] <= w_this;
                                    r_s_step_v[j]        <= 1'b1;
                                end
                            end
                    end else if (w_ln_go && !w_trouve) begin : ajout_table
                        integer j;
                        for (j = 0; j < S; j = j + 1)
                            if (w_prem_libre[j]) begin
                                r_s_v[j]              <= 1'b1;
                                r_s_dt[6*j +: 6]      <= r_pk_dt;
                                r_s_first_v[j]        <= ~r_losses;
                                r_s_first[16*j +: 16] <= r_pend;
                                r_s_last[16*j +: 16]  <= r_pend;
                                r_s_step_v[j]         <= 1'b0;
                                r_s_lost[j]           <= 1'b0;
                            end
                    end
                    // Les lignes suivantes ne sont pas jugées sur le trou. Une entrée ouverte à ce même cycle par la
                    // fin d'un paquet long (avant la perte) est marquée aussi.
                    if (w_perte && r_open)
                        r_s_lost <= r_s_v | (w_ln_go && !w_trouve ? w_prem_libre : {S{1'b0}});
                    if (w_lu && r_pk_size_ok && !w_len_v) begin
                        case (r_pk_raw)
                            3'd1:    begin r_w_v[0] <= 1'b1; r_w[15:0]  <= r_pk_wc; end
                            3'd2:    begin r_w_v[1] <= 1'b1; r_w[31:16] <= r_pk_wc; end
                            3'd3:    begin r_w_v[2] <= 1'b1; r_w[47:32] <= r_pk_wc; end
                            3'd4:    begin r_w_v[3] <= 1'b1; r_w[63:48] <= r_pk_wc; end
                            default: begin r_w_v[4] <= 1'b1; r_w[79:64] <= r_pk_wc; end
                        endcase
                    end

                    // 3 : en-tête court
                    if (w_fs_moi) begin
                        r_open       <= 1'b1;
                        r_fnum       <= w_num;
                        r_bad        <= w_e_fns;
                        r_lfn_v      <= 1'b1;
                        r_lfn        <= w_num;
                        r_lost_since <= 16'd0;
                        r_ls_v       <= 1'b0;
                        r_ls_lost    <= 1'b0;
                        r_losses     <= 1'b0;
                        r_seen       <= 1'b0;
                        r_lz_v       <= 1'b0;
                        r_pend_v     <= 1'b0;
                        r_w_v        <= 5'd0;
                        r_s_v        <= {S{1'b0}};
                    end
                    if (w_fe_moi)
                        r_open <= 1'b0;
                    if ((w_ls_moi || w_le_moi) && r_open) begin
                        r_ls_lost <= 1'b0;
                        if (w_ls_moi) begin
                            r_ls_v   <= 1'b1;
                            r_ls_num <= w_num;
                            if (!r_lz_v) begin
                                r_lz_v    <= 1'b1;
                                r_lz_zero <= w_zero;
                            end
                            r_pend_v <= ~w_zero;
                            r_pend   <= w_num;
                        end else begin
                            r_ls_v   <= 1'b0;
                            r_pend_v <= 1'b0;
                        end
                    end
                end
        end
    endgenerate

    // --- sorties -------------------------------------------------------------------------------------------------

    // étage q_ : événements de chaque VC et autres sorties, un cycle avant la réduction par OU
    reg  [NB_VC*7-1:0] q_err_hdr;
    reg  [NB_VC*3-1:0] q_err_end;
    reg  [NB_VC-1:0]   q_frame_ok;
    reg  [NB_VC-1:0]   q_slots_full;
    reg                q_fs, q_fe, q_late;
    reg  [1:0]         q_frame_vc, q_err_hdr_vc, q_err_end_vc;
    reg  [15:0]        q_frame_number;
    reg  [2:0]         q_loss;
    reg  [NB_VC-1:0]   q_loss_mask, q_late_mask;
    reg                q_cnt_clear;

    reg  [6:0] w_err_hdr_or;
    reg  [2:0] w_err_end_or;
    integer    v;
    always @(*) begin
        w_err_hdr_or = 7'd0;
        w_err_end_or = 3'd0;
        for (v = 0; v < NB_VC; v = v + 1) begin
            w_err_hdr_or = w_err_hdr_or | q_err_hdr[7*v +: 7];
            w_err_end_or = w_err_end_or | q_err_end[3*v +: 3];
        end
    end

    // Les compteurs lisent les impulsions déjà en bascules (o_err_*, o_fe_ok) : un cycle de plus, et le jugement des
    // erreurs ne s'enchaîne pas avec l'additionneur de 16 bits.
    wire [2:0] w_nb_frame_err = {2'd0, o_err_hdr[ERR_MISSING_FE]} + {2'd0, o_err_hdr[ERR_MISSING_FS]}
                              + {2'd0, o_err_hdr[ERR_FN_SEQUENCE]} + {2'd0, o_err_hdr[ERR_FN_MISMATCH]}
                              + {2'd0, o_err_hdr[ERR_EMPTY]} + {2'd0, o_err_end[END_MISSING_FS]};
    wire [2:0] w_nb_line_err  = {2'd0, o_err_hdr[ERR_LINE_SYNC]} + {2'd0, o_err_hdr[ERR_LN_SEQUENCE]}
                              + {2'd0, o_err_end[END_LN_SEQUENCE]} + {2'd0, o_err_end[END_LINE_LENGTH]};

    // _last_report : trame du dernier paquet ; après une perte, toutes les trames ouvertes
    wire [3:0]       w_hot_hdr = 4'b0001 << e_vc;
    wire [3:0]       w_hot_pk  = 4'b0001 << r_pk_vc;
    wire [3:0]       w_hot_dt  = 4'b0001 << e_dt_vc;
    wire [NB_VC-1:0] w_vc_hdr  = w_hot_hdr[NB_VC-1:0];
    wire [NB_VC-1:0] w_vc_pk   = w_hot_pk[NB_VC-1:0];
    wire [NB_VC-1:0] w_vc_dt   = w_hot_dt[NB_VC-1:0];
    wire [NB_VC-1:0] w_open_fs = w_open | (w_fs ? w_vc_hdr : {NB_VC{1'b0}});

    always @(posedge clk or negedge rst_n)
        if (!rst_n) begin
            r_pk_valid <= 1'b0; r_pk_defer <= 1'b0; r_pk_defer_status <= 2'd0; r_pk_vc <= 2'd0; r_pk_dt <= 6'd0;
            r_pk_wc <= 16'd0; r_pk_payload <= 1'b0; r_pk_image <= 1'b0; r_pk_raw <= 3'd0; r_pk_size_ok <= 1'b0;
            r_lr_mask <= {NB_VC{1'b0}};
            q_err_hdr <= {NB_VC*7{1'b0}}; q_err_end <= {NB_VC*3{1'b0}}; q_frame_ok <= {NB_VC{1'b0}};
            q_slots_full <= {NB_VC{1'b0}};
            q_fs <= 1'b0; q_fe <= 1'b0; q_frame_vc <= 2'd0; q_frame_number <= 16'd0; q_err_hdr_vc <= 2'd0;
            q_err_end_vc <= 2'd0; q_loss <= 3'd0; q_loss_mask <= {NB_VC{1'b0}}; q_late <= 1'b0;
            q_late_mask <= {NB_VC{1'b0}}; q_cnt_clear <= 1'b0;
        end else begin
            // paquet long : ouvert à son en-tête, fermé à sa fin, différé si sa fin arrive avec lui
            r_pk_defer <= w_own_end;
            r_pk_defer_status <= e_end_status;
            if (w_hdr_long) begin
                r_pk_valid   <= ~w_own_end;
                r_pk_vc      <= e_vc;
                r_pk_dt      <= e_dt;
                r_pk_wc      <= e_wc;
                r_pk_payload <= e_payload;
                r_pk_image   <= e_image;
                r_pk_raw     <= e_raw;
                r_pk_size_ok <= e_size_ok;
            end else if (w_e1)
                r_pk_valid <= 1'b0;

            if (w_sh | w_hdr_long)
                r_lr_mask <= w_vc_hdr & (w_fs ? w_open_fs : {NB_VC{1'b1}});
            else if (e_dt_evt)
                r_lr_mask <= w_vc_dt;
            else if (w_nb_loss != 2'd0)
                r_lr_mask <= w_open;
            else if (w_e1_bon)
                r_lr_mask <= w_vc_pk;

            q_fs           <= w_fs & ({30'd0, e_vc} < NB_VC);
            q_fe           <= w_fe & ({30'd0, e_vc} < NB_VC) & |(w_open & w_vc_hdr);
            q_frame_ok     <= w_frame_ok;
            q_frame_vc     <= e_vc;
            q_frame_number <= e_wc;
            q_err_hdr      <= w_err_hdr;
            q_err_hdr_vc   <= e_vc;
            q_err_end      <= w_err_end;
            q_err_end_vc   <= r_pk_vc;
            q_loss         <= {w_loss_burst, w_loss_ecc, w_loss_short};
            q_loss_mask    <= w_open;
            q_late         <= w_late;
            q_late_mask    <= r_lr_mask;
            q_slots_full   <= w_slots_full;
            q_cnt_clear    <= i_cnt_clear;
        end

    always @(posedge clk or negedge rst_n)
        if (!rst_n) begin
            o_fs <= 1'b0; o_fe <= 1'b0; o_fe_ok <= 1'b0; o_frame_vc <= 2'd0; o_frame_number <= 16'd0;
            o_err_hdr <= 7'd0; o_err_hdr_vc <= 2'd0; o_err_end <= 3'd0; o_err_end_vc <= 2'd0;
            o_loss <= 3'd0; o_loss_mask <= {NB_VC{1'b0}}; o_late <= 1'b0; o_late_mask <= {NB_VC{1'b0}};
            o_line_slots_full <= 1'b0;
        end else begin
            o_fs           <= q_fs;
            o_fe           <= q_fe;
            o_fe_ok        <= |q_frame_ok;
            o_frame_vc     <= q_frame_vc;
            o_frame_number <= q_frame_number;
            o_err_hdr      <= w_err_hdr_or;
            o_err_hdr_vc   <= q_err_hdr_vc;
            o_err_end      <= w_err_end_or;
            o_err_end_vc   <= q_err_end_vc;
            o_loss         <= q_loss;
            o_loss_mask    <= q_loss_mask;
            o_late         <= q_late;
            o_late_mask    <= q_late_mask;
            o_line_slots_full <= |q_slots_full;
        end

    // Compteurs collants saturants, remis à zéro par i_cnt_clear ou le reset
    reg [CNT_WIDTH-1:0] r_cnt_ok, r_cnt_frame, r_cnt_line;
    wire [CNT_WIDTH:0]  w_cnt_frame = {1'b0, r_cnt_frame} + {{(CNT_WIDTH-2){1'b0}}, w_nb_frame_err};
    wire [CNT_WIDTH:0]  w_cnt_line  = {1'b0, r_cnt_line} + {{(CNT_WIDTH-2){1'b0}}, w_nb_line_err};

    always @(posedge clk or negedge rst_n)
        if (!rst_n) begin
            r_cnt_ok    <= {CNT_WIDTH{1'b0}};
            r_cnt_frame <= {CNT_WIDTH{1'b0}};
            r_cnt_line  <= {CNT_WIDTH{1'b0}};
        end else if (q_cnt_clear) begin
            r_cnt_ok    <= {CNT_WIDTH{1'b0}};
            r_cnt_frame <= {CNT_WIDTH{1'b0}};
            r_cnt_line  <= {CNT_WIDTH{1'b0}};
        end else begin
            if (o_fe_ok && !(&r_cnt_ok))
                r_cnt_ok <= r_cnt_ok + 1'b1;
            r_cnt_frame <= w_cnt_frame[CNT_WIDTH] ? {CNT_WIDTH{1'b1}} : w_cnt_frame[CNT_WIDTH-1:0];
            r_cnt_line  <= w_cnt_line[CNT_WIDTH] ? {CNT_WIDTH{1'b1}} : w_cnt_line[CNT_WIDTH-1:0];
        end

    assign o_cnt_frame_ok  = r_cnt_ok;
    assign o_cnt_frame_err = r_cnt_frame;
    assign o_cnt_line_err  = r_cnt_line;
endmodule

`default_nettype wire
`endif
