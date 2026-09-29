// Tête du Lane Management : relie les blocs du RTL, pour la synthèse et les bancs d'ensemble.
// Tout est sur Clk Système (choix_equipe.md §1 et §8). Les FIFOs sont dans le PHY (L13, L20) : elles sont hors du module.
// Interfaces à poignée de main registrées (27/09/2026, après routage LibreLane : échec au coin lent dès 200 MHz sur des
// chemins qui finissaient sur les sorties) : un lm_etage à l'entrée TX, un vers la FIFO TX, un en sortie RX. Il ne reste
// qu'une porte entre une bascule et fifo_tx_wr (out_valid et non fifo_tx_full), et le chemin fifo_rx_empty -> fifo_rx_rd
// de la LMF (côté lecture de la FIFO RX : un étage y garderait des mots au-delà de fifo_rx_raz). Latence : +1 cycle par
// étage ; le contenu des mots ne change pas.
// Les variantes des points ouverts restent des paramètres (README.md) ; valeurs par défaut sans choix implicite :
// ce sont celles de la synthèse de référence, à changer par SYNTH_PARAMETERS pour les autres.
//
// Mot de statut (champs TBD, point 3), convention de modèle : STATUT_W bits par lane, HS au bit HS_BIT,
// état de la SM dans [ETAT_LSB +: ETAT_W].
`default_nettype none

module lm_top #(
    parameter REMISE_TAILLE = 0,    // point 6
    parameter LANE_ABSENTE  = 1,    // point 26
    parameter REMISE_RX     = 1,    // point 2
    parameter CODAGE        = 1,    // point 3
    parameter STATUT_W      = 8,
    parameter HS_BIT        = 1,
    parameter ETAT_LSB      = 2,
    parameter ETAT_W        = 6,
    parameter SYNC          = 2,    // bascules de lm_statut_resync avant la double lecture : 2 ou 3 (SYNC3)
    parameter ENABLE_RX_MASQUE = 0  // 1 : la LMF prend le masque comme Enable (SIt, RX4 : masque = Enable figé au repos du
                                    // RX) ; la LDF garde l'entrée enable
) (
    input  wire                  clk,
    input  wire                  rst_n,
    input  wire [3:0]            enable,
    input  wire [3:0]            masque,
    // TX : module CSI-2 -> LDF -> FIFO TX du PHY
    input  wire                  tx_in_valid,
    output wire                  tx_in_ready,
    input  wire [31:0]           tx_in_data,
    input  wire [2:0]            tx_in_nb,
    input  wire                  tx_in_last,
    input  wire [16:0]           tx_in_total,
    output wire                  fifo_tx_wr,
    output wire [31:0]           fifo_tx_wdata,
    output wire [3:0]            fifo_tx_wlanes,
    output wire                  fifo_tx_fin,
    input  wire                  fifo_tx_full,
    output wire [67:0]           tx_tailles,
    output wire                  tx_tailles_valides,
    output wire                  tx_erreur,
    // RX : FIFO RX du PHY -> LMF -> module CSI-2
    input  wire                  fifo_rx_empty,
    output wire                  fifo_rx_rd,
    input  wire [31:0]           fifo_rx_rdata,
    input  wire [3:0]            fifo_rx_rlanes,
    input  wire                  fifo_rx_rsot,      // D1 (a) : étiquettes du mot lu (0 sans L22, faute de source)
    input  wire                  fifo_rx_rerr,
    input  wire                  fifo_rx_rsot_err,
    input  wire                  fifo_rx_rvide,
    output wire                  fifo_rx_raz,
    output wire                  rx_out_valid,
    output wire [31:0]           rx_out_data,
    output wire [2:0]            rx_out_nb,
    output wire                  rx_out_sot,
    output wire                  rx_out_err,
    output wire                  rx_out_sot_err,
    output wire                  rx_erreur_config,
    output wire                  rx_erreur_burst,
    // statut des 4 lanes : domaine du PHY en entrée, resynchronisé en sortie
    input  wire [4*STATUT_W-1:0] statut_phy,
    output wire [4*STATUT_W-1:0] statut,
    output wire [4*ETAT_W-1:0]   etat
);
    // TX : entrée registrée -> LDF -> étage registré -> FIFO TX
    wire        in_valid, in_ready, in_last;
    wire [31:0] in_data;
    wire [2:0]  in_nb;
    wire [16:0] in_total;
    lm_etage #(.W(53)) etage_tx_in (
        .clk(clk), .rst_n(rst_n),
        .in_valid(tx_in_valid), .in_ready(tx_in_ready), .in_data({tx_in_data, tx_in_nb, tx_in_last, tx_in_total}),
        .out_valid(in_valid), .out_ready(in_ready), .out_data({in_data, in_nb, in_last, in_total})
    );

    wire        ldf_wr, ldf_fin, etage_tx_pret, etage_tx_valide;
    wire [31:0] ldf_wdata;
    wire [3:0]  ldf_wlanes;
    // tx_erreur : Enable invalide (niveau), ou battement invalide pris par la LDF (une période ; plan de correction, T9)
    wire ldf_erreur, ldf_entree_invalide;
    assign tx_erreur = ldf_erreur || ldf_entree_invalide;
    lm_ldf_tx #(.REMISE_TAILLE(REMISE_TAILLE)) ldf (
        .clk(clk), .rst_n(rst_n), .enable(enable),
        .in_valid(in_valid), .in_ready(in_ready), .in_data(in_data), .in_nb(in_nb),
        .in_last(in_last), .in_total(in_total),
        .fifo_wr(ldf_wr), .fifo_wdata(ldf_wdata), .fifo_wlanes(ldf_wlanes), .fifo_fin(ldf_fin),
        .fifo_full(!etage_tx_pret),
        .tailles(tx_tailles), .tailles_valides(tx_tailles_valides), .erreur(ldf_erreur),
        .entree_invalide(ldf_entree_invalide)
    );

    // la LDF n'écrit que si l'étage est prêt (fifo_full = !in_ready) : ldf_wr est la poignée de main
    lm_etage #(.W(37)) etage_fifo_tx (
        .clk(clk), .rst_n(rst_n),
        .in_valid(ldf_wr), .in_ready(etage_tx_pret), .in_data({ldf_wdata, ldf_wlanes, ldf_fin}),
        .out_valid(etage_tx_valide), .out_ready(!fifo_tx_full), .out_data({fifo_tx_wdata, fifo_tx_wlanes, fifo_tx_fin})
    );
    assign fifo_tx_wr = etage_tx_valide && !fifo_tx_full;

    // RX : FIFO RX -> LMF -> étage registré -> module CSI-2
    wire        lmf_valid;
    wire [31:0] lmf_data;
    wire [2:0]  lmf_nb;
    wire        lmf_sot, lmf_err, lmf_sot_err;
    lm_lmf_rx #(.LANE_ABSENTE(LANE_ABSENTE)) lmf (
        .clk(clk), .rst_n(rst_n), .enable(ENABLE_RX_MASQUE != 0 ? masque : enable), .masque(masque),
        .fifo_empty(fifo_rx_empty), .fifo_rd(fifo_rx_rd), .fifo_rdata(fifo_rx_rdata), .fifo_rlanes(fifo_rx_rlanes),
        .fifo_rsot(fifo_rx_rsot), .fifo_rerr(fifo_rx_rerr), .fifo_rsot_err(fifo_rx_rsot_err), .fifo_rvide(fifo_rx_rvide),
        .out_valid(lmf_valid), .out_data(lmf_data), .out_nb(lmf_nb),
        .out_sot(lmf_sot), .out_err(lmf_err), .out_sot_err(lmf_sot_err),
        .erreur_config(rx_erreur_config), .erreur_burst(rx_erreur_burst)
    );

    // D11 (choix 6 ; plan de correction, T14) : pas de rx_out_ready, l'étage de sortie RX n'est plus qu'un registre
    reg        sortie_valid;
    reg [37:0] sortie_data;
    always @(posedge clk or negedge rst_n)
        if (!rst_n) begin
            sortie_valid <= 1'b0;
            sortie_data  <= 38'd0;
        end else begin
            sortie_valid <= lmf_valid;
            if (lmf_valid) sortie_data <= {lmf_data, lmf_nb, lmf_sot, lmf_err, lmf_sot_err};
        end
    assign rx_out_valid = sortie_valid;
    assign {rx_out_data, rx_out_nb, rx_out_sot, rx_out_err, rx_out_sot_err} = sortie_data;

    genvar l;
    wire [3:0] hs;
    generate
        for (l = 0; l < 4; l = l + 1) begin : lane
            lm_statut_resync #(.W(STATUT_W), .CODAGE(CODAGE), .ETAT_LSB(ETAT_LSB), .ETAT_W(ETAT_W), .SYNC(SYNC)) resync (
                .clk(clk), .rst_n(rst_n),
                .statut_phy(statut_phy[l*STATUT_W +: STATUT_W]),
                .statut(statut[l*STATUT_W +: STATUT_W]),
                .etat(etat[l*ETAT_W +: ETAT_W])
            );
            assign hs[l] = statut[l*STATUT_W + HS_BIT];
        end
    endgenerate

    // fin du HS : plus aucune lane du masque en HS
    lm_raz_rx #(.STRATEGIE(REMISE_RX)) raz (
        .clk(clk), .rst_n(rst_n), .hs((hs & masque) != 4'd0), .fifo_empty(fifo_rx_empty), .fifo_raz(fifo_rx_raz)
    );
endmodule

`default_nettype wire
