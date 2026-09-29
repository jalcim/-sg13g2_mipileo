// Banc RX du csi2_top (29/09/2026) : les mots d'un flux D-PHY (modèle PHY indépendant de lm-corrections-revue,
// tests/independants/modele_phy_dphy.py) entrent dans le LM ; on relève les sorties d'application du top (pixels,
// trame, débogage) et, pour l'analyse, les sorties de llp_top dans le top (hiérarchie : dut.hdr_valid…).
// Stimulus : fichier d'événements du modèle, comme rtl/integration/tests/tb_rx.v ("t type valeur", temps en ps ;
// 0 : front montant de W ; 3 : front descendant ; 4 : mots ; 2 : HS pris comme HSPR ; 9 : fin).
// Plusargs : +TS (période de Clk Système, ps), +PHASE (ps), +MASQUE (hex, enable), +STIM, +SORTIE.
// Sortie, au front de Clk Système (t en ps) :
//   S t vc dt wc fmt corrige sot_err      rx_sol
//   X t nb data(84 bits, hex)             rx_pix_valid
//   L t etat                              rx_eol
//   C t vc dt donnee corrige sot_err      rx_short_valid
//   F t vc numero                         trame_fs
//   G t vc numero ok                      trame_fe
//   T t err_hdr err_hdr_vc err_end err_end_vc loss loss_mask late late_mask slots   une erreur de trame au moins
//   R t dt_vc                             événement « type réservé » de llp_rx (o_rx_evt_dt, dans le top)
//   H t vc dt wc court corrige sot_err    en-tête publié par llp_top (dans le top)
//   E t etat                              fin de paquet long de llp_top (dans le top)
//   D t erreur evt                        dbg_erreur ou dbg_evt
//   K <8 compteurs de llp_top> <3 compteurs de llp_trame> verrou erreur_fifo      à la fin
`timescale 1ps/1ps
module tb_rx;
    reg         clk = 1'b0, clk_w = 1'b0, rst_n = 1'b1;
    reg  [31:0] mots = 32'd0;
    reg  [3:0]  hs = 4'd0, masque = 4'hf;
    wire [11:0] statut_phy = {hs[3], 2'b00, hs[2], 2'b00, hs[1], 2'b00, hs[0], 2'b00};

    wire        sol, sol_corr, sol_se, pix_v, eol, sh_v, sh_corr, sh_se;
    wire [1:0]  sol_vc, sh_vc, t_vc, ehv, eev;
    wire [5:0]  sol_dt, sh_dt;
    wire [15:0] sol_wc, sh_data, t_num;
    wire [2:0]  sol_fmt, pix_nb, eol_st, err_end, loss;
    wire [83:0] pix;
    wire        fs, fe, fe_ok, late, slots, d_err, d_evt;
    wire [6:0]  err_hdr;
    wire [3:0]  loss_m, late_m, verrou;
    wire [15:0] k_ok, k_corr, k_dbl, k_crc, k_trunc, k_burst, k_dt, k_se, t_cok, t_cerr, t_cligne;

    csi2_top dut (   // paramètres par défaut du top (bloc v2, NB_VC = 4, DEBUG = 1)
        .clk(clk), .rst_n(rst_n), .enable(masque),
        .clk_w(clk_w), .mots(mots), .hspr(hs), .statut_phy(statut_phy),
        .fifo_tx_wr(), .fifo_tx_wdata(), .fifo_tx_wlanes(), .fifo_tx_fin(), .fifo_tx_full(1'b0), .tx_init(),
        .rx_sol(sol), .rx_sol_vc(sol_vc), .rx_sol_dt(sol_dt), .rx_sol_wc(sol_wc), .rx_sol_fmt(sol_fmt),
        .rx_sol_ecc_corrected(sol_corr), .rx_sol_sot_err(sol_se), .rx_pix_valid(pix_v), .rx_pix_nb(pix_nb),
        .rx_pix_data(pix), .rx_eol(eol), .rx_eol_status(eol_st), .rx_short_valid(sh_v), .rx_short_vc(sh_vc),
        .rx_short_dt(sh_dt), .rx_short_data(sh_data), .rx_short_ecc_corrected(sh_corr), .rx_short_sot_err(sh_se),
        .trame_fs(fs), .trame_fe(fe), .trame_fe_ok(fe_ok), .trame_vc(t_vc), .trame_numero(t_num),
        .trame_err_hdr(err_hdr), .trame_err_hdr_vc(ehv), .trame_err_end(err_end), .trame_err_end_vc(eev),
        .trame_loss(loss), .trame_loss_mask(loss_m), .trame_late(late), .trame_late_mask(late_m),
        .trame_slots_pleins(slots),
        .tx_req_valid(1'b0), .tx_req_ready(), .tx_req_vc(2'd0), .tx_req_dt(6'd0), .tx_req_width(16'd0),
        .tx_pix_valid(1'b0), .tx_pix_ready(), .tx_pix_data(112'd0), .tx_pix_nb(4'd0), .tx_evt_width(), .tx_evt_nb(),
        .tx_init_done(),
        .dbg_verrou(verrou), .dbg_erreur(d_err), .dbg_evt(d_evt), .cnt_gel(1'b0),
        .llp_cnt_ok(k_ok), .llp_cnt_ecc_corrected(k_corr), .llp_cnt_ecc_double(k_dbl), .llp_cnt_crc(k_crc),
        .llp_cnt_trunc(k_trunc), .llp_cnt_burst(k_burst), .llp_cnt_dt(k_dt), .llp_cnt_sot_err(k_se),
        .trame_cnt_ok(t_cok), .trame_cnt_err(t_cerr), .trame_cnt_ligne(t_cligne)
    );

    integer ts = 7992, phase_s = 0, t_reset = 100000;
    reg [8*512-1:0] f_stim, f_sortie;
    initial begin
        if (!$value$plusargs("TS=%d", ts)) ts = 7992;
        if (!$value$plusargs("PHASE=%d", phase_s)) phase_s = 0;
        if (!$value$plusargs("MASQUE=%h", masque)) masque = 4'hf;
        if (!$value$plusargs("STIM=%s", f_stim)) f_stim = "stim.txt";
        if (!$value$plusargs("SORTIE=%s", f_sortie)) f_sortie = "sortie.txt";
        #(phase_s + 1);
        forever #(ts / 2) clk = ~clk;
    end

    integer fo;
    initial begin #1 fo = $fopen(f_sortie, "w"); end
    always @(posedge clk) begin
        if (sol) $fwrite(fo, "S %0d %0d %h %0d %0d %0d %0d\n", $time, sol_vc, sol_dt, sol_wc, sol_fmt, sol_corr, sol_se);
        if (pix_v) $fwrite(fo, "X %0d %0d %h\n", $time, pix_nb, pix);
        if (eol) $fwrite(fo, "L %0d %0d\n", $time, eol_st);
        if (sh_v) $fwrite(fo, "C %0d %0d %h %h %0d %0d\n", $time, sh_vc, sh_dt, sh_data, sh_corr, sh_se);
        if (fs) $fwrite(fo, "F %0d %0d %0d\n", $time, t_vc, t_num);
        if (fe) $fwrite(fo, "G %0d %0d %0d %0d\n", $time, t_vc, t_num, fe_ok);
        if (|err_hdr | |err_end | |loss | late | slots)
            $fwrite(fo, "T %0d %h %0d %h %0d %h %h %0d %h %0d\n", $time, err_hdr, ehv, err_end, eev, loss, loss_m,
                    late, late_m, slots);
        if (dut.evt_dt) $fwrite(fo, "R %0d %0d\n", $time, dut.evt_dt_vc);
        if (dut.hdr_valid) $fwrite(fo, "H %0d %0d %h %0d %0d %0d %0d\n", $time, dut.hdr_vc, dut.hdr_dt, dut.hdr_wc,
                                   dut.hdr_short, dut.hdr_ecc_corrected, dut.hdr_sot_err);
        if (dut.end_valid) $fwrite(fo, "E %0d %0d\n", $time, dut.end_status);
        if (d_err | d_evt) $fwrite(fo, "D %0d %0d %0d\n", $time, d_err, d_evt);
    end

    initial begin
        #2 rst_n = 1'b0;
        #(t_reset) rst_n = 1'b1;
    end

    integer fd, r, typ;
    reg [63:0] t;
    reg [31:0] v;
    initial begin
        #1 fd = $fopen(f_stim, "r");
        r = 3;
        while (r == 3) begin
            r = $fscanf(fd, "%d %d %h\n", t, typ, v);
            if (r == 3) begin
                if (t > $time) #(t - $time);
                case (typ)
                    0: clk_w = 1'b1;
                    3: clk_w = 1'b0;
                    4: mots = v;
                    2: hs = v[3:0];
                    9: r = 0;
                    default: ;
                endcase
            end
        end
        #(2000000);
        $fwrite(fo, "K %0d %0d %0d %0d %0d %0d %0d %0d %0d %0d %0d %h %0d\n", k_ok, k_corr, k_dbl, k_crc, k_trunc,
                k_burst, k_dt, k_se, t_cok, t_cerr, t_cligne, verrou, dut.lm_erreur_fifo);
        $fclose(fo);
        $finish;
    end
endmodule
