// Top de test de llp_pix_rx derrière llp_rx : flux du LM en entrée, sorties des deux modules en deux bus plats.
// Positions reprises par test_llp_pix_rx.py (SORTIES_RX de test_llp_rx.py, CHAMPS_PIX).
`default_nettype none

module tb_llp_pix_rx (
    input  wire         clk,
    input  wire         rst_n,
    input  wire [38:0]  i_beat,         // {sot_err, err, sot, valid, nb[2:0], data[31:0]}
    output wire [73:0]  o_rx,           // sorties de llp_rx, même rangement que tb_llp_rx
    output wire [144:0] o_pix           // sorties de llp_pix_rx, o_sol en [0]
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
    wire        w_sol;
    wire [1:0]  w_sol_vc;
    wire [5:0]  w_sol_dt;
    wire [15:0] w_sol_wc;
    wire [2:0]  w_sol_fmt;
    wire        w_pix_valid;
    wire [2:0]  w_pix_nb;
    wire [83:0] w_pix_data;
    wire        w_eol;
    wire [2:0]  w_eol_status;
    wire        w_short_valid;
    wire [1:0]  w_short_vc;
    wire [5:0]  w_short_dt;
    wire [15:0] w_short_data;

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

    llp_pix_rx u_pix (
        .clk           (clk),
        .rst_n         (rst_n),
        .i_hdr_valid   (w_hdr_valid),
        .i_hdr_vc      (w_hdr_vc),
        .i_hdr_dt      (w_hdr_dt),
        .i_hdr_wc      (w_hdr_wc),
        .i_hdr_short   (w_hdr_short),
        .i_hdr_ecc_corrected (w_hdr_ecc_corrected),
        .i_hdr_sot_err (w_hdr_sot_err),
        .i_pay_valid   (w_pay_valid),
        .i_pay_data    (w_pay_data),
        .i_pay_nb      (w_pay_nb),
        .i_end_valid   (w_end_valid),
        .i_end_status  (w_end_status),
        .o_sol         (w_sol),
        .o_sol_vc      (w_sol_vc),
        .o_sol_dt      (w_sol_dt),
        .o_sol_wc      (w_sol_wc),
        .o_sol_fmt     (w_sol_fmt),
        .o_sol_ecc_corrected (),
        .o_sol_sot_err (),
        .o_pix_valid   (w_pix_valid),
        .o_pix_nb      (w_pix_nb),
        .o_pix_data    (w_pix_data),
        .o_eol         (w_eol),
        .o_eol_status  (w_eol_status),
        .o_short_valid (w_short_valid),
        .o_short_vc    (w_short_vc),
        .o_short_dt    (w_short_dt),
        .o_short_data  (w_short_data),
        .o_short_ecc_corrected (),
        .o_short_sot_err ()
    );

    assign o_rx  = {w_evt_dt_vc, w_evt_burst_late, w_evt_dt, w_evt_short_burst, w_evt_burst, w_evt_ecc, w_end_status, w_end_valid,
                    w_pay_nb, w_pay_data, w_pay_valid,
                    w_hdr_sot_err, w_hdr_ecc_corrected, w_hdr_short, w_hdr_wc, w_hdr_dt, w_hdr_vc, w_hdr_valid};
    assign o_pix = {w_short_data, w_short_dt, w_short_vc, w_short_valid, w_eol_status, w_eol,
                    w_pix_data, w_pix_nb, w_pix_valid, w_sol_fmt, w_sol_wc, w_sol_dt, w_sol_vc, w_sol};
endmodule

`default_nettype wire
