// Aucun chemin combinatoire d'une entrée de llp_top vers une sortie (revue 36, N36-9 : le contrôle comb=True de
// test_llp_top.py ne voyait que les sorties TX). Trafic aléatoire RX et TX ; à chaque cycle, entre deux fronts, toutes
// les entrées sont retirées au hasard plusieurs fois : aucune sortie (RX, TX, compteurs, init) ne doit bouger avant le
// front suivant. Autonome, sans modèle : iverilog -g2012 -s tb_llp_top_comb tb_llp_top_comb.v llp_*.v ../../lm_cdc.v
// Sortie : « COMB cycles=<n> ecarts=<n> », $fatal si un écart.
`timescale 1ns/1ps
`default_nettype none
module tb_llp_top_comb;
    reg         clk = 1'b0, rst_n = 1'b0;
    reg         v, sot, err, se, gel, tx_ready, req_v, pay_v;
    reg  [31:0] d, pay_d;
    reg  [2:0]  nb, pay_nb;
    reg  [1:0]  req_vc;
    reg  [5:0]  req_dt;
    reg  [15:0] req_wc;
    wire [260:0] s;
    reg  [260:0] s_front;
    integer      cycles, k, ecarts = 0;

    always #4 clk = ~clk;

    llp_top #(.INIT_CYCLES(20)) dut (
        .clk(clk), .rst_n(rst_n),
        .rx_out_valid(v), .rx_out_data(d), .rx_out_nb(nb), .rx_out_sot(sot), .rx_out_err(err), .rx_out_sot_err(se),
        .tx_in_valid(s[0]), .tx_in_ready(tx_ready), .tx_in_data(s[32:1]), .tx_in_nb(s[35:33]), .tx_in_last(s[36]),
        .tx_in_total(s[53:37]), .tx_init(s[54]),
        .o_rx_hdr_valid(s[55]), .o_rx_hdr_vc(s[57:56]), .o_rx_hdr_dt(s[63:58]), .o_rx_hdr_wc(s[79:64]),
        .o_rx_hdr_short(s[80]), .o_rx_hdr_ecc_corrected(s[81]), .o_rx_hdr_sot_err(s[82]),
        .o_rx_pay_valid(s[83]), .o_rx_pay_data(s[115:84]), .o_rx_pay_nb(s[118:116]),
        .o_rx_end_valid(s[119]), .o_rx_end_status(s[121:120]),
        .o_rx_evt_ecc(s[122]), .o_rx_evt_burst(s[123]), .o_rx_evt_short_burst(s[124]), .o_rx_evt_dt(s[125]),
        .o_rx_evt_sot_err(s[126]), .o_rx_evt_burst_late(s[258]), .o_rx_evt_dt_vc(s[260:259]),
        .i_tx_req_valid(req_v), .o_tx_req_ready(s[127]), .i_tx_req_vc(req_vc), .i_tx_req_dt(req_dt),
        .i_tx_req_wc(req_wc), .i_tx_pay_valid(pay_v), .o_tx_pay_ready(s[128]), .i_tx_pay_data(pay_d),
        .i_tx_pay_nb(pay_nb), .o_tx_init_done(s[129]), .i_cnt_gel(gel),
        .o_cnt_ok(s[145:130]), .o_cnt_ecc_corrected(s[161:146]), .o_cnt_ecc_double(s[177:162]),
        .o_cnt_crc(s[193:178]), .o_cnt_trunc(s[209:194]), .o_cnt_burst(s[225:210]), .o_cnt_dt(s[241:226]),
        .o_cnt_sot_err(s[257:242])
    );

    task automatic tire;
        begin
            v = $urandom % 4 != 0; sot = v && $urandom % 6 == 0; err = v && $urandom % 20 == 0;
            se = sot && $urandom % 4 == 0; nb = sot && err && $urandom % 2 ? 3'd0 : 3'd1 + $urandom % 4;
            d = $urandom; gel = $urandom % 200 == 0 ? ~gel : gel; tx_ready = $urandom % 3 != 0;
            req_v = $urandom % 8 == 0; req_vc = $urandom; req_dt = $urandom % 2 ? 6'h2A : 6'h01;
            req_wc = $urandom % 20; pay_v = $urandom % 4 != 0; pay_d = $urandom; pay_nb = 3'd1 + $urandom % 4;
        end
    endtask

    initial begin
        gel = 1'b0;
        tire;
        repeat (3) @(negedge clk);
        rst_n = 1'b1;
        for (cycles = 0; cycles < 20000; cycles = cycles + 1) begin
            @(posedge clk);
            #1 s_front = s;                             // sorties après le front
            for (k = 0; k < 3; k = k + 1) begin         // entrées retirées trois fois avant le front suivant
                tire;
                #1 if (s !== s_front) begin
                    ecarts = ecarts + 1;
                    if (ecarts <= 3) $display("ECART cycle %0d : sorties %h puis %h", cycles, s_front, s);
                end
            end
        end
        $display("COMB cycles=%0d ecarts=%0d", cycles, ecarts);
        if (ecarts) $fatal(1, "chemin combinatoire d'une entrée vers une sortie");
        $finish;
    end
endmodule
`default_nettype wire
