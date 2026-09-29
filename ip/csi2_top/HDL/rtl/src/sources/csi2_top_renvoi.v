// Top CSI-2 complet de la puce, côté numérique (29/09/2026, priorité de Jérémy : « une implémentation complète de MIPI
// CSI-2, placée-routée et mesurée, ensuite on optimise »). Étapes E0 à E2 du plan de
// analyse/reponses/inventaire_csi2_complet.md, en un seul top ; fiche : analyse/reponses/csi2_top.md.
//
// Contenu (provenance exacte, SHA et md5 : sources/manifeste.json, écrit par construit.py) :
// - bloc v3 (29/09/2026, choix 42 et 48 ; rtl/integration/construit.py --bloc v3, fiche analyse/reponses/bloc_v3.md) :
//   SYNC3 (patch SYNC3_bloc_v2.patch de claude/sync3-bloc-v2 6bccdca3 sur le LM et llp_top : SYNC = 3, trois bascules
//   par synchroniseur, ARM_N = 8) et llp_rx nd (registres à forte sortance dupliqués, genere_d.py de
//   claude/llp-rx-timing 9e59b1e8, régénéré sur le llp_rx de ce top). Repli : SYNC = 2 et ARM_N = 11 (paramètres),
//   construit.py --llp-rx v2 (llp_rx sans nd) ;
// - LM : celui du bloc v3 (rtl/integration/sources_v3/lm) : lm_top_l22t_arme de lm-corrections-revue
//   017e91c1 + patchs_lm/ de rtl/integration (27/N2, en-tête, NU1, NU2) + SYNC3, ARM_N = 8 (choix 42 ; 11 à deux
//   bascules, choix 41), REMISE_TAILLE = 1 (choix 30), compteurs et débogage du LM gardés (la variante « sans debug »
//   est abandonnée) ;
// - LLP (E0) : llp_top de llp-pixel 4b089b9e (o_rx_evt_burst_late, o_rx_evt_dt_vc) + série pixel 03+01+02
//   (claude/llp-pixel-patch03 b09a6a09, choix 43) + les 6 patchs LLP du bloc v2 rebasés (patchs_llp/ de ce dossier ;
//   preuves : patchs_llp/preuves.py, équivalence avec le LLP du bloc v2 sur les sorties communes) ;
// - pixel-byte RX (E1) : llp_pix_rx sur les sorties o_rx_hdr/pay/end_* de llp_top (RAW6, 8, 10, 12, 14 ; autres types
//   en octets bruts) ;
// - contrôle de trame (E2) : llp_trame, NB_VC = 4 (choix 47), en parallèle de llp_pix_rx ;
// - pixel-byte TX (E1) : llp_pix_tx devant i_tx_req/pay_* de llp_top : l'application émet paquets courts (FS, FE, LS,
//   LE, génériques) et lignes de pixels par cette seule entrée.
// Choix 47 : pas d'ULPS, pas de CCI ; la sortie pixel sort sur les broches (brochage à venir : ports internes complets
// gardés ici) ; NB_VC = 4.
//
// Horloges : Clk Système (`clk`) partout, sauf l'écriture de la FIFO de tête du LM (W, `clk_w`). Aucun passage
// d'horloge ajouté : pixel-byte et trame sont derrière llp_rx et devant llp_tx, sur Clk Système. Reset : RST_N commun ;
// le LM et llp_top le synchronisent chacun ; lm_sync_reset d'ici donne le même relâchement (SYNC fronts de clk) à
// llp_pix_rx, llp_trame, llp_pix_tx et aux registres de débogage.
//
// Latences (README du LLP) : sorties pixel 1 cycle après llp_rx, soit 4 cycles après le battement du LM ; sorties de
// trame 2 cycles après llp_rx (3 pour les erreurs d'un paquet long fini au cycle de son en-tête).
//
// Renvoi RX -> TX (prompt 056, construit.py --renvoi : ce fichier est csi2_top.v patché par renvoi/csi2_top.patch ;
// fiche analyse/reponses/renvoi_rx_tx.md) : broches statiques renvoi_mode[1:0], changées sous reset. 00 : application,
// tous les chemins d'origine (preuve d'équivalence avec csi2_top.v) ; 01 N1 mots, 10 N2 paquets, 11 N3 pixels : ce que
// reçoit le RX repart par le TX (module renvoi, renvoi/). Hors du mode 00, l'entrée TX de l'application est coupée
// (tx_req_ready et tx_pix_ready à 0).
//
// Codes d'erreur (côté application) :
// - rx_eol_status : 0 bonne ; 1 CRC faux ; 2 tronquée (R3) ; 3 jetée (R8) ; 4 taille hors groupe ;
// - rx_sol_ecc_corrected / rx_sol_sot_err et rx_short_* : drapeaux de l'en-tête (les deux à 1 : ligne douteuse,
//   choix 34) ;
// - trame_err_hdr[6:0] : missing_frame_end, missing_frame_start, frame_number_sequence, frame_number_mismatch,
//   empty_frame, line_sync_mismatch, line_number_sequence ; trame_err_end[2:0] : missing_frame_start,
//   line_number_sequence, line_length_mismatch ; trame_loss[2:0] : short_burst, ecc_uncorrectable, burst_error ;
//   trame_late : burst_error tardif (R9) ; trame_fe_ok : trame fermée sans aucune erreur ;
// - tx_evt_width : largeur ou type refusés (aucun paquet ne part) ; tx_evt_nb : nombre de pixels du battement faux.
//
// Débogage (DEBUG = 1 par défaut ; à 0, ces sorties sont tenues à 0 et leur logique disparaît à la synthèse, les ports
// restent) : dbg_verrou[3:0] (verrou du LM) ; dbg_erreur = OU registré de tx_erreur, err_sync[3:0], erreur_fifo et
// rx_erreur_config du LM ; dbg_evt = OU registré des événements de llp_rx (ecc, burst, short_burst, dt, sot_err) ;
// les 8 compteurs de llp_top (llp_cnt_*) et les 3 de llp_trame (trame_cnt_*). cnt_gel (asynchrone) : 1 fige les
// compteurs de llp_top, la retombée les remet à 0 (patch 03) ; la même retombée, synchronisée ici, remet à 0 ceux de
// llp_trame (qui ne se figent pas).
//
// Limites héritées (lm_llp_top.v, choix 27, 28, 33, 41, 46) : N ∈ {1, 2, 4} lanes ; lane coincée en HS récupérée par un
// reset de l'hôte ; Clk Système 1,001 × W (7,992 ns) ; conditions d'usage du choix 27. Écarts du pixel-byte et de la
// trame au modèle : README du LLP (pas de data_type_mismatch, refus du bourrage en TX, etc.).
`default_nettype none

module csi2_top #(
    // LM : SYNTH_PARAMETERS du bloc v3 (vérifiés par construit.py)
    parameter REMISE_TAILLE = 1,
    parameter LANE_ABSENTE  = 1,
    parameter REMISE_RX     = 1,
    parameter ARM_N         = 8,           // SYNC3 (choix 42) : 11 (choix 41) − 3
    parameter SYNC          = 3,           // SYNC3 (choix 42) : bascules de chaque synchroniseur du LM, de llp_top et
                                           // du reset d'application ; 2 : repli (avec ARM_N = 11)
    parameter STATUT_W      = 3,
    parameter HS_BIT        = 2,
    parameter ETAT_LSB      = 0,
    parameter ETAT_W        = 3,
    parameter CODAGE        = 0,
    // LLP
    parameter LLP_INIT_CYCLES = 20000,
    parameter LLP_CNT_WIDTH   = 16,
    // trame (choix 47 : NB_VC = 4)
    parameter NB_VC           = 4,
    parameter FRAME_WRAP      = 0,
    parameter LINE_DT_SLOTS   = 2,
    parameter TRAME_CNT_WIDTH = 16,
    // débogage
    parameter DEBUG           = 1,
    // renvoi RX -> TX (renvoi/renvoi.v)
    parameter RENVOI_NIVEAUX   = 7,     // niveaux présents : bit 0 N1, bit 1 N2, bit 2 N3
    parameter RENVOI_ERREUR    = 0,     // N2 : 0 E_CRC, 1 E_SUP
    parameter RENVOI_STATUT    = 1,     // paquet générique de statut en fin de trame
    parameter RENVOI_STATUT_VC = 3,
    parameter RENVOI_PREREMPLI = 0,     // octets
    parameter RENVOI_PROF      = 16     // battements du tampon devant le LM
) (
    // Clk Système, reset
    input  wire                         clk,
    input  wire                         rst_n,
    // configuration (broches EN[3:0])
    input  wire [3:0]                   enable,
    // renvoi RX -> TX (broches statiques) : 00 application, 01 N1 mots, 10 N2 paquets, 11 N3 pixels
    input  wire [1:0]                   renvoi_mode,
    // D-PHY RX : horloge de mot W, mots des 4 lanes, HSPR de la SM LP, statut du PHY
    input  wire                         clk_w,
    input  wire [31:0]                  mots,
    input  wire [3:0]                   hspr,
    input  wire [4*STATUT_W-1:0]        statut_phy,
    // D-PHY TX : FIFO TX, initialisation
    output wire                         fifo_tx_wr,
    output wire [31:0]                  fifo_tx_wdata,
    output wire [3:0]                   fifo_tx_wlanes,
    output wire                         fifo_tx_fin,
    input  wire                         fifo_tx_full,
    output wire                         tx_init,
    // application RX : pixels (llp_pix_rx)
    output wire                         rx_sol,
    output wire [1:0]                   rx_sol_vc,
    output wire [5:0]                   rx_sol_dt,
    output wire [15:0]                  rx_sol_wc,
    output wire [2:0]                   rx_sol_fmt,
    output wire                         rx_sol_ecc_corrected,
    output wire                         rx_sol_sot_err,
    output wire                         rx_pix_valid,
    output wire [2:0]                   rx_pix_nb,
    output wire [83:0]                  rx_pix_data,
    output wire                         rx_eol,
    output wire [2:0]                   rx_eol_status,
    output wire                         rx_short_valid,
    output wire [1:0]                   rx_short_vc,
    output wire [5:0]                   rx_short_dt,
    output wire [15:0]                  rx_short_data,
    output wire                         rx_short_ecc_corrected,
    output wire                         rx_short_sot_err,
    // application RX : trame (llp_trame)
    output wire                         trame_fs,
    output wire                         trame_fe,
    output wire                         trame_fe_ok,
    output wire [1:0]                   trame_vc,
    output wire [15:0]                  trame_numero,
    output wire [6:0]                   trame_err_hdr,
    output wire [1:0]                   trame_err_hdr_vc,
    output wire [2:0]                   trame_err_end,
    output wire [1:0]                   trame_err_end_vc,
    output wire [2:0]                   trame_loss,
    output wire [NB_VC-1:0]             trame_loss_mask,
    output wire                         trame_late,
    output wire [NB_VC-1:0]             trame_late_mask,
    output wire                         trame_slots_pleins,
    // application TX : pixels (llp_pix_tx)
    input  wire                         tx_req_valid,
    output wire                         tx_req_ready,
    input  wire [1:0]                   tx_req_vc,
    input  wire [5:0]                   tx_req_dt,
    input  wire [15:0]                  tx_req_width,
    input  wire                         tx_pix_valid,
    output wire                         tx_pix_ready,
    input  wire [111:0]                 tx_pix_data,
    input  wire [3:0]                   tx_pix_nb,
    output wire                         tx_evt_width,
    output wire                         tx_evt_nb,
    output wire                         tx_init_done,
    // débogage (DEBUG)
    output wire [3:0]                   dbg_verrou,
    output wire                         dbg_erreur,
    output wire                         dbg_evt,
    input  wire                         cnt_gel,
    output wire [LLP_CNT_WIDTH-1:0]     llp_cnt_ok,
    output wire [LLP_CNT_WIDTH-1:0]     llp_cnt_ecc_corrected,
    output wire [LLP_CNT_WIDTH-1:0]     llp_cnt_ecc_double,
    output wire [LLP_CNT_WIDTH-1:0]     llp_cnt_crc,
    output wire [LLP_CNT_WIDTH-1:0]     llp_cnt_trunc,
    output wire [LLP_CNT_WIDTH-1:0]     llp_cnt_burst,
    output wire [LLP_CNT_WIDTH-1:0]     llp_cnt_dt,
    output wire [LLP_CNT_WIDTH-1:0]     llp_cnt_sot_err,
    output wire [TRAME_CNT_WIDTH-1:0]   trame_cnt_ok,
    output wire [TRAME_CNT_WIDTH-1:0]   trame_cnt_err,
    output wire [TRAME_CNT_WIDTH-1:0]   trame_cnt_ligne
);
    // REMISE_TAILLE figé à 1 (revue 51, choix 39), comme dans lm_llp_top.v
    generate
        if (REMISE_TAILLE != 1) begin : g_refus_remise_taille
            REMISE_TAILLE_doit_valoir_1_choix_39 refus ();
        end
    endgenerate

    // ------------------------------------------------------------------------------------------------ LM
    // interface LM -> LLP (RX, spec §2.1) et LLP -> LM (TX, spec §4.1)
    wire        rx_out_valid, rx_out_sot, rx_out_err, rx_out_sot_err;
    wire [31:0] rx_out_data;
    wire [2:0]  rx_out_nb;
    wire        tx_in_valid, tx_in_ready, tx_in_last;
    wire [31:0] tx_in_data;
    wire [2:0]  tx_in_nb;
    wire [16:0] tx_in_total;
    // entrée TX du LM : sortie de llp_top (mode 00) ou du renvoi
    wire        lm_in_valid, lm_in_ready, lm_in_last;
    wire [31:0] lm_in_data;
    wire [2:0]  lm_in_nb;
    wire [16:0] lm_in_total;
    wire        rv_tx_valid, rv_tx_last, rv_llp_ready;
    wire [31:0] rv_tx_data;
    wire [2:0]  rv_tx_nb;
    wire [16:0] rv_tx_total;
    wire        renvoi_app = renvoi_mode == 2'b00;
    assign lm_in_valid = renvoi_app ? tx_in_valid : rv_tx_valid;
    assign lm_in_data  = renvoi_app ? tx_in_data  : rv_tx_data;
    assign lm_in_nb    = renvoi_app ? tx_in_nb    : rv_tx_nb;
    assign lm_in_last  = renvoi_app ? tx_in_last  : rv_tx_last;
    assign lm_in_total = renvoi_app ? tx_in_total : rv_tx_total;
    assign tx_in_ready = renvoi_app ? lm_in_ready : rv_llp_ready;
    // débogage du LM
    wire        lm_tx_erreur, lm_erreur_fifo, lm_rx_erreur_config;
    wire [3:0]  lm_verrou, lm_err_sync;

    lm_top_l22t_arme #(
        .REMISE_TAILLE(REMISE_TAILLE), .LANE_ABSENTE(LANE_ABSENTE), .REMISE_RX(REMISE_RX), .ARM_N(ARM_N),
        .STATUT_W(STATUT_W), .HS_BIT(HS_BIT), .ETAT_LSB(ETAT_LSB), .ETAT_W(ETAT_W), .CODAGE(CODAGE), .SYNC(SYNC)
    ) lm (
        .clk(clk), .rst_n(rst_n), .enable(enable), .masque(4'd0),
        .tx_in_valid(lm_in_valid), .tx_in_ready(lm_in_ready), .tx_in_data(lm_in_data), .tx_in_nb(lm_in_nb),
        .tx_in_last(lm_in_last), .tx_in_total(lm_in_total),
        .fifo_tx_wr(fifo_tx_wr), .fifo_tx_wdata(fifo_tx_wdata), .fifo_tx_wlanes(fifo_tx_wlanes),
        .fifo_tx_fin(fifo_tx_fin), .fifo_tx_full(fifo_tx_full),
        .tx_tailles(), .tx_tailles_valides(), .tx_erreur(lm_tx_erreur),
        .clk_w(clk_w), .mots(mots), .hspr(hspr), .verrou(lm_verrou), .err_sync(lm_err_sync),
        .erreur_deskew(), .erreur_fifo(lm_erreur_fifo),
        .rx_out_valid(rx_out_valid), .rx_out_data(rx_out_data), .rx_out_nb(rx_out_nb),
        .rx_out_sot(rx_out_sot), .rx_out_err(rx_out_err), .rx_out_sot_err(rx_out_sot_err),
        .rx_erreur_config(lm_rx_erreur_config), .rx_erreur_burst(),
        .statut_phy(statut_phy), .statut(), .etat()
    );

    // ------------------------------------------------------------------------------------------------ LLP (E0)
    wire        hdr_valid, hdr_short, hdr_ecc_corrected, hdr_sot_err;
    wire [1:0]  hdr_vc;
    wire [5:0]  hdr_dt;
    wire [15:0] hdr_wc;
    wire        pay_valid;
    wire [31:0] pay_data;
    wire [2:0]  pay_nb;
    wire        end_valid;
    wire [1:0]  end_status;
    wire        evt_ecc, evt_burst, evt_burst_late, evt_short_burst, evt_dt, evt_sot_err;
    wire [1:0]  evt_dt_vc;
    wire        ltx_req_valid, ltx_req_ready, ltx_pay_valid, ltx_pay_ready;
    wire [1:0]  ltx_req_vc;
    wire [5:0]  ltx_req_dt;
    wire [15:0] ltx_req_wc;
    wire [31:0] ltx_pay_data;
    wire [2:0]  ltx_pay_nb;
    wire [LLP_CNT_WIDTH-1:0] c_ok, c_ecc_corrected, c_ecc_double, c_crc, c_trunc, c_burst, c_dt, c_sot_err;
    // entrée TX de llp_top : llp_pix_tx (ptx_*), ou le renvoi N2 (n2_*)
    wire        ptx_req_valid, ptx_pay_valid, n2_req_valid, n2_pay_valid;
    wire [1:0]  ptx_req_vc, n2_req_vc;
    wire [5:0]  ptx_req_dt, n2_req_dt;
    wire [15:0] ptx_req_wc, n2_req_wc;
    wire [31:0] ptx_pay_data, n2_pay_data;
    wire [2:0]  ptx_pay_nb, n2_pay_nb;
    wire        renvoi_n2 = renvoi_mode == 2'b10;
    assign ltx_req_valid = renvoi_n2 ? n2_req_valid : ptx_req_valid;
    assign ltx_req_vc    = renvoi_n2 ? n2_req_vc    : ptx_req_vc;
    assign ltx_req_dt    = renvoi_n2 ? n2_req_dt    : ptx_req_dt;
    assign ltx_req_wc    = renvoi_n2 ? n2_req_wc    : ptx_req_wc;
    assign ltx_pay_valid = renvoi_n2 ? n2_pay_valid : ptx_pay_valid;
    assign ltx_pay_data  = renvoi_n2 ? n2_pay_data  : ptx_pay_data;
    assign ltx_pay_nb    = renvoi_n2 ? n2_pay_nb    : ptx_pay_nb;

    // une connexion par ligne, « .port (fil) » : les mutants des bancs (tests/) visent ces lignes
    llp_top #(.INIT_CYCLES(LLP_INIT_CYCLES), .CNT_WIDTH(LLP_CNT_WIDTH), .SYNC_RST(SYNC), .SYNC_GEL(SYNC)) llp (
        .clk                    (clk),
        .rst_n                  (rst_n),
        .rx_out_valid           (rx_out_valid),
        .rx_out_data            (rx_out_data),
        .rx_out_nb              (rx_out_nb),
        .rx_out_sot             (rx_out_sot),
        .rx_out_err             (rx_out_err),
        .rx_out_sot_err         (rx_out_sot_err),
        .tx_in_valid            (tx_in_valid),
        .tx_in_ready            (tx_in_ready),
        .tx_in_data             (tx_in_data),
        .tx_in_nb               (tx_in_nb),
        .tx_in_last             (tx_in_last),
        .tx_in_total            (tx_in_total),
        .tx_init                (tx_init),
        .o_rx_hdr_valid         (hdr_valid),
        .o_rx_hdr_vc            (hdr_vc),
        .o_rx_hdr_dt            (hdr_dt),
        .o_rx_hdr_wc            (hdr_wc),
        .o_rx_hdr_short         (hdr_short),
        .o_rx_hdr_ecc_corrected (hdr_ecc_corrected),
        .o_rx_hdr_sot_err       (hdr_sot_err),
        .o_rx_pay_valid         (pay_valid),
        .o_rx_pay_data          (pay_data),
        .o_rx_pay_nb            (pay_nb),
        .o_rx_end_valid         (end_valid),
        .o_rx_end_status        (end_status),
        .o_rx_evt_ecc           (evt_ecc),
        .o_rx_evt_burst         (evt_burst),
        .o_rx_evt_burst_late    (evt_burst_late),
        .o_rx_evt_short_burst   (evt_short_burst),
        .o_rx_evt_dt            (evt_dt),
        .o_rx_evt_dt_vc         (evt_dt_vc),
        .o_rx_evt_sot_err       (evt_sot_err),
        .i_tx_req_valid         (ltx_req_valid),
        .o_tx_req_ready         (ltx_req_ready),
        .i_tx_req_vc            (ltx_req_vc),
        .i_tx_req_dt            (ltx_req_dt),
        .i_tx_req_wc            (ltx_req_wc),
        .i_tx_pay_valid         (ltx_pay_valid),
        .o_tx_pay_ready         (ltx_pay_ready),
        .i_tx_pay_data          (ltx_pay_data),
        .i_tx_pay_nb            (ltx_pay_nb),
        .o_tx_init_done         (tx_init_done),
        .i_cnt_gel              (cnt_gel),
        .o_cnt_ok               (c_ok),
        .o_cnt_ecc_corrected    (c_ecc_corrected),
        .o_cnt_ecc_double       (c_ecc_double),
        .o_cnt_crc              (c_crc),
        .o_cnt_trunc            (c_trunc),
        .o_cnt_burst            (c_burst),
        .o_cnt_dt               (c_dt),
        .o_cnt_sot_err          (c_sot_err)
    );

    // reset synchronisé des blocs d'application (même relâchement que dans llp_top)
    wire rst_app_n;
    lm_sync_reset #(.SYNC(SYNC)) u_sync_rst (.clk(clk), .rst_n(rst_n), .rst_sync_n(rst_app_n));

    // ------------------------------------------------------------------------------------------------ pixel RX (E1)
    llp_pix_rx pix_rx (
        .clk                    (clk),
        .rst_n                  (rst_app_n),
        .i_hdr_valid            (hdr_valid),
        .i_hdr_vc               (hdr_vc),
        .i_hdr_dt               (hdr_dt),
        .i_hdr_wc               (hdr_wc),
        .i_hdr_short            (hdr_short),
        .i_hdr_ecc_corrected    (hdr_ecc_corrected),
        .i_hdr_sot_err          (hdr_sot_err),
        .i_pay_valid            (pay_valid),
        .i_pay_data             (pay_data),
        .i_pay_nb               (pay_nb),
        .i_end_valid            (end_valid),
        .i_end_status           (end_status),
        .o_sol                  (rx_sol),
        .o_sol_vc               (rx_sol_vc),
        .o_sol_dt               (rx_sol_dt),
        .o_sol_wc               (rx_sol_wc),
        .o_sol_fmt              (rx_sol_fmt),
        .o_sol_ecc_corrected    (rx_sol_ecc_corrected),
        .o_sol_sot_err          (rx_sol_sot_err),
        .o_pix_valid            (rx_pix_valid),
        .o_pix_nb               (rx_pix_nb),
        .o_pix_data             (rx_pix_data),
        .o_eol                  (rx_eol),
        .o_eol_status           (rx_eol_status),
        .o_short_valid          (rx_short_valid),
        .o_short_vc             (rx_short_vc),
        .o_short_dt             (rx_short_dt),
        .o_short_data           (rx_short_data),
        .o_short_ecc_corrected  (rx_short_ecc_corrected),
        .o_short_sot_err        (rx_short_sot_err)
    );

    // ------------------------------------------------------------------------------------------------ trame (E2)
    wire                       trame_clear;
    wire [TRAME_CNT_WIDTH-1:0] t_ok, t_err, t_ligne;

    llp_trame #(.NB_VC(NB_VC), .FRAME_WRAP(FRAME_WRAP), .LINE_DT_SLOTS(LINE_DT_SLOTS),
                .CNT_WIDTH(TRAME_CNT_WIDTH)) trame (
        .clk                    (clk),
        .rst_n                  (rst_app_n),
        .i_hdr_valid            (hdr_valid),
        .i_hdr_vc               (hdr_vc),
        .i_hdr_dt               (hdr_dt),
        .i_hdr_wc               (hdr_wc),
        .i_hdr_short            (hdr_short),
        .i_end_valid            (end_valid),
        .i_end_status           (end_status),
        .i_evt_ecc              (evt_ecc),
        .i_evt_burst            (evt_burst),
        .i_evt_burst_late       (evt_burst_late),
        .i_evt_short_burst      (evt_short_burst),
        .i_evt_dt               (evt_dt),
        .i_evt_dt_vc            (evt_dt_vc),
        .i_cnt_clear            (trame_clear),
        .o_fs                   (trame_fs),
        .o_fe                   (trame_fe),
        .o_fe_ok                (trame_fe_ok),
        .o_frame_vc             (trame_vc),
        .o_frame_number         (trame_numero),
        .o_err_hdr              (trame_err_hdr),
        .o_err_hdr_vc           (trame_err_hdr_vc),
        .o_err_end              (trame_err_end),
        .o_err_end_vc           (trame_err_end_vc),
        .o_loss                 (trame_loss),
        .o_loss_mask            (trame_loss_mask),
        .o_late                 (trame_late),
        .o_late_mask            (trame_late_mask),
        .o_line_slots_full      (trame_slots_pleins),
        .o_cnt_frame_ok         (t_ok),
        .o_cnt_frame_err        (t_err),
        .o_cnt_line_err         (t_ligne)
    );

    // ------------------------------------------------------------------------------------------------ pixel TX (E1)
    // entrée de llp_pix_tx : l'application (mode 00), le renvoi N3 (n3_*), rien sinon
    wire         ptx_i_req_valid, ptx_i_pix_valid, ptx_o_req_ready, ptx_o_pix_ready;
    wire [1:0]   ptx_i_req_vc;
    wire [5:0]   ptx_i_req_dt;
    wire [15:0]  ptx_i_req_width;
    wire [111:0] ptx_i_pix_data;
    wire [3:0]   ptx_i_pix_nb;
    wire         n3_req_valid, n3_pix_valid;
    wire [1:0]   n3_req_vc;
    wire [5:0]   n3_req_dt;
    wire [15:0]  n3_req_width;
    wire [111:0] n3_pix_data;
    wire [3:0]   n3_pix_nb;
    wire         renvoi_n3 = renvoi_mode == 2'b11;
    assign ptx_i_req_valid = renvoi_app ? tx_req_valid : renvoi_n3 & n3_req_valid;
    assign ptx_i_req_vc    = renvoi_app ? tx_req_vc    : n3_req_vc;
    assign ptx_i_req_dt    = renvoi_app ? tx_req_dt    : n3_req_dt;
    assign ptx_i_req_width = renvoi_app ? tx_req_width : n3_req_width;
    assign ptx_i_pix_valid = renvoi_app ? tx_pix_valid : renvoi_n3 & n3_pix_valid;
    assign ptx_i_pix_data  = renvoi_app ? tx_pix_data  : n3_pix_data;
    assign ptx_i_pix_nb    = renvoi_app ? tx_pix_nb    : n3_pix_nb;
    assign tx_req_ready    = renvoi_app & ptx_o_req_ready;
    assign tx_pix_ready    = renvoi_app & ptx_o_pix_ready;

    llp_pix_tx pix_tx (
        .clk                    (clk),
        .rst_n                  (rst_app_n),
        .i_req_valid            (ptx_i_req_valid),
        .o_req_ready            (ptx_o_req_ready),
        .i_req_vc               (ptx_i_req_vc),
        .i_req_dt               (ptx_i_req_dt),
        .i_req_width            (ptx_i_req_width),
        .i_pix_valid            (ptx_i_pix_valid),
        .o_pix_ready            (ptx_o_pix_ready),
        .i_pix_data             (ptx_i_pix_data),
        .i_pix_nb               (ptx_i_pix_nb),
        .o_evt_width            (tx_evt_width),
        .o_evt_nb               (tx_evt_nb),
        .o_llp_req_valid        (ptx_req_valid),
        .i_llp_req_ready        (ltx_req_ready & ~renvoi_n2),
        .o_llp_req_vc           (ptx_req_vc),
        .o_llp_req_dt           (ptx_req_dt),
        .o_llp_req_wc           (ptx_req_wc),
        .o_llp_pay_valid        (ptx_pay_valid),
        .i_llp_pay_ready        (ltx_pay_ready & ~renvoi_n2),
        .o_llp_pay_data         (ptx_pay_data),
        .o_llp_pay_nb           (ptx_pay_nb)
    );

    // ------------------------------------------------------------------------------------------------ renvoi RX -> TX
    wire [LLP_CNT_WIDTH-1:0] rv_cnt_perdus, rv_cnt_marques, rv_cnt_supprimes, rv_cnt_bourres;
    wire [$clog2(RENVOI_PROF):0] rv_tampon_max;

    renvoi #(.NIVEAUX(RENVOI_NIVEAUX), .ERREUR(RENVOI_ERREUR), .STATUT(RENVOI_STATUT), .STATUT_VC(RENVOI_STATUT_VC),
             .PREREMPLI(RENVOI_PREREMPLI), .PROF(RENVOI_PROF), .CNT_W(LLP_CNT_WIDTH)) u_renvoi (
        .clk                    (clk),
        .rst_n                  (rst_app_n),
        .i_mode                 (renvoi_mode),
        .i_rx_valid             (rx_out_valid),
        .i_rx_data              (rx_out_data),
        .i_rx_nb                (rx_out_nb),
        .i_rx_sot               (rx_out_sot),
        .i_rx_err               (rx_out_err),
        .i_hdr_valid            (hdr_valid),
        .i_hdr_vc               (hdr_vc),
        .i_hdr_dt               (hdr_dt),
        .i_hdr_wc               (hdr_wc),
        .i_hdr_short            (hdr_short),
        .i_hdr_ecc_corrected    (hdr_ecc_corrected),
        .i_hdr_sot_err          (hdr_sot_err),
        .i_pay_valid            (pay_valid),
        .i_pay_data             (pay_data),
        .i_pay_nb               (pay_nb),
        .i_end_valid            (end_valid),
        .i_end_status           (end_status),
        .i_sol                  (rx_sol),
        .i_sol_vc               (rx_sol_vc),
        .i_sol_dt               (rx_sol_dt),
        .i_sol_wc               (rx_sol_wc),
        .i_sol_fmt              (rx_sol_fmt),
        .i_pix_valid            (rx_pix_valid),
        .i_pix_nb               (rx_pix_nb),
        .i_pix_data             (rx_pix_data),
        .i_eol                  (rx_eol),
        .i_eol_status           (rx_eol_status),
        .i_short_valid          (rx_short_valid),
        .i_short_vc             (rx_short_vc),
        .i_short_dt             (rx_short_dt),
        .i_short_data           (rx_short_data),
        .i_fe                   (trame_fe),
        .i_fe_ok                (trame_fe_ok),
        .i_fe_vc                (trame_vc),
        .i_err_hdr              (|trame_err_hdr),
        .i_err_end              (|trame_err_end),
        .i_loss                 (|trame_loss),
        .i_late                 (trame_late),
        .i_cnt_llp              ({c_sot_err, c_dt, c_burst, c_trunc, c_crc, c_ecc_double}),
        .i_cnt_trame            (t_err),
        .o_n2_req_valid         (n2_req_valid),
        .i_n2_req_ready         (ltx_req_ready),
        .o_n2_req_vc            (n2_req_vc),
        .o_n2_req_dt            (n2_req_dt),
        .o_n2_req_wc            (n2_req_wc),
        .o_n2_pay_valid         (n2_pay_valid),
        .i_n2_pay_ready         (ltx_pay_ready),
        .o_n2_pay_data          (n2_pay_data),
        .o_n2_pay_nb            (n2_pay_nb),
        .o_n3_req_valid         (n3_req_valid),
        .i_n3_req_ready         (ptx_o_req_ready),
        .o_n3_req_vc            (n3_req_vc),
        .o_n3_req_dt            (n3_req_dt),
        .o_n3_req_width         (n3_req_width),
        .o_n3_pix_valid         (n3_pix_valid),
        .i_n3_pix_ready         (ptx_o_pix_ready),
        .o_n3_pix_data          (n3_pix_data),
        .o_n3_pix_nb            (n3_pix_nb),
        .i_llp_valid            (tx_in_valid),
        .o_llp_ready            (rv_llp_ready),
        .i_llp_data             (tx_in_data),
        .i_llp_nb               (tx_in_nb),
        .i_llp_last             (tx_in_last),
        .i_llp_total            (tx_in_total),
        .o_tx_valid             (rv_tx_valid),
        .i_tx_ready             (lm_in_ready),
        .o_tx_data              (rv_tx_data),
        .o_tx_nb                (rv_tx_nb),
        .o_tx_last              (rv_tx_last),
        .o_tx_total             (rv_tx_total),
        .o_cnt_perdus           (rv_cnt_perdus),
        .o_cnt_marques          (rv_cnt_marques),
        .o_cnt_supprimes        (rv_cnt_supprimes),
        .o_cnt_bourres          (rv_cnt_bourres),
        .o_tampon_max           (rv_tampon_max)
    );

    // ------------------------------------------------------------------------------------------------ débogage
    // cnt_gel : même synchronisation que dans llp_top (SYNC bascules, puis une de retard ; SYNC_GEL du patch SYNC3) ; sa
    // retombée remet à 0 les compteurs de llp_trame
    reg  [SYNC:0] r_gel;
    reg        r_erreur, r_evt;
    always @(posedge clk or negedge rst_app_n)
        if (!rst_app_n) begin
            r_gel    <= {(SYNC+1){1'b0}};
            r_erreur <= 1'b0;
            r_evt    <= 1'b0;
        end else begin
            r_gel    <= {r_gel[SYNC-1:0], cnt_gel};
            r_erreur <= lm_tx_erreur | (|lm_err_sync) | lm_erreur_fifo | lm_rx_erreur_config;
            r_evt    <= evt_ecc | evt_burst | evt_short_burst | evt_dt | evt_sot_err;
        end
    assign trame_clear = r_gel[SYNC] & ~r_gel[SYNC-1];

    generate
        if (DEBUG != 0) begin : g_debug
            assign dbg_verrou            = lm_verrou;
            assign dbg_erreur            = r_erreur;
            assign dbg_evt               = r_evt;
            assign llp_cnt_ok            = c_ok;
            assign llp_cnt_ecc_corrected = c_ecc_corrected;
            assign llp_cnt_ecc_double    = c_ecc_double;
            assign llp_cnt_crc           = c_crc;
            assign llp_cnt_trunc         = c_trunc;
            assign llp_cnt_burst         = c_burst;
            assign llp_cnt_dt            = c_dt;
            assign llp_cnt_sot_err       = c_sot_err;
            assign trame_cnt_ok          = t_ok;
            assign trame_cnt_err         = t_err;
            assign trame_cnt_ligne       = t_ligne;
        end else begin : g_sans_debug
            assign dbg_verrou            = 4'd0;
            assign dbg_erreur            = 1'b0;
            assign dbg_evt               = 1'b0;
            assign llp_cnt_ok            = {LLP_CNT_WIDTH{1'b0}};
            assign llp_cnt_ecc_corrected = {LLP_CNT_WIDTH{1'b0}};
            assign llp_cnt_ecc_double    = {LLP_CNT_WIDTH{1'b0}};
            assign llp_cnt_crc           = {LLP_CNT_WIDTH{1'b0}};
            assign llp_cnt_trunc         = {LLP_CNT_WIDTH{1'b0}};
            assign llp_cnt_burst         = {LLP_CNT_WIDTH{1'b0}};
            assign llp_cnt_dt            = {LLP_CNT_WIDTH{1'b0}};
            assign llp_cnt_sot_err       = {LLP_CNT_WIDTH{1'b0}};
            assign trame_cnt_ok          = {TRAME_CNT_WIDTH{1'b0}};
            assign trame_cnt_err         = {TRAME_CNT_WIDTH{1'b0}};
            assign trame_cnt_ligne       = {TRAME_CNT_WIDTH{1'b0}};
            // non lus sans débogage : la synthèse retire leur logique
            wire w_non_lus = &{1'b0, lm_verrou, r_erreur, r_evt, c_ok, c_ecc_corrected, c_ecc_double, c_crc, c_trunc,
                               c_burst, c_dt, c_sot_err, t_ok, t_err, t_ligne};
        end
    endgenerate
endmodule

`default_nettype wire
