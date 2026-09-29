// SIt armé (28/09/2026) : lm_top_l22t (SIt, top retenu) et une instance de lm_armement par lane (choix 9 de
// connaissances/decisions.md : armement de `recherche` par un compteur sur Clk Système, N = 13 à 125 MHz).
// Nouveau fichier : lm_top_l22t.v et lm_armement.v ne changent pas.
//
// Ports : ceux de lm_top_l22t, sauf l'entrée `recherche`, remplacée par `hspr` (HSPR de la SM LP du PHY, LP-00 détecté,
// asynchrone, un bit par lane ; il retombe au retour en LP-11).
// N fixe par le paramètre ARM_N, sans entrée `consigne` (choix 9 bis révisé du 28/09/2026 : pas de broche en plus, pas
// de registre de configuration). Le mode PROGRAMMABLE de lm_armement.v reste une option documentée, non utilisée ici.
// Plage de Clk Système où N = 13 tient : mesurée sur ce top (tests/armement/balayage_fsys.py, tempo_recherche.md).
// Dans le mot de statut retenu (point 3 du 27/09 : STOP, HSRQ, HSPR, HS_BIT = 2), `hspr[l]` est le même fil que le bit
// HS_BIT du statut de la lane l : l'intégrateur relie les deux ; il est gardé comme port à part pour ne rien supposer du
// format de `statut_phy`.
//
// Chaîne de `recherche`, par lane :
//   hspr (asynchrone) -> lm_armement (2 bascules sur Clk Système, décompteur, registre) -> recherche (Clk Système)
//   -> lm_top_l22t : 2 bascules sur W (RECHERCHE_SYNC = 1), puis la FIFO asynchrone avec les mots.
// Latences (lm_armement.v, vérifiées par tests/armement/tb_lm_armement.v), T = période de Clk Système, t_d = instant où
// HSPR change : montée de `recherche` dans [t_d + (N + 1) T ; t_d + (N + 2) T], soit 112 à 120 ns pour N = 13 à
// 125 MHz ; chute dans [t_d + 2 T ; t_d + 3 T].
// Conditions d'emploi :
// - Clk Système au moins aussi rapide que W (condition de lm_top_l22t) : à 125 MHz, 1 000 Mb/s par lane au plus ;
// - N se règle avec Clk Système (l'arrivée de `recherche` compte en périodes de Clk Système) : garder (N + 1) T dans la
//   fenêtre d'armement [G + L_d − 9 UI ; S − 12 UI + L_d[ (lm_armement.v) ; N = 21 à 200 MHz donne 110 à 115 ns ;
// - la latence de HSPR depuis le début de T_HS-PREPARE s'ajoute (filtre de persistance D_FILT de LP_SM.vhd compris) :
//   elle n'est pas figée (TODO/02_lm_armement.md).
`default_nettype none

module lm_top_l22t_arme #(
    parameter REMISE_TAILLE    = 0,     // point 6
    parameter LANE_ABSENTE     = 1,     // point 26
    parameter REMISE_RX        = 1,     // point 2
    parameter CODAGE           = 0,     // point 3 ; statut du choix 3 par défaut (montage figé, choix 28)
    parameter STATUT_W         = 3,
    parameter HS_BIT           = 2,
    parameter ETAT_LSB         = 0,
    parameter ETAT_W           = 3,
    parameter FIFO_A           = 3,     // FIFO asynchrone de 2^FIFO_A mots
    parameter ARM_LARGEUR      = 6,     // largeur du décompteur de lm_armement
    parameter ARM_N            = 13,    // N, en périodes de Clk Système (13 à 125 MHz)
    parameter SYNC             = 3      // SYNC3 (analyse/reponses/sync3.md) : bascules de chaque synchroniseur ; 2 : RTL
                                        // d'avant. Avec SYNC = 3, ARM_N se recale (voir sync3.md)
) (
    input  wire                   clk,
    input  wire                   rst_n,
    input  wire [3:0]             enable,
    input  wire [3:0]             masque,
    input  wire                   tx_in_valid,
    output wire                   tx_in_ready,
    input  wire [31:0]            tx_in_data,
    input  wire [2:0]             tx_in_nb,
    input  wire                   tx_in_last,
    input  wire [16:0]            tx_in_total,
    output wire                   fifo_tx_wr,
    output wire [31:0]            fifo_tx_wdata,
    output wire [3:0]             fifo_tx_wlanes,
    output wire                   fifo_tx_fin,
    input  wire                   fifo_tx_full,
    output wire [67:0]            tx_tailles,
    output wire                   tx_tailles_valides,
    output wire                   tx_erreur,
    input  wire                   clk_w,
    input  wire [31:0]            mots,          // domaine W
    input  wire [3:0]             hspr,          // asynchrone : HSPR de la SM LP du PHY, par lane
    output wire [3:0]             verrou,        // domaine Clk Système
    output wire [3:0]             err_sync,      // domaine Clk Système, une période
    output wire                   erreur_deskew, // domaine Clk Système, une période
    output wire                   erreur_fifo,   // domaine Clk Système, collante jusqu'au reset
    output wire                   rx_out_valid,
    output wire [31:0]            rx_out_data,
    output wire [2:0]             rx_out_nb,
    output wire                   rx_out_sot,       // D1 (a), comme lm_top_l22t (plan de correction, T11)
    output wire                   rx_out_err,
    output wire                   rx_out_sot_err,
    output wire                   rx_erreur_config,
    output wire                   rx_erreur_burst,
    input  wire [4*STATUT_W-1:0]  statut_phy,
    output wire [4*STATUT_W-1:0]  statut,
    output wire [4*ETAT_W-1:0]    etat
);
    wire       rst_arm_n;
    wire [3:0] recherche;                       // domaine Clk Système

    // reset des compteurs : asynchrone à l'assertion, relâché sur Clk Système (comme dans lm_top_l22t)
    lm_sync_reset #(.SYNC(SYNC)) sync_rst_arm (.clk(clk), .rst_n(rst_n), .rst_sync_n(rst_arm_n));

    genvar l;
    generate
        for (l = 0; l < 4; l = l + 1) begin : armement
            lm_armement #(.LARGEUR(ARM_LARGEUR), .N_DEFAUT(ARM_N), .PROGRAMMABLE(0), .SYNC(SYNC)) arm (
                .clk(clk), .rst_n(rst_arm_n), .consigne({ARM_LARGEUR{1'b0}}), .hspr(hspr[l]), .recherche(recherche[l])
            );
        end
    endgenerate

    lm_top_l22t #(
        .REMISE_TAILLE(REMISE_TAILLE), .LANE_ABSENTE(LANE_ABSENTE), .REMISE_RX(REMISE_RX), .CODAGE(CODAGE),
        .STATUT_W(STATUT_W), .HS_BIT(HS_BIT), .ETAT_LSB(ETAT_LSB), .ETAT_W(ETAT_W), .FIFO_A(FIFO_A),
        .RECHERCHE_SYNC(1),                     // recherche vient de Clk Système : SYNC bascules sur W
        .SYNC(SYNC)
    ) sit (
        .clk(clk), .rst_n(rst_n), .enable(enable), .masque(masque),
        .tx_in_valid(tx_in_valid), .tx_in_ready(tx_in_ready), .tx_in_data(tx_in_data), .tx_in_nb(tx_in_nb),
        .tx_in_last(tx_in_last), .tx_in_total(tx_in_total),
        .fifo_tx_wr(fifo_tx_wr), .fifo_tx_wdata(fifo_tx_wdata), .fifo_tx_wlanes(fifo_tx_wlanes),
        .fifo_tx_fin(fifo_tx_fin), .fifo_tx_full(fifo_tx_full),
        .tx_tailles(tx_tailles), .tx_tailles_valides(tx_tailles_valides), .tx_erreur(tx_erreur),
        .clk_w(clk_w), .mots(mots), .recherche(recherche), .verrou(verrou), .err_sync(err_sync),
        .erreur_deskew(erreur_deskew), .erreur_fifo(erreur_fifo),
        .rx_out_valid(rx_out_valid), .rx_out_data(rx_out_data), .rx_out_nb(rx_out_nb),
        .rx_out_sot(rx_out_sot), .rx_out_err(rx_out_err), .rx_out_sot_err(rx_out_sot_err),
        .rx_erreur_config(rx_erreur_config), .rx_erreur_burst(rx_erreur_burst),
        .statut_phy(statut_phy), .statut(statut), .etat(etat)
    );
endmodule

`default_nettype wire
