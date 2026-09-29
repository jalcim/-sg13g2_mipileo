// Top de test de llp_rx : entrées et sorties rangées en deux bus plats, une écriture et une lecture par cycle
// depuis cocotb. Positions reprises par test_llp_rx.py (ENTREE_* et SORTIE_*).
`default_nettype none

module tb_llp_rx (
    input  wire        clk,
    input  wire        rst_n,
    input  wire [38:0] i_beat,          // {sot_err, err, sot, valid, nb[2:0], data[31:0]}
    output wire [73:0] o_mon            // sorties de llp_rx, o_hdr_valid en [0]
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

    llp_rx u_rx (
        .clk                 (clk),
        .rst_n               (rst_n),
        .i_rx_valid          (i_beat[35]),
        .i_rx_data           (i_beat[31:0]),
        .i_rx_nb             (i_beat[34:32]),
        .i_rx_sot            (i_beat[36]),
        .i_rx_err            (i_beat[37]),
        .i_rx_sot_err        (i_beat[38]),
        .o_hdr_valid         (w_hdr_valid),
        .o_hdr_vc            (w_hdr_vc),
        .o_hdr_dt            (w_hdr_dt),
        .o_hdr_wc            (w_hdr_wc),
        .o_hdr_short         (w_hdr_short),
        .o_hdr_ecc_corrected (w_hdr_ecc_corrected),
        .o_hdr_sot_err       (w_hdr_sot_err),
        .o_pay_valid         (w_pay_valid),
        .o_pay_data          (w_pay_data),
        .o_pay_nb            (w_pay_nb),
        .o_end_valid         (w_end_valid),
        .o_end_status        (w_end_status),
        .o_evt_ecc           (w_evt_ecc),
        .o_evt_burst         (w_evt_burst),
        .o_evt_burst_late    (w_evt_burst_late),
        .o_evt_short_burst   (w_evt_short_burst),
        .o_evt_dt            (w_evt_dt),
        .o_evt_dt_vc         (w_evt_dt_vc)
    );

    assign o_mon = {w_evt_dt_vc, w_evt_burst_late, w_evt_dt, w_evt_short_burst, w_evt_burst, w_evt_ecc, w_end_status, w_end_valid,
                    w_pay_nb, w_pay_data, w_pay_valid,
                    w_hdr_sot_err, w_hdr_ecc_corrected, w_hdr_short, w_hdr_wc, w_hdr_dt, w_hdr_vc, w_hdr_valid};
endmodule

`default_nettype wire
