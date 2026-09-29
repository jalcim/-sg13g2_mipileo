// Renvoi RX -> TX dans le csi2_top (prompt 056 ; fiche analyse/reponses/renvoi_rx_tx.md) : ce que reçoit le MIPI RX
// repart par le MIPI TX, à débit égal (mêmes lanes, même débit par lane), horloges RX (clk_w) et Clock TX
// indépendantes. Tout est sur Clk Système ; aucune horloge ajoutée.
//
// Mode (renvoi_mode, broches statiques, changées sous reset) :
//   00 application : ce bloc est à l'écart, le csi2_top est inchangé (preuve d'équivalence, tests/renvoi/) ;
//   01 N1 mots     : rx_out_* du LM -> tx_in_* du LM, LLP contourné (renvoi_n1) ;
//   10 N2 paquets  : o_rx_hdr/pay/end de llp_top -> i_tx_req/pay de llp_top (renvoi_n2), ECC et CRC refaits ;
//   11 N3 pixels   : rx_sol/pix/eol/short de llp_pix_rx -> tx_req/pix de llp_pix_tx (renvoi_n3).
// Les multiplexeurs sont dans csi2_top.v (patch renvoi/csi2_top.patch) ; en mode 00 ils prennent les chemins d'origine.
// En N2 et N3, la sortie TX de llp_top passe par renvoi_marque (CRC faux sur les paquets reçus en erreur) ; en N1 à N3,
// le flux passe par renvoi_tampon (tampon élastique et préremplissage) avant le LM. STATUT : renvoi_statut.
//
// Compteurs du renvoi (CNT_W bits, collants, saturants, remis à 0 par le reset) : paquets perdus (le RX ne s'arrête
// pas : paquet qui trouve le renvoi occupé, burst trop court, ligne de taille hors groupe en N3, verdict perdu),
// marqués (CRC rendu faux), supprimés (E_SUP), bourrés (charge complétée par des zéros).
`default_nettype none

module renvoi #(
    parameter NIVEAUX   = 7,            // niveaux présents : bit 0 N1, bit 1 N2, bit 2 N3 ; mode d'un niveau absent :
                                        // rien n'est renvoyé
    parameter ERREUR    = 0,            // N2 : 0 E_CRC, 1 E_SUP
    parameter STATUT    = 1,            // paquet générique de statut en fin de trame
    parameter STATUT_VC = 3,            // VC réservé du statut
    parameter PREREMPLI = 0,            // octets retenus avant le départ d'un paquet
    parameter PROF      = 16,           // battements du tampon
    parameter CNT_W     = 16
) (
    input  wire         clk,
    input  wire         rst_n,
    input  wire [1:0]   i_mode,
    // LM, RX
    input  wire         i_rx_valid,
    input  wire [31:0]  i_rx_data,
    input  wire [2:0]   i_rx_nb,
    input  wire         i_rx_sot,
    input  wire         i_rx_err,
    // llp_top, RX
    input  wire         i_hdr_valid,
    input  wire [1:0]   i_hdr_vc,
    input  wire [5:0]   i_hdr_dt,
    input  wire [15:0]  i_hdr_wc,
    input  wire         i_hdr_short,
    input  wire         i_hdr_ecc_corrected,
    input  wire         i_hdr_sot_err,
    input  wire         i_pay_valid,
    input  wire [31:0]  i_pay_data,
    input  wire [2:0]   i_pay_nb,
    input  wire         i_end_valid,
    input  wire [1:0]   i_end_status,
    // llp_pix_rx
    input  wire         i_sol,
    input  wire [1:0]   i_sol_vc,
    input  wire [5:0]   i_sol_dt,
    input  wire [15:0]  i_sol_wc,
    input  wire [2:0]   i_sol_fmt,
    input  wire         i_pix_valid,
    input  wire [2:0]   i_pix_nb,
    input  wire [83:0]  i_pix_data,
    input  wire         i_eol,
    input  wire [2:0]   i_eol_status,
    input  wire         i_short_valid,
    input  wire [1:0]   i_short_vc,
    input  wire [5:0]   i_short_dt,
    input  wire [15:0]  i_short_data,
    // llp_trame et compteurs
    input  wire         i_fe,
    input  wire         i_fe_ok,
    input  wire [1:0]   i_fe_vc,
    input  wire         i_err_hdr,
    input  wire         i_err_end,
    input  wire         i_loss,
    input  wire         i_late,
    input  wire [6*CNT_W-1:0] i_cnt_llp,    // ecc_double, crc, trunc, burst, dt, sot_err (k = 0 à 5)
    input  wire [CNT_W-1:0]   i_cnt_trame,  // trames en erreur
    // N2 -> llp_top (TX)
    output wire         o_n2_req_valid,
    input  wire         i_n2_req_ready,
    output wire [1:0]   o_n2_req_vc,
    output wire [5:0]   o_n2_req_dt,
    output wire [15:0]  o_n2_req_wc,
    output wire         o_n2_pay_valid,
    input  wire         i_n2_pay_ready,
    output wire [31:0]  o_n2_pay_data,
    output wire [2:0]   o_n2_pay_nb,
    // N3 -> llp_pix_tx
    output wire         o_n3_req_valid,
    input  wire         i_n3_req_ready,
    output wire [1:0]   o_n3_req_vc,
    output wire [5:0]   o_n3_req_dt,
    output wire [15:0]  o_n3_req_width,
    output wire         o_n3_pix_valid,
    input  wire         i_n3_pix_ready,
    output wire [111:0] o_n3_pix_data,
    output wire [3:0]   o_n3_pix_nb,
    // sortie TX de llp_top (N2, N3)
    input  wire         i_llp_valid,
    output wire         o_llp_ready,
    input  wire [31:0]  i_llp_data,
    input  wire [2:0]   i_llp_nb,
    input  wire         i_llp_last,
    input  wire [16:0]  i_llp_total,
    // vers l'entrée TX du LM
    output wire         o_tx_valid,
    input  wire         i_tx_ready,
    output wire [31:0]  o_tx_data,
    output wire [2:0]   o_tx_nb,
    output wire         o_tx_last,
    output wire [16:0]  o_tx_total,
    // compteurs du renvoi
    output wire [CNT_W-1:0] o_cnt_perdus,
    output wire [CNT_W-1:0] o_cnt_marques,
    output wire [CNT_W-1:0] o_cnt_supprimes,
    output wire [CNT_W-1:0] o_cnt_bourres,
    output wire [$clog2(PROF):0] o_tampon_max
);
    wire n1 = i_mode == 2'b01 && NIVEAUX[0];
    wire n2 = i_mode == 2'b10 && NIVEAUX[1];
    wire n3 = i_mode == 2'b11 && NIVEAUX[2];

    // statut
    wire        st_valid, st_ready_n1, st_ready_n2, st_ready_n3;
    wire [5:0]  st_dt;
    wire [15:0] st_data;
    wire        evt_renvoi;

    // N1
    wire        n1_valid, n1_last, n1_perdu, n1_bourre;
    wire [31:0] n1_data;
    wire [2:0]  n1_nb;
    wire [16:0] n1_total;
    wire        t_ready;
    renvoi_n1 u_n1 (
        .clk(clk), .rst_n(rst_n), .i_actif(n1),
        .i_valid(i_rx_valid), .i_data(i_rx_data), .i_nb(i_rx_nb), .i_sot(i_rx_sot), .i_err(i_rx_err),
        .i_st_valid(st_valid), .o_st_ready(st_ready_n1), .i_st_vc(STATUT_VC[1:0]), .i_st_dt(st_dt),
        .i_st_data(st_data),
        .o_valid(n1_valid), .i_ready(t_ready & n1), .o_data(n1_data), .o_nb(n1_nb), .o_last(n1_last),
        .o_total(n1_total), .o_evt_perdu(n1_perdu), .o_evt_bourre(n1_bourre)
    );

    // N2
    wire n2_verdict, n2_mauvais, n2_perdu, n2_supprime, n2_bourre;
    generate
        if (NIVEAUX[1]) begin : g_n2
        renvoi_n2 #(.ERREUR(ERREUR)) u_n2 (
            .clk(clk), .rst_n(rst_n), .i_actif(n2),
            .i_hdr_valid(i_hdr_valid), .i_hdr_vc(i_hdr_vc), .i_hdr_dt(i_hdr_dt), .i_hdr_wc(i_hdr_wc),
            .i_hdr_short(i_hdr_short), .i_hdr_ecc_corrected(i_hdr_ecc_corrected), .i_hdr_sot_err(i_hdr_sot_err),
            .i_pay_valid(i_pay_valid), .i_pay_data(i_pay_data), .i_pay_nb(i_pay_nb),
            .i_end_valid(i_end_valid), .i_end_status(i_end_status),
            .i_st_valid(st_valid), .o_st_ready(st_ready_n2), .i_st_vc(STATUT_VC[1:0]), .i_st_dt(st_dt),
            .i_st_data(st_data),
            .o_req_valid(o_n2_req_valid), .i_req_ready(i_n2_req_ready), .o_req_vc(o_n2_req_vc), .o_req_dt(o_n2_req_dt),
            .o_req_wc(o_n2_req_wc), .o_pay_valid(o_n2_pay_valid), .i_pay_ready(i_n2_pay_ready),
            .o_pay_data(o_n2_pay_data), .o_pay_nb(o_n2_pay_nb),
            .o_verdict(n2_verdict), .o_mauvais(n2_mauvais), .o_evt_perdu(n2_perdu), .o_evt_supprime(n2_supprime),
            .o_evt_bourre(n2_bourre)
        );
        end else begin : g_sans_n2
            assign {o_n2_req_valid, o_n2_req_vc, o_n2_req_dt, o_n2_req_wc, o_n2_pay_valid, o_n2_pay_data, o_n2_pay_nb}
                = 61'd0;
            assign {st_ready_n2, n2_verdict, n2_mauvais, n2_perdu, n2_supprime, n2_bourre} = 6'd0;
            wire w_non_lus = &{1'b0, i_hdr_valid, i_hdr_vc, i_hdr_dt, i_hdr_wc, i_hdr_short, i_hdr_ecc_corrected,
                               i_hdr_sot_err, i_pay_valid, i_pay_data, i_pay_nb, i_end_valid, i_end_status,
                               i_n2_req_ready, i_n2_pay_ready};
        end
    endgenerate

    // N3
    wire n3_verdict, n3_mauvais, n3_perdu, n3_bourre;
    generate
        if (NIVEAUX[2]) begin : g_n3
        renvoi_n3 u_n3 (
            .clk(clk), .rst_n(rst_n), .i_actif(n3),
            .i_sol(i_sol), .i_sol_vc(i_sol_vc), .i_sol_dt(i_sol_dt), .i_sol_wc(i_sol_wc), .i_sol_fmt(i_sol_fmt),
            .i_pix_valid(i_pix_valid), .i_pix_nb(i_pix_nb), .i_pix_data(i_pix_data),
            .i_eol(i_eol), .i_eol_status(i_eol_status),
            .i_short_valid(i_short_valid), .i_short_vc(i_short_vc), .i_short_dt(i_short_dt), .i_short_data(i_short_data),
            .i_st_valid(st_valid), .o_st_ready(st_ready_n3), .i_st_vc(STATUT_VC[1:0]), .i_st_dt(st_dt),
            .i_st_data(st_data),
            .o_req_valid(o_n3_req_valid), .i_req_ready(i_n3_req_ready), .o_req_vc(o_n3_req_vc), .o_req_dt(o_n3_req_dt),
            .o_req_width(o_n3_req_width), .o_pix_valid(o_n3_pix_valid), .i_pix_ready(i_n3_pix_ready),
            .o_pix_data(o_n3_pix_data), .o_pix_nb(o_n3_pix_nb),
            .o_verdict(n3_verdict), .o_mauvais(n3_mauvais), .o_evt_perdu(n3_perdu), .o_evt_bourre(n3_bourre)
        );
        end else begin : g_sans_n3
            assign {o_n3_req_valid, o_n3_req_vc, o_n3_req_dt, o_n3_req_width, o_n3_pix_valid, o_n3_pix_data,
                    o_n3_pix_nb} = 142'd0;
            assign {st_ready_n3, n3_verdict, n3_mauvais, n3_perdu, n3_bourre} = 5'd0;
            wire w_non_lus = &{1'b0, i_sol, i_sol_vc, i_sol_dt, i_sol_wc, i_sol_fmt, i_pix_valid, i_pix_nb, i_pix_data,
                               i_eol, i_eol_status, i_short_valid, i_short_vc, i_short_dt, i_short_data,
                               i_n3_req_ready, i_n3_pix_ready};
        end
    endgenerate

    // marquage (N2, N3) : sortie TX de llp_top vers le tampon
    wire        m_valid, m_last, m_marque, m_debord;
    wire [31:0] m_data;
    wire [2:0]  m_nb;
    wire [16:0] m_total;
    renvoi_marque u_marque (
        .clk(clk), .rst_n(rst_n),
        .i_verdict(n2_verdict | n3_verdict), .i_mauvais(n2 ? n2_mauvais : n3_mauvais),
        .i_valid(i_llp_valid & (n2 | n3)), .o_ready(o_llp_ready), .i_data(i_llp_data), .i_nb(i_llp_nb),
        .i_last(i_llp_last), .i_total(i_llp_total),
        .o_valid(m_valid), .i_ready(t_ready & (n2 | n3)), .o_data(m_data), .o_nb(m_nb), .o_last(m_last),
        .o_total(m_total), .o_evt_marque(m_marque), .o_debord(m_debord)
    );

    // tampon devant le LM
    renvoi_tampon #(.PROF(PROF), .PREREMPLI(PREREMPLI)) u_tampon (
        .clk(clk), .rst_n(rst_n),
        .i_valid(n1 ? n1_valid : m_valid), .o_ready(t_ready),
        .i_data(n1 ? n1_data : m_data), .i_nb(n1 ? n1_nb : m_nb), .i_last(n1 ? n1_last : m_last),
        .i_total(n1 ? n1_total : m_total),
        .o_valid(o_tx_valid), .i_ready(i_tx_ready), .o_data(o_tx_data), .o_nb(o_tx_nb), .o_last(o_tx_last),
        .o_total(o_tx_total), .o_max(o_tampon_max)
    );

    // compteurs
    wire [3:0] w_inc = {n1_bourre | n2_bourre | n3_bourre, n2_supprime, m_marque,
                        n1_perdu | n2_perdu | n3_perdu | m_debord};
    wire [4*CNT_W-1:0] w_cnt;
    genvar rang;
    generate
        for (rang = 0; rang < 4; rang = rang + 1) begin : g_cnt
            reg [CNT_W-1:0] r_cnt;
            always @(posedge clk or negedge rst_n)
                if (!rst_n)
                    r_cnt <= {CNT_W{1'b0}};
                else if (w_inc[rang] & ~&r_cnt)
                    r_cnt <= r_cnt + 1'b1;
            assign w_cnt[CNT_W*rang +: CNT_W] = r_cnt;
        end
    endgenerate
    assign {o_cnt_bourres, o_cnt_supprimes, o_cnt_marques, o_cnt_perdus} = w_cnt;
    assign evt_renvoi = |w_inc;

    renvoi_statut #(.STATUT(STATUT), .CNT_W(CNT_W)) u_statut (
        .clk(clk), .rst_n(rst_n), .i_actif(n1 | n2 | n3),
        .i_fe(i_fe), .i_fe_ok(i_fe_ok), .i_fe_vc(i_fe_vc), .i_err_hdr(i_err_hdr), .i_err_end(i_err_end),
        .i_loss(i_loss), .i_late(i_late), .i_renvoi(evt_renvoi),
        .i_cnt({o_cnt_perdus, i_cnt_trame, i_cnt_llp}),
        .o_valid(st_valid), .i_ready(st_ready_n1 | st_ready_n2 | st_ready_n3), .o_dt(st_dt), .o_data(st_data)
    );
endmodule

`default_nettype wire
