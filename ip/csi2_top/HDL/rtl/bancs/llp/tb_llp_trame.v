// Top de test de llp_trame derrière llp_rx : flux du LM en entrée (bus i_beat de tb_llp_rx), sorties de llp_trame
// en un bus plat. Positions reprises par test_llp_trame.py (CHAMPS_TRAME).
`default_nettype none

module tb_llp_trame #(
    parameter NB_VC         = 4,
    parameter FRAME_WRAP    = 0,
    parameter LINE_DT_SLOTS = 2
) (
    input  wire         clk,
    input  wire         rst_n,
    input  wire [38:0]  i_beat,         // {sot_err, err, sot, valid, nb[2:0], data[31:0]}
    input  wire         i_cnt_clear,
    output wire [95:0]  o_trame          // sorties de llp_trame, o_fs en [0]
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

    wire        w_fs;
    wire        w_fe;
    wire        w_fe_ok;
    wire [1:0]  w_frame_vc;
    wire [15:0] w_frame_number;
    wire [6:0]  w_err_hdr;
    wire [1:0]  w_err_hdr_vc;
    wire [2:0]  w_err_end;
    wire [1:0]  w_err_end_vc;
    wire [2:0]  w_loss;
    wire [NB_VC-1:0] w_loss_mask;
    wire        w_late;
    wire [NB_VC-1:0] w_late_mask;
    wire        w_slots_full;
    wire [15:0] w_cnt_ok;
    wire [15:0] w_cnt_frame;
    wire [15:0] w_cnt_line;

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

    llp_trame #(
        .NB_VC         (NB_VC),
        .FRAME_WRAP    (FRAME_WRAP),
        .LINE_DT_SLOTS (LINE_DT_SLOTS)
    ) u_trame (
        .clk               (clk),
        .rst_n             (rst_n),
        .i_hdr_valid       (w_hdr_valid),
        .i_hdr_vc          (w_hdr_vc),
        .i_hdr_dt          (w_hdr_dt),
        .i_hdr_wc          (w_hdr_wc),
        .i_hdr_short       (w_hdr_short),
        .i_end_valid       (w_end_valid),
        .i_end_status      (w_end_status),
        .i_evt_ecc         (w_evt_ecc),
        .i_evt_burst       (w_evt_burst),
        .i_evt_burst_late  (w_evt_burst_late),
        .i_evt_short_burst (w_evt_short_burst),
        .i_evt_dt          (w_evt_dt),
        .i_evt_dt_vc       (w_evt_dt_vc),
        .i_cnt_clear       (i_cnt_clear),
        .o_fs              (w_fs),
        .o_fe              (w_fe),
        .o_fe_ok           (w_fe_ok),
        .o_frame_vc        (w_frame_vc),
        .o_frame_number    (w_frame_number),
        .o_err_hdr         (w_err_hdr),
        .o_err_hdr_vc      (w_err_hdr_vc),
        .o_err_end         (w_err_end),
        .o_err_end_vc      (w_err_end_vc),
        .o_loss            (w_loss),
        .o_loss_mask       (w_loss_mask),
        .o_late            (w_late),
        .o_late_mask       (w_late_mask),
        .o_line_slots_full (w_slots_full),
        .o_cnt_frame_ok    (w_cnt_ok),
        .o_cnt_frame_err   (w_cnt_frame),
        .o_cnt_line_err    (w_cnt_line)
    );

    wire [3:0] w_loss_mask4 = w_loss_mask;      // complété de zéros au-delà de NB_VC
    wire [3:0] w_late_mask4 = w_late_mask;

    assign o_trame = {w_cnt_line, w_cnt_frame, w_cnt_ok, w_slots_full, w_late_mask4, w_late, w_loss_mask4, w_loss,
                      w_err_end_vc, w_err_end, w_err_hdr_vc, w_err_hdr, w_frame_number, w_frame_vc, w_fe_ok, w_fe,
                      w_fs};
endmodule

`default_nettype wire
