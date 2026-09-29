// Boite noire de dphy_tx, generee depuis dphy_tx.lef par scripts/gen_msphy5973.py.
(* blackbox *)
module dphy_tx (
    input wire PG,
    inout wire VGND,
    inout wire VPWR,
    input wire clk,
    output wire clk_hs_oe,
    output wire clk_lp_n,
    output wire clk_lp_p,
    output wire clk_ready,
    input wire clk_request,
    output wire clk_run,
    output wire [3:0] hs_oe,
    output wire [3:0] hs_sync,
    output wire [3:0] hs_trail,
    output wire [3:0] lp_n,
    output wire [3:0] lp_p,
    input wire rst,
    output wire [3:0] tx_ready_hs,
    input wire [3:0] tx_request_hs
);
endmodule
