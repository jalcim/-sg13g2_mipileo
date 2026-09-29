// Banc TX du csi2_top (29/09/2026) : une application présente des requêtes et des battements de pixels à llp_pix_tx
// (ports tx_req_*, tx_pix_*) ; on relève ce que le LM écrit dans la FIFO TX (fifo_tx_*), en-têtes de tailles compris.
// Repris de rtl/integration/tests/tb_tx.v (même sortie W, I, D, X, F).
// Stimuli ($readmemh) : REQ, une requête par ligne, {vc[1:0], dt[5:0], width[15:0]} (24 bits) ; PIX, un battement par
// ligne, {nb[3:0], data[111:0]} (116 bits), à la suite pour tous les paquets. NREQ et NPIX : nombres de lignes.
// Plusargs : +MASQUE, +REQ, +PIX, +NREQ, +NPIX, +SORTIE, +PLEIN (% de cycles fifo_tx_full), +TROU (% de retenue de
// l'application), +GRAINE.
// Sortie : I c (chute de tx_init) ; D c (tx_init_done) ; W c wdata wlanes fin ; Y c evt_width evt_nb ; F c (fin).
`timescale 1ps/1ps
module tb_tx;
    reg          clk = 1'b0, rst_n = 1'b1;
    reg  [3:0]   masque = 4'hf;
    reg          plein = 1'b0;
    wire         wr, fin, tx_init, init_done, req_ready, pix_ready, e_w, e_nb;
    wire [31:0]  wdata;
    wire [3:0]   wlanes;
    reg          req_valid = 1'b0, pix_valid = 1'b0;
    reg  [23:0]  req [0:255];
    reg  [115:0] pix [0:65535];
    integer      nreq = 0, npix = 0, ireq = 0, ipix = 0, pc_plein = 0, pc_trou = 0, graine = 1, cycle = 0;

    csi2_top dut (
        .clk(clk), .rst_n(rst_n), .enable(masque),
        .clk_w(1'b0), .mots(32'd0), .hspr(4'd0), .statut_phy(12'd0),
        .fifo_tx_wr(wr), .fifo_tx_wdata(wdata), .fifo_tx_wlanes(wlanes), .fifo_tx_fin(fin), .fifo_tx_full(plein),
        .tx_init(tx_init),
        .rx_sol(), .rx_sol_vc(), .rx_sol_dt(), .rx_sol_wc(), .rx_sol_fmt(), .rx_sol_ecc_corrected(), .rx_sol_sot_err(),
        .rx_pix_valid(), .rx_pix_nb(), .rx_pix_data(), .rx_eol(), .rx_eol_status(), .rx_short_valid(), .rx_short_vc(),
        .rx_short_dt(), .rx_short_data(), .rx_short_ecc_corrected(), .rx_short_sot_err(),
        .trame_fs(), .trame_fe(), .trame_fe_ok(), .trame_vc(), .trame_numero(), .trame_err_hdr(), .trame_err_hdr_vc(),
        .trame_err_end(), .trame_err_end_vc(), .trame_loss(), .trame_loss_mask(), .trame_late(), .trame_late_mask(),
        .trame_slots_pleins(),
        .tx_req_valid(req_valid), .tx_req_ready(req_ready), .tx_req_vc(req[ireq][23:22]), .tx_req_dt(req[ireq][21:16]),
        .tx_req_width(req[ireq][15:0]), .tx_pix_valid(pix_valid), .tx_pix_ready(pix_ready),
        .tx_pix_data(pix[ipix][111:0]), .tx_pix_nb(pix[ipix][115:112]), .tx_evt_width(e_w), .tx_evt_nb(e_nb),
        .tx_init_done(init_done),
        .dbg_verrou(), .dbg_erreur(), .dbg_evt(), .cnt_gel(1'b0),
        .llp_cnt_ok(), .llp_cnt_ecc_corrected(), .llp_cnt_ecc_double(), .llp_cnt_crc(), .llp_cnt_trunc(),
        .llp_cnt_burst(), .llp_cnt_dt(), .llp_cnt_sot_err(), .trame_cnt_ok(), .trame_cnt_err(), .trame_cnt_ligne()
    );

    reg [8*512-1:0] f_req, f_pix, f_sortie;
    integer fo;
    reg tx_init_r = 1'b1, done_r = 1'b0;
    initial begin
        if (!$value$plusargs("MASQUE=%h", masque)) masque = 4'hf;
        if (!$value$plusargs("REQ=%s", f_req)) f_req = "req.hex";
        if (!$value$plusargs("PIX=%s", f_pix)) f_pix = "pix.hex";
        if (!$value$plusargs("SORTIE=%s", f_sortie)) f_sortie = "sortie_tx.txt";
        if (!$value$plusargs("NREQ=%d", nreq)) nreq = 0;
        if (!$value$plusargs("NPIX=%d", npix)) npix = 0;
        if (!$value$plusargs("PLEIN=%d", pc_plein)) pc_plein = 0;
        if (!$value$plusargs("TROU=%d", pc_trou)) pc_trou = 0;
        if (!$value$plusargs("GRAINE=%d", graine)) graine = 1;
        $readmemh(f_req, req);
        if (npix > 0) $readmemh(f_pix, pix);
        fo = $fopen(f_sortie, "w");
        #2 rst_n = 1'b0;
        #20000 rst_n = 1'b1;
    end
    always #3996 clk = ~clk;                    // 7,992 ns

    integer tirage_plein, tirage_trou;
    always @(posedge clk) begin
        tirage_plein = $urandom % 100;
        tirage_trou = $urandom % 100;
        cycle <= cycle + 1;
        plein <= tirage_plein < pc_plein;
        if (req_valid && req_ready) begin
            ireq <= ireq + 1;
            req_valid <= (ireq + 1 < nreq);
        end else if (!req_valid && init_done && ireq < nreq)
            req_valid <= 1'b1;
        if (pix_valid && pix_ready) begin
            ipix <= ipix + 1;
            pix_valid <= (ipix + 1 < npix) && (tirage_trou >= pc_trou);
        end else if (!pix_valid)
            pix_valid <= init_done && (ipix < npix) && (tirage_trou >= pc_trou);
    end
    initial begin tirage_plein = $urandom(graine); end

    always @(posedge clk) begin
        if (tx_init_r && !tx_init && rst_n) $fwrite(fo, "I %0d\n", cycle);
        tx_init_r <= tx_init;
        if (!done_r && init_done) $fwrite(fo, "D %0d\n", cycle);
        done_r <= init_done;
        if (wr) $fwrite(fo, "W %0d %h %h %0d\n", cycle, wdata, wlanes, fin);
        if (e_w | e_nb) $fwrite(fo, "Y %0d %0d %0d\n", cycle, e_w, e_nb);
    end

    initial begin
        wait (rst_n);
        wait (ireq >= nreq && ipix >= npix);
        repeat (400) @(posedge clk);
        $fwrite(fo, "F %0d\n", cycle);
        $fclose(fo);
        $finish;
    end
    initial begin #2000000000; $display("tb_tx : délai dépassé"); $fwrite(fo, "F %0d\n", cycle); $finish; end
endmodule
