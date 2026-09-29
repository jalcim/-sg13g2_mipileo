// Sommet du LLP CSI-2 : tête RX (llp_rx), tête TX (llp_tx), reset synchronisé et compteurs d'erreurs.
// Côté LM, les ports portent les noms de la spec d'interface (../../spec/interface_lm_llp.md §2.1 et §4.1), pour un
// câblage nom à nom. Côté application, ceux de llp_rx et llp_tx, préfixés rx_ et tx_, sémantique inchangée.
//
// rst_n est asynchrone : son assertion remet tout à zéro sans attendre l'horloge, son relâchement est pris par
// lm_sync_reset (../lm_cdc.v), deux fronts de clk plus tard (spec §1.2). Sous reset : tx_in_valid = 0, tx_init = 1.
//
// llp_rx prend le battement RX du LM dans des bascules d'entrée (ENTREE = 1), après avoir calculé sa part du
// syndrome de l'ECC : sa latence compte un cycle de plus depuis rx_out_*. Sans elles, le chemin de rx_out_sot à
// l'état de llp_rx ne garde que 0,00 ns de setup au coin lent après routage à 7,14 ns (README, mesures).
//
// Compteurs collants saturants de CNT_WIDTH bits, remis à zéro par le reset seul (pas de CCI ni de registre de test
// sur la puce) : chacun avance au front qui suit l'impulsion qu'il compte, et reste à sa valeur maximale.
// Sources (README) : sorties de llp_rx, sauf o_cnt_sot_err, pris sur le battement du LM, indépendamment de l'en-tête.
//
// Côté application TX, une tranche de registre avant (débit plein) sur la requête et sur la charge (revue 36, N36-4) :
// sans elle, le chemin de i_tx_req_wc (retard d'entrée de 20 %) au compte des mots de llp_tx puis à o_req_ready est le
// pire chemin avant placement. Un mot est pris au front où i_tx_*_valid et o_tx_*_ready valent 1, comme avant ;
// o_tx_*_ready = init TX finie, et tranche vide ou llp_tx prêt : portes sur des bascules, sans chemin depuis une
// entrée ; à 0 sous reset et pendant l'init TX, comme sans la tranche.
// La latence TX compte un cycle de plus.
`ifndef __LLP_TOP__
`define __LLP_TOP__
`default_nettype none

module llp_top #(
    parameter INIT_CYCLES = 20000,      // transmis à llp_tx : cycles entre la chute de tx_init et o_tx_init_done
    parameter CNT_WIDTH   = 16,
    parameter SYNC_RST    = 2,          // bascules du relâchement du reset (lm_sync_reset) : 2, ou 3 (SYNC3, revue 43/N10)
    parameter SYNC_GEL    = 2           // bascules de synchronisation de i_cnt_gel : 2, ou 3 (SYNC3, bloc v2)
) (
    input  wire                 clk,
    input  wire                 rst_n,  // asynchrone, actif bas, synchronisé ici
    // LM, RX (spec §2.1)
    input  wire                 rx_out_valid,
    input  wire [31:0]          rx_out_data,
    input  wire [2:0]           rx_out_nb,
    input  wire                 rx_out_sot,
    input  wire                 rx_out_err,
    input  wire                 rx_out_sot_err,
    // LM et PHY, TX (spec §4.1)
    output wire                 tx_in_valid,
    input  wire                 tx_in_ready,
    output wire [31:0]          tx_in_data,
    output wire [2:0]           tx_in_nb,
    output wire                 tx_in_last,
    output wire [16:0]          tx_in_total,
    output wire                 tx_init,
    // application, RX
    output wire                 o_rx_hdr_valid,
    output wire [1:0]           o_rx_hdr_vc,
    output wire [5:0]           o_rx_hdr_dt,
    output wire [15:0]          o_rx_hdr_wc,
    output wire                 o_rx_hdr_short,
    output wire                 o_rx_hdr_ecc_corrected,
    output wire                 o_rx_hdr_sot_err,
    output wire                 o_rx_pay_valid,
    output wire [31:0]          o_rx_pay_data,
    output wire [2:0]           o_rx_pay_nb,
    output wire                 o_rx_end_valid,
    output wire [1:0]           o_rx_end_status,
    output wire                 o_rx_evt_ecc,
    output wire                 o_rx_evt_burst,
    output wire                 o_rx_evt_burst_late,
    output wire                 o_rx_evt_short_burst,
    output wire                 o_rx_evt_dt,
    output wire [1:0]           o_rx_evt_dt_vc,
    output wire                 o_rx_evt_sot_err,       // rx_out_sot_err sur un sot pris, avec ou sans en-tête (R11)
    // application, TX
    input  wire                 i_tx_req_valid,
    output wire                 o_tx_req_ready,
    input  wire [1:0]           i_tx_req_vc,
    input  wire [5:0]           i_tx_req_dt,
    input  wire [15:0]          i_tx_req_wc,
    input  wire                 i_tx_pay_valid,
    output wire                 o_tx_pay_ready,
    input  wire [31:0]          i_tx_pay_data,
    input  wire [2:0]           i_tx_pay_nb,
    output wire                 o_tx_init_done,
    // compteurs
    input  wire                 i_cnt_gel,              // asynchrone : 1 fige les compteurs, la retombée les remet à 0
    output wire [CNT_WIDTH-1:0] o_cnt_ok,               // paquets longs finis en état 0, paquets courts publiés
    output wire [CNT_WIDTH-1:0] o_cnt_ecc_corrected,    // en-têtes publiés dont l'ECC a corrigé un bit
    output wire [CNT_WIDTH-1:0] o_cnt_ecc_double,       // en-têtes non corrigeables (o_rx_evt_ecc)
    output wire [CNT_WIDTH-1:0] o_cnt_crc,              // paquets finis en état 1
    output wire [CNT_WIDTH-1:0] o_cnt_trunc,            // paquets finis en état 2, et o_rx_evt_short_burst
    output wire [CNT_WIDTH-1:0] o_cnt_burst,            // bursts en erreur ou vides (o_rx_evt_burst)
    output wire [CNT_WIDTH-1:0] o_cnt_dt,               // types réservés (o_rx_evt_dt)
    output wire [CNT_WIDTH-1:0] o_cnt_sot_err           // battements valides portant rx_out_sot_err
);
    localparam NB_CNT = 8;

    wire                        w_rst_n;
    wire [NB_CNT-1:0]           w_inc;
    wire [NB_CNT*CNT_WIDTH-1:0] w_cnt;
    reg                         r_sot_err;          // battement valide portant rx_out_sot_err, un cycle plus tard
    // N36-1 : battement vide (sot, err, nb = 0 : burst perdu, spec §2.5) de rx_out_*, suivi sur la latence RX de
    // llp_top (3 cycles avec ENTREE = 1) pour masquer en o_cnt_trunc la fin 2 ou le court qu'il provoque au même
    // cycle que son o_rx_evt_burst : un burst perdu ne compte qu'une fois, en o_cnt_burst (R10)
    reg  [2:0]                  r_vide;
    // N36-2 et N36-7 : i_cnt_gel synchronisé (r_gel[SYNC_GEL-1:0]) et retardé d'un cycle (r_gel[SYNC_GEL]), pour sa
    // retombée ; SYNC_GEL = 2 : RTL d'avant (r_gel[1:0], r_gel[2])
    reg  [SYNC_GEL:0]           r_gel;
    wire                        w_gel = r_gel[SYNC_GEL-1];
    wire                        w_raz = r_gel[SYNC_GEL] & ~r_gel[SYNC_GEL-1];
    // tranche d'entrée TX (N36-4) : requête et charge de l'application, un cycle plus tard
    reg                         r_req_valid;
    reg  [1:0]                  r_req_vc;
    reg  [5:0]                  r_req_dt;
    reg  [15:0]                 r_req_wc;
    reg                         r_pay_valid;
    reg  [31:0]                 r_pay_data;
    reg  [2:0]                  r_pay_nb;
    wire                        w_req_ready;            // o_req_ready de llp_tx
    wire                        w_pay_ready;            // o_pay_ready de llp_tx

    lm_sync_reset #(.SYNC(SYNC_RST)) u_sync_rst (
        .clk        (clk),
        .rst_n      (rst_n),
        .rst_sync_n (w_rst_n)
    );

    // Même retard que les bascules d'entrée de llp_rx
    always @(posedge clk or negedge w_rst_n)
        if (!w_rst_n) begin
            r_sot_err <= 1'b0;
            r_vide    <= 3'b000;
            r_gel     <= {(SYNC_GEL+1){1'b0}};
        end else begin
            r_sot_err <= rx_out_valid & rx_out_sot_err;
            r_vide    <= {r_vide[1:0], rx_out_valid & rx_out_sot & rx_out_err & (rx_out_nb == 3'd0)};
            r_gel     <= {r_gel[SYNC_GEL-1:0], i_cnt_gel};
        end

    llp_rx #(
        .ENTREE (1)
    ) u_rx (
        .clk                 (clk),
        .rst_n               (w_rst_n),
        .i_rx_valid          (rx_out_valid),
        .i_rx_data           (rx_out_data),
        .i_rx_nb             (rx_out_nb),
        .i_rx_sot            (rx_out_sot),
        .i_rx_err            (rx_out_err),
        .i_rx_sot_err        (rx_out_sot_err),
        .o_hdr_valid         (o_rx_hdr_valid),
        .o_hdr_vc            (o_rx_hdr_vc),
        .o_hdr_dt            (o_rx_hdr_dt),
        .o_hdr_wc            (o_rx_hdr_wc),
        .o_hdr_short         (o_rx_hdr_short),
        .o_hdr_ecc_corrected (o_rx_hdr_ecc_corrected),
        .o_hdr_sot_err       (o_rx_hdr_sot_err),
        .o_pay_valid         (o_rx_pay_valid),
        .o_pay_data          (o_rx_pay_data),
        .o_pay_nb            (o_rx_pay_nb),
        .o_end_valid         (o_rx_end_valid),
        .o_end_status        (o_rx_end_status),
        .o_evt_ecc           (o_rx_evt_ecc),
        .o_evt_burst         (o_rx_evt_burst),
        .o_evt_burst_late    (o_rx_evt_burst_late),
        .o_evt_short_burst   (o_rx_evt_short_burst),
        .o_evt_dt            (o_rx_evt_dt),
        .o_evt_dt_vc         (o_rx_evt_dt_vc),
        .o_evt_sot_err       (o_rx_evt_sot_err)
    );

    llp_tx #(
        .INIT_CYCLES (INIT_CYCLES)
    ) u_tx (
        .clk         (clk),
        .rst_n       (w_rst_n),
        .i_req_valid (r_req_valid),
        .o_req_ready (w_req_ready),
        .i_req_vc    (r_req_vc),
        .i_req_dt    (r_req_dt),
        .i_req_wc    (r_req_wc),
        .i_pay_valid (r_pay_valid),
        .o_pay_ready (w_pay_ready),
        .i_pay_data  (r_pay_data),
        .i_pay_nb    (r_pay_nb),
        .o_init_done (o_tx_init_done),
        .o_tx_valid  (tx_in_valid),
        .i_tx_ready  (tx_in_ready),
        .o_tx_data   (tx_in_data),
        .o_tx_nb     (tx_in_nb),
        .o_tx_last   (tx_in_last),
        .o_tx_total  (tx_in_total),
        .o_tx_init   (tx_init)
    );

    // prêt seulement après l'initialisation TX (o_tx_init_done, bascule remise à 0 par le reset) : sous reset et
    // pendant les INIT_CYCLES, rien n'est pris, comme sans la tranche (README de llp_tx)
    assign o_tx_req_ready = o_tx_init_done & (~r_req_valid | w_req_ready);
    assign o_tx_pay_ready = o_tx_init_done & (~r_pay_valid | w_pay_ready);

    always @(posedge clk or negedge w_rst_n)
        if (!w_rst_n) begin
            r_req_valid <= 1'b0;
            r_req_vc    <= 2'd0;
            r_req_dt    <= 6'd0;
            r_req_wc    <= 16'd0;
            r_pay_valid <= 1'b0;
            r_pay_data  <= 32'd0;
            r_pay_nb    <= 3'd0;
        end else begin
            if (o_tx_req_ready) begin
                r_req_valid <= i_tx_req_valid;
                r_req_vc    <= i_tx_req_vc;
                r_req_dt    <= i_tx_req_dt;
                r_req_wc    <= i_tx_req_wc;
            end
            if (o_tx_pay_ready) begin
                r_pay_valid <= i_tx_pay_valid;
                r_pay_data  <= i_tx_pay_data;
                r_pay_nb    <= i_tx_pay_nb;
            end
        end

    // Paquets bons : un paquet court n'a pas de o_rx_end_valid, son en-tête publié compte. Une fin 0 vient du battement
    // qui porte le pied d'un paquet long, un en-tête court d'un battement sot : deux battements, jamais au même cycle.
    // Une fin en état 2 et o_rx_evt_short_burst viennent d'un même battement sot (même latence), l'une si un paquet
    // long est ouvert, l'autre si un en-tête est en cours : jamais au même cycle, un seul incrément suffit.
    // Sur le battement vide (r_vide[2], même cycle que son o_rx_evt_burst), la coupure est celle du burst perdu, déjà
    // comptée en o_cnt_burst : o_cnt_trunc ne compte pas (N36-1). Un sot ordinaire, ou un sot marqué err qui porte des
    // octets, sur un paquet long ouvert, reste compté : c'est une perte que le LM n'a pas marquée (P46).
    assign w_inc = {r_sot_err,
                    o_rx_evt_dt,
                    o_rx_evt_burst,
                    ((o_rx_end_valid & (o_rx_end_status == 2'd2)) | o_rx_evt_short_burst) & ~r_vide[2],
                    o_rx_end_valid & (o_rx_end_status == 2'd1),
                    o_rx_evt_ecc,
                    o_rx_hdr_valid & o_rx_hdr_ecc_corrected,
                    (o_rx_end_valid & (o_rx_end_status == 2'd0)) | (o_rx_hdr_valid & o_rx_hdr_short)};

    genvar rang;
    generate
        for (rang = 0; rang < NB_CNT; rang = rang + 1)
        begin : g_cnt
            reg [CNT_WIDTH-1:0] r_cnt;

            always @(posedge clk or negedge w_rst_n)
                if (!w_rst_n)
                    r_cnt <= {CNT_WIDTH{1'b0}};
                else if (w_raz)
                    r_cnt <= {CNT_WIDTH{1'b0}};
                else if (w_inc[rang] & ~w_gel & ~&r_cnt)
                    r_cnt <= r_cnt + 1'b1;

            assign w_cnt[rang*CNT_WIDTH +: CNT_WIDTH] = r_cnt;
        end
    endgenerate

    assign o_cnt_ok            = w_cnt[0*CNT_WIDTH +: CNT_WIDTH];
    assign o_cnt_ecc_corrected = w_cnt[1*CNT_WIDTH +: CNT_WIDTH];
    assign o_cnt_ecc_double    = w_cnt[2*CNT_WIDTH +: CNT_WIDTH];
    assign o_cnt_crc           = w_cnt[3*CNT_WIDTH +: CNT_WIDTH];
    assign o_cnt_trunc         = w_cnt[4*CNT_WIDTH +: CNT_WIDTH];
    assign o_cnt_burst         = w_cnt[5*CNT_WIDTH +: CNT_WIDTH];
    assign o_cnt_dt            = w_cnt[6*CNT_WIDTH +: CNT_WIDTH];
    assign o_cnt_sot_err       = w_cnt[7*CNT_WIDTH +: CNT_WIDTH];
endmodule

`default_nettype wire
`endif
