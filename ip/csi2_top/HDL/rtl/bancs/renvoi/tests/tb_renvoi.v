// Banc de bout en bout du renvoi RX -> TX (prompt 056) : modèle PHY RX (événements de modele_phy_dphy.py : clk_w,
// mots, HS) -> csi2_top --renvoi -> FIFO TX et PHY TX modélisés ici -> mots lus par le PHY TX, décodés en Python
// (bancs.py) par le golden mipi_csi2.
//
// Horloges indépendantes : Clk Système (+TS ps, +PHASE), W du RX (événements du stimulus) et W_TX (+TTX, période en
// ps réels, écart en ppm compris ; +PHASE_TX).
// FIFO TX et PHY TX (a_trancher_5 : modèle de outils_interfaces_tx/demarrage_tx.py repris au cycle près) :
// - FIFO de +PROF_FIFO mots (32), écrite sur Clk Système par fifo_tx_wr ; fifo_tx_full sort d'une bascule de Clk
//   Système, calculé sur le pointeur de lecture vu deux cycles en retard (pessimiste) ;
// - lue sur W_TX, pointeur d'écriture vu trois périodes en retard ; par paquet : N mots d'en-tête (tailles), départ
//   non_vide (un mot de données visible), SoT de +SOT ps, un mot par période sans pause jusqu'à fifo_tx_fin, puis
//   EoT de +EOT ps (T_HS-TRAIL + T_HS-EXIT) avant l'en-tête du paquet suivant ;
// - sous-remplissage : mot à lire absent en cours de burst ; le burst est perdu (U), le reste du paquet est lu et jeté.
// Paramètres du top : ceux du module tb_renvoi (LLP_INIT_CYCLES réduit à 200 : l'initialisation TX de llp_tx ne
// retarde pas le premier burst).
// Plusargs : +TS +PHASE +MASQUE +STIM +SORTIE +TTX +PHASE_TX +SOT +EOT +PROF_FIFO +MODE (renvoi_mode) +FIN (ps de
// vidange après le stimulus).
// Sortie : S t (départ du SoT) ; H t mot (en-tête lu) ; D t wdata wlanes fin (mot lu) ; U t (sous-remplissage) ;
//   B t wdata wlanes fin (mot jeté après U) ; K <compteurs> à la fin.
`timescale 1ps/1fs
module tb_renvoi #(
    // paramètres du top, passés par iverilog -Ptb_renvoi.<nom> (bancs.py)
    parameter RENVOI_NIVEAUX   = 7,
    parameter RENVOI_ERREUR    = 0,
    parameter RENVOI_STATUT    = 1,
    parameter RENVOI_PREREMPLI = 0,
    parameter RENVOI_PROF      = 16,
    parameter LLP_INIT_CYCLES  = 200
);
    reg         clk = 1'b0, clk_w = 1'b0, rst_n = 1'b1, wtx = 1'b0;
    reg  [31:0] mots = 32'd0;
    reg  [3:0]  hs = 4'd0, masque = 4'hf;
    reg  [1:0]  mode = 2'b01;
    wire [11:0] statut_phy = {hs[3], 2'b00, hs[2], 2'b00, hs[1], 2'b00, hs[0], 2'b00};
    wire        wr, fin;
    wire [31:0] wdata;
    wire [3:0]  wlanes;
    reg         full_r = 1'b0;
    wire [15:0] k_ok, k_corr, k_dbl, k_crc, k_trunc, k_burst, k_dt, k_se, t_cok, t_cerr, t_cligne;

    csi2_top #(.RENVOI_NIVEAUX(RENVOI_NIVEAUX), .RENVOI_ERREUR(RENVOI_ERREUR), .RENVOI_STATUT(RENVOI_STATUT), .RENVOI_PREREMPLI(RENVOI_PREREMPLI),
               .RENVOI_PROF(RENVOI_PROF), .LLP_INIT_CYCLES(LLP_INIT_CYCLES)) dut (
        .clk(clk), .rst_n(rst_n), .enable(masque), .renvoi_mode(mode),
        .clk_w(clk_w), .mots(mots), .hspr(hs), .statut_phy(statut_phy),
        .fifo_tx_wr(wr), .fifo_tx_wdata(wdata), .fifo_tx_wlanes(wlanes), .fifo_tx_fin(fin), .fifo_tx_full(full_r),
        .tx_init(),
        .rx_sol(), .rx_sol_vc(), .rx_sol_dt(), .rx_sol_wc(), .rx_sol_fmt(), .rx_sol_ecc_corrected(), .rx_sol_sot_err(),
        .rx_pix_valid(), .rx_pix_nb(), .rx_pix_data(), .rx_eol(), .rx_eol_status(), .rx_short_valid(), .rx_short_vc(),
        .rx_short_dt(), .rx_short_data(), .rx_short_ecc_corrected(), .rx_short_sot_err(),
        .trame_fs(), .trame_fe(), .trame_fe_ok(), .trame_vc(), .trame_numero(), .trame_err_hdr(), .trame_err_hdr_vc(),
        .trame_err_end(), .trame_err_end_vc(), .trame_loss(), .trame_loss_mask(), .trame_late(), .trame_late_mask(),
        .trame_slots_pleins(),
        .tx_req_valid(1'b0), .tx_req_ready(), .tx_req_vc(2'd0), .tx_req_dt(6'd0), .tx_req_width(16'd0),
        .tx_pix_valid(1'b0), .tx_pix_ready(), .tx_pix_data(112'd0), .tx_pix_nb(4'd0), .tx_evt_width(), .tx_evt_nb(),
        .tx_init_done(),
        .dbg_verrou(), .dbg_erreur(), .dbg_evt(), .cnt_gel(1'b0),
        .llp_cnt_ok(k_ok), .llp_cnt_ecc_corrected(k_corr), .llp_cnt_ecc_double(k_dbl), .llp_cnt_crc(k_crc),
        .llp_cnt_trunc(k_trunc), .llp_cnt_burst(k_burst), .llp_cnt_dt(k_dt), .llp_cnt_sot_err(k_se),
        .trame_cnt_ok(t_cok), .trame_cnt_err(t_cerr), .trame_cnt_ligne(t_cligne)
    );

    integer ts = 7992, phase_s = 0, prof = 32, n_lanes = 4, fo;
    real    ttx = 8000.0, phase_tx = 0.0, t_sot = 213000.0, t_eot = 164000.0, t_fin = 20000000.0;
    reg [8*512-1:0] f_stim, f_sortie;
    initial begin
        if (!$value$plusargs("TS=%d", ts)) ts = 7992;
        if (!$value$plusargs("PHASE=%d", phase_s)) phase_s = 0;
        if (!$value$plusargs("MASQUE=%h", masque)) masque = 4'hf;
        if (!$value$plusargs("MODE=%d", mode)) mode = 2'b01;
        if (!$value$plusargs("STIM=%s", f_stim)) f_stim = "stim.txt";
        if (!$value$plusargs("SORTIE=%s", f_sortie)) f_sortie = "sortie.txt";
        if (!$value$plusargs("TTX=%f", ttx)) ttx = 8000.0;
        if (!$value$plusargs("PHASE_TX=%f", phase_tx)) phase_tx = 0.0;
        if (!$value$plusargs("SOT=%f", t_sot)) t_sot = 213000.0;
        if (!$value$plusargs("EOT=%f", t_eot)) t_eot = 164000.0;
        if (!$value$plusargs("PROF_FIFO=%d", prof)) prof = 32;
        if (!$value$plusargs("FIN=%f", t_fin)) t_fin = 20000000.0;
        n_lanes = masque[0] + masque[1] + masque[2] + masque[3];
    end
    initial begin
        #(phase_s + 1);
        forever #(ts / 2) clk = ~clk;
    end
    initial begin
        #(phase_tx + 3.0);
        forever #(ttx / 2.0) wtx = ~wtx;
    end
    initial begin
        #1 fo = $fopen(f_sortie, "w");
        #2 rst_n = 1'b0;
        #100000 rst_n = 1'b1;
    end

    // ---------------------------------------------------------------------------------------------- FIFO TX
    reg  [36:0] ftx [0:255];
    integer wp = 0, rp = 0, rp_s1 = 0, rp_s2 = 0, wp_s1 = 0, wp_s2 = 0, wp_s3 = 0, occ_max = 0;
    always @(posedge clk) begin
        if (wr) begin
            if (wp - rp_s2 >= prof) $fwrite(fo, "O %0t\n", $realtime);    // jamais : la LDF respecte le plein
            ftx[wp % 256] <= {wdata, wlanes, fin};
        end
        wp     <= wp + wr;
        rp_s1  <= rp;
        rp_s2  <= rp_s1;
        full_r <= (wp + wr) - rp_s2 >= prof;
        if (wp + wr - rp > occ_max) occ_max = wp + wr - rp;
    end

    // ---------------------------------------------------------------------------------------------- PHY TX
    localparam ENTETE = 0, ATTENTE = 1, SOT = 2, BURST = 3, PURGE = 4, EOT = 5;
    integer etat = ENTETE, hn = 0, n_u = 0, n_bursts = 0;
    real    t_etat = 0.0;
    reg [36:0] m;
    always @(posedge wtx) begin
        wp_s1 <= wp;
        wp_s2 <= wp_s1;
        wp_s3 <= wp_s2;
        if (etat == ENTETE && wp_s3 > rp) begin
            m = ftx[rp % 256];
            rp = rp + 1;
            $fwrite(fo, "H %0t %h\n", $realtime, m[36:5]);
            hn = hn + 1;
            if (hn == n_lanes) begin
                hn = 0;
                etat = ATTENTE;
            end
        end else if (etat == ATTENTE && wp_s3 > rp) begin
            etat = SOT;
            t_etat = $realtime + t_sot;
            $fwrite(fo, "S %0t\n", $realtime);
        end else if (etat == EOT && $realtime >= t_etat)
            etat = ENTETE;
        if (etat == SOT && $realtime >= t_etat)
            etat = BURST;
        if (etat == BURST || etat == PURGE) begin
            if (wp_s3 > rp) begin
                m = ftx[rp % 256];
                rp = rp + 1;
                $fwrite(fo, "%s %0t %h %h %0d\n", etat == BURST ? "D" : "B", $realtime, m[36:5], m[4:1], m[0]);
                if (m[0]) begin
                    etat = EOT;
                    t_etat = $realtime + t_eot;
                    n_bursts = n_bursts + 1;
                end
            end else if (etat == BURST) begin
                $fwrite(fo, "U %0t\n", $realtime);
                n_u = n_u + 1;
                etat = PURGE;
            end
        end
    end

    // ---------------------------------------------------------------------------------------------- stimulus RX
    integer fd, r, typ;
    reg [63:0] t;
    reg [31:0] v;
    initial begin
        #1 fd = $fopen(f_stim, "r");
        r = 3;
        while (r == 3) begin
            r = $fscanf(fd, "%d %d %h\n", t, typ, v);
            if (r == 3) begin
                if (t > $realtime) #(t - $realtime);
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
        #(t_fin);
        $fwrite(fo, "K %0d %0d %0d %0d %0d %0d %0d %0d %0d %0d %0d  %0d %0d %0d %0d %0d  %0d %0d %0d %0d %0d %0d\n",
                k_ok, k_corr, k_dbl, k_crc, k_trunc, k_burst, k_dt, k_se, t_cok, t_cerr, t_cligne,
                dut.rv_cnt_perdus, dut.rv_cnt_marques, dut.rv_cnt_supprimes, dut.rv_cnt_bourres, dut.rv_tampon_max,
                occ_max, n_u, n_bursts, wp - rp, etat, dut.lm_erreur_fifo);
        $fclose(fo);
        $finish;
    end
endmodule
