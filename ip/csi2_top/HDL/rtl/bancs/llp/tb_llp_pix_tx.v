// Top de test de llp_pix_tx devant llp_tx (INIT_CYCLES réduit) : pixels de l'application vers les battements du LM.
`default_nettype none

module tb_llp_pix_tx #(
    parameter INIT_CYCLES = 37
) (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        i_req_valid,
    output wire        o_req_ready,
    input  wire [1:0]  i_req_vc,
    input  wire [5:0]  i_req_dt,
    input  wire [15:0] i_req_width,
    input  wire        i_pix_valid,
    output wire        o_pix_ready,
    input  wire [111:0] i_pix_data,
    input  wire [3:0]  i_pix_nb,
    output wire        o_evt_width,
    output wire        o_evt_nb,
    output wire        o_init_done,
    output wire        o_tx_valid,
    input  wire        i_tx_ready,
    output wire [31:0] o_tx_data,
    output wire [2:0]  o_tx_nb,
    output wire        o_tx_last,
    output wire [16:0] o_tx_total,
    output wire        o_tx_init
);
    wire        w_req_valid;
    wire        w_req_ready;
    wire [1:0]  w_req_vc;
    wire [5:0]  w_req_dt;
    wire [15:0] w_req_wc;
    wire        w_pay_valid;
    wire        w_pay_ready;
    wire [31:0] w_pay_data;
    wire [2:0]  w_pay_nb;

    llp_pix_tx u_pix (
        .clk             (clk),
        .rst_n           (rst_n),
        .i_req_valid     (i_req_valid),
        .o_req_ready     (o_req_ready),
        .i_req_vc        (i_req_vc),
        .i_req_dt        (i_req_dt),
        .i_req_width     (i_req_width),
        .i_pix_valid     (i_pix_valid),
        .o_pix_ready     (o_pix_ready),
        .i_pix_data      (i_pix_data),
        .i_pix_nb        (i_pix_nb),
        .o_evt_width     (o_evt_width),
        .o_evt_nb        (o_evt_nb),
        .o_llp_req_valid (w_req_valid),
        .i_llp_req_ready (w_req_ready),
        .o_llp_req_vc    (w_req_vc),
        .o_llp_req_dt    (w_req_dt),
        .o_llp_req_wc    (w_req_wc),
        .o_llp_pay_valid (w_pay_valid),
        .i_llp_pay_ready (w_pay_ready),
        .o_llp_pay_data  (w_pay_data),
        .o_llp_pay_nb    (w_pay_nb)
    );

    llp_tx #(
        .INIT_CYCLES (INIT_CYCLES)
    ) u_tx (
        .clk         (clk),
        .rst_n       (rst_n),
        .i_req_valid (w_req_valid),
        .o_req_ready (w_req_ready),
        .i_req_vc    (w_req_vc),
        .i_req_dt    (w_req_dt),
        .i_req_wc    (w_req_wc),
        .i_pay_valid (w_pay_valid),
        .o_pay_ready (w_pay_ready),
        .i_pay_data  (w_pay_data),
        .i_pay_nb    (w_pay_nb),
        .o_init_done (o_init_done),
        .o_tx_valid  (o_tx_valid),
        .i_tx_ready  (i_tx_ready),
        .o_tx_data   (o_tx_data),
        .o_tx_nb     (o_tx_nb),
        .o_tx_last   (o_tx_last),
        .o_tx_total  (o_tx_total),
        .o_tx_init   (o_tx_init)
    );
endmodule

`default_nettype wire
