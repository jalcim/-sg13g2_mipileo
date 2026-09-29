// Boite noire de dphy_rx, generee depuis dphy_rx.lef par scripts/gen_msphy5973.py.
(* blackbox *)
module dphy_rx (
    input wire PG,
    inout wire VGND,
    inout wire VPWR,
    input wire clk_lp_n,
    input wire clk_lp_p,
    output wire clk_miss,
    output wire clk_rx_en,
    output wire clk_stop,
    output wire clk_term_en,
    output wire [3:0] hs_rx_en,
    output wire [3:0] hspr,
    output wire [3:0] hsreq,
    input wire [3:0] lp_n,
    input wire [3:0] lp_p,
    input wire rx_clk,
    output wire [3:0] stop,
    output wire [3:0] term_en
);
endmodule
