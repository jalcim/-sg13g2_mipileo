// Top de test de llp_tx avec INIT_CYCLES réduit : les bancs passent l'attente de tx_init en quelques cycles.
`default_nettype none

module tb_llp_tx #(
    parameter INIT_CYCLES = 37
) (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        i_req_valid,
    output wire        o_req_ready,
    input  wire [1:0]  i_req_vc,
    input  wire [5:0]  i_req_dt,
    input  wire [15:0] i_req_wc,
    input  wire        i_pay_valid,
    output wire        o_pay_ready,
    input  wire [31:0] i_pay_data,
    input  wire [2:0]  i_pay_nb,
    output wire        o_init_done,
    output wire        o_tx_valid,
    input  wire        i_tx_ready,
    output wire [31:0] o_tx_data,
    output wire [2:0]  o_tx_nb,
    output wire        o_tx_last,
    output wire [16:0] o_tx_total,
    output wire        o_tx_init
);
    llp_tx #(
        .INIT_CYCLES (INIT_CYCLES)
    ) u_tx (
        .clk         (clk),
        .rst_n       (rst_n),
        .i_req_valid (i_req_valid),
        .o_req_ready (o_req_ready),
        .i_req_vc    (i_req_vc),
        .i_req_dt    (i_req_dt),
        .i_req_wc    (i_req_wc),
        .i_pay_valid (i_pay_valid),
        .o_pay_ready (o_pay_ready),
        .i_pay_data  (i_pay_data),
        .i_pay_nb    (i_pay_nb),
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
