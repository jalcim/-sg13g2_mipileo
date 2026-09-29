// Top de test de llp_top. Côté RX, les bus plats de tb_llp_rx (i_beat et o_mon, mêmes positions) ; côté TX, les noms
// de tb_llp_tx ; les huit compteurs en un bus plat o_cnt, dans l'ordre de test_llp_top.COMPTEURS.
// INIT_CYCLES réduit comme dans tb_llp_tx ; CNT_WIDTH réduit par run_llp.py pour le banc de saturation.
`default_nettype none

module tb_llp_top #(
    parameter INIT_CYCLES = 37,
    parameter CNT_WIDTH   = 16
) (
    input  wire                   clk,
    input  wire                   rst_n,
    input  wire [38:0]            i_beat,       // {sot_err, err, sot, valid, nb[2:0], data[31:0]}
    output wire [73:0]            o_mon,        // sorties RX de llp_top, o_rx_hdr_valid en [0]
    input  wire                   i_req_valid,
    output wire                   o_req_ready,
    input  wire [1:0]             i_req_vc,
    input  wire [5:0]             i_req_dt,
    input  wire [15:0]            i_req_wc,
    input  wire                   i_pay_valid,
    output wire                   o_pay_ready,
    input  wire [31:0]            i_pay_data,
    input  wire [2:0]             i_pay_nb,
    output wire                   o_init_done,
    output wire                   o_tx_valid,
    input  wire                   i_tx_ready,
    output wire [31:0]            o_tx_data,
    output wire [2:0]             o_tx_nb,
    output wire                   o_tx_last,
    output wire [16:0]            o_tx_total,
    output wire                   o_tx_init,
    output wire [8*CNT_WIDTH-1:0] o_cnt        // {sot_err, dt, burst, trunc, crc, ecc_double, ecc_corrected, ok}
);
    wire        w_hdr_valid;
    wire [1:0]  w_hdr_vc;
    wire [5:0]  w_hdr_dt;
    wire [15:0] w_hdr_wc;
    wire        w_hdr_short;
    wire        w_hdr_ecc_corrected;
    wire        w_hdr_sot_err;
    wire        w_pay_valid;
    wire [31:0] w_pay_data;
    wire [2:0]  w_pay_nb;
    wire        w_end_valid;
    wire [1:0]  w_end_status;
    wire        w_evt_ecc;
    wire        w_evt_burst;
    wire        w_evt_burst_late;
    wire        w_evt_short_burst;
    wire        w_evt_dt;
    wire [1:0]  w_evt_dt_vc;

    llp_top #(
        .INIT_CYCLES (INIT_CYCLES),
        .CNT_WIDTH   (CNT_WIDTH)
    ) u_top (
        .clk                    (clk),
        .rst_n                  (rst_n),
        .rx_out_valid           (i_beat[35]),
        .rx_out_data            (i_beat[31:0]),
        .rx_out_nb              (i_beat[34:32]),
        .rx_out_sot             (i_beat[36]),
        .rx_out_err             (i_beat[37]),
        .rx_out_sot_err         (i_beat[38]),
        .tx_in_valid            (o_tx_valid),
        .tx_in_ready            (i_tx_ready),
        .tx_in_data             (o_tx_data),
        .tx_in_nb               (o_tx_nb),
        .tx_in_last             (o_tx_last),
        .tx_in_total            (o_tx_total),
        .tx_init                (o_tx_init),
        .o_rx_hdr_valid         (w_hdr_valid),
        .o_rx_hdr_vc            (w_hdr_vc),
        .o_rx_hdr_dt            (w_hdr_dt),
        .o_rx_hdr_wc            (w_hdr_wc),
        .o_rx_hdr_short         (w_hdr_short),
        .o_rx_hdr_ecc_corrected (w_hdr_ecc_corrected),
        .o_rx_hdr_sot_err       (w_hdr_sot_err),
        .o_rx_pay_valid         (w_pay_valid),
        .o_rx_pay_data          (w_pay_data),
        .o_rx_pay_nb            (w_pay_nb),
        .o_rx_end_valid         (w_end_valid),
        .o_rx_end_status        (w_end_status),
        .o_rx_evt_ecc           (w_evt_ecc),
        .o_rx_evt_burst         (w_evt_burst),
        .o_rx_evt_burst_late    (w_evt_burst_late),
        .o_rx_evt_short_burst   (w_evt_short_burst),
        .o_rx_evt_dt            (w_evt_dt),
        .o_rx_evt_dt_vc         (w_evt_dt_vc),
        .i_tx_req_valid         (i_req_valid),
        .o_tx_req_ready         (o_req_ready),
        .i_tx_req_vc            (i_req_vc),
        .i_tx_req_dt            (i_req_dt),
        .i_tx_req_wc            (i_req_wc),
        .i_tx_pay_valid         (i_pay_valid),
        .o_tx_pay_ready         (o_pay_ready),
        .i_tx_pay_data          (i_pay_data),
        .i_tx_pay_nb            (i_pay_nb),
        .o_tx_init_done         (o_init_done),
        .i_cnt_gel              (1'b0),                 // compteurs libres (patch N36-2 et N36-7)
        .o_cnt_ok               (o_cnt[0*CNT_WIDTH +: CNT_WIDTH]),
        .o_cnt_ecc_corrected    (o_cnt[1*CNT_WIDTH +: CNT_WIDTH]),
        .o_cnt_ecc_double       (o_cnt[2*CNT_WIDTH +: CNT_WIDTH]),
        .o_cnt_crc              (o_cnt[3*CNT_WIDTH +: CNT_WIDTH]),
        .o_cnt_trunc            (o_cnt[4*CNT_WIDTH +: CNT_WIDTH]),
        .o_cnt_burst            (o_cnt[5*CNT_WIDTH +: CNT_WIDTH]),
        .o_cnt_dt               (o_cnt[6*CNT_WIDTH +: CNT_WIDTH]),
        .o_cnt_sot_err          (o_cnt[7*CNT_WIDTH +: CNT_WIDTH])
    );

    assign o_mon = {w_evt_dt_vc, w_evt_burst_late, w_evt_dt, w_evt_short_burst, w_evt_burst, w_evt_ecc, w_end_status, w_end_valid,
                    w_pay_nb, w_pay_data, w_pay_valid,
                    w_hdr_sot_err, w_hdr_ecc_corrected, w_hdr_short, w_hdr_wc, w_hdr_dt, w_hdr_vc, w_hdr_valid};
endmodule

`default_nettype wire
