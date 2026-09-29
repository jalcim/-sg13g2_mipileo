// MSPHY5973 : D-PHY + CSI-2 + E/S, genere par scripts/gen_msphy5973.py, NE PAS EDITER.
// Cablage : doc/cablage_msphy5973.md. v1.0.0 : renvoi RX vers TX non fonctionnel, pont TX en cours (D38).
module MSPHY5973 (
    inout IOVDD,
    inout IOVSS,
    inout IOVDD_MIPI,
    inout IOVSS_MIPI,
    inout VDD,
    inout VSS,
    inout RX_CLK_P,
    inout RX_CLK_N,
    inout RX_D0_P,
    inout RX_D0_N,
    inout RX_D1_P,
    inout RX_D1_N,
    inout RX_D2_P,
    inout RX_D2_N,
    inout RX_D3_P,
    inout RX_D3_N,
    inout TX_CLK_P,
    inout TX_CLK_N,
    inout TX_D0_P,
    inout TX_D0_N,
    inout TX_D1_P,
    inout TX_D1_N,
    inout TX_D2_P,
    inout TX_D2_N,
    inout TX_D3_P,
    inout TX_D3_N,
    inout CLKIN_P,
    inout CLKIN_N,
    inout BANDGAP,
    inout TX_ANALOG,
    inout CLK_SYS,
    inout RST_N,
    inout RENVOI_MODE0,
    inout RENVOI_MODE1,
    inout EN0,
    inout EN1,
    inout EN2,
    inout EN3
);

    wire pol_e_POLN_RX, pol_e_VB, pol_e_PBIAS, pol_e_PS, pol_e_POLN;
    wire pol_n_POLN_RX, pol_n_VB, pol_n_PBIAS, pol_n_PS, pol_n_POLN;
    wire pol_w_POLN_RX, pol_w_VB, pol_w_PBIAS, pol_w_PS, pol_w_POLN;
    wire pol_s_POLN_RX, pol_s_VB, pol_s_PBIAS, pol_s_PS, pol_s_POLN;
    wire vbg, tx_analog_padres_nc;
    wire rx_clk_p_hs, rx_clk_n_hs, rx_clk_p_lp, rx_clk_n_lp;
    wire rx_d0_p_hs, rx_d0_n_hs, rx_d0_p_lp, rx_d0_n_lp;
    wire rx_d1_p_hs, rx_d1_n_hs, rx_d1_p_lp, rx_d1_n_lp;
    wire rx_d2_p_hs, rx_d2_n_hs, rx_d2_p_lp, rx_d2_n_lp;
    wire rx_d3_p_hs, rx_d3_n_hs, rx_d3_p_lp, rx_d3_n_lp;
    wire clkin_p_hs, clkin_n_hs, clkin_p_lp_nc, clkin_n_lp_nc;
    wire tx_clk_hsp, tx_clk_hsn, tx_clk_lpinp, tx_clk_lpinn;
    wire tx_d0_hsp, tx_d0_hsn, tx_d0_lpinp, tx_d0_lpinn;
    wire tx_d1_hsp, tx_d1_hsn, tx_d1_lpinp, tx_d1_lpinn;
    wire tx_d2_hsp, tx_d2_hsn, tx_d2_lpinp, tx_d2_lpinn;
    wire tx_d3_hsp, tx_d3_hsn, tx_d3_lpinp, tx_d3_lpinn;
    wire clk_sys, rst_n, rx_clk, clk_w, tx_ck;
    wire [3:0] enable;
    wire [1:0] renvoi_mode;
    wire [31:0] mots;
    wire [31:0] mot_p, mot_n;
    wire clk_w_p, clk_w_n;
    wire [3:0] hspr, hsreq, stop;
    wire [11:0] statut_phy;
    wire [3:0] tx_hs_oe, tx_lp_p, tx_lp_n;
    wire tx_clk_hs_oe, tx_clk_lp_p, tx_clk_lp_n;
    wire [3:0] tx_mot_p, tx_mot_n, tx_dout_p, tx_dout_n, tx_dout;
    wire tx_clk_w_p, tx_clk_w_n;

    // Coins : domaine MIPI a l'est et au nord, domaine IO a l'ouest et au sud
    (* keep *) MIPI_Corner corner_ne (
        `ifdef USE_POWER_PINS
        .IOVDD(IOVDD_MIPI), .IOVSS(IOVSS_MIPI), .VDD(VDD), .VSS(VSS)
        `endif
    );
    (* keep *) MIPI_Corner corner_sw (
        `ifdef USE_POWER_PINS
        .IOVDD(IOVDD), .IOVSS(IOVSS), .VDD(VDD), .VSS(VSS)
        `endif
    );
    (* keep *) MIPI_CornerBreaker corner_nw (
        `ifdef USE_POWER_PINS
        .IOVDD(IOVDD), .IOVSS(IOVSS), .IOVDD_MIPI(IOVDD_MIPI), .IOVSS_MIPI(IOVSS_MIPI), .VDD(VDD), .VSS(VSS)
        `endif
    );
    (* keep *) MIPI_CornerBreaker corner_se (
        `ifdef USE_POWER_PINS
        .IOVDD(IOVDD), .IOVSS(IOVSS), .IOVDD_MIPI(IOVDD_MIPI), .IOVSS_MIPI(IOVSS_MIPI), .VDD(VDD), .VSS(VSS)
        `endif
    );

    // Est : RX
    (* keep *) MIPI_IOPadIOVdd iovdd_mipi_pad (
        `ifdef USE_POWER_PINS
        .IOVDD(IOVDD_MIPI), .IOVSS(IOVSS_MIPI), .VDD(VDD), .VSS(VSS),
        `endif
        .POLN_RX(pol_e_POLN_RX), .VB(pol_e_VB), .PBIAS(pol_e_PBIAS), .PS(pol_e_PS), .POLN(pol_e_POLN)
    );

    (* keep *) MIPI_IOPadIOVss iovss_mipi_pad (
        `ifdef USE_POWER_PINS
        .IOVDD(IOVDD_MIPI), .IOVSS(IOVSS_MIPI), .VDD(VDD), .VSS(VSS),
        `endif
        .POLN_RX(pol_e_POLN_RX), .VB(pol_e_VB), .PBIAS(pol_e_PBIAS), .PS(pol_e_PS), .POLN(pol_e_POLN)
    );

    (* keep *) MIPI_IOPadBandgap bandgap_pad (
        `ifdef USE_POWER_PINS
        .IOVDD(IOVDD_MIPI), .IOVSS(IOVSS_MIPI), .VDD(VDD), .VSS(VSS),
        `endif
        .POLN_RX(pol_e_POLN_RX), .VB(pol_e_VB), .PBIAS(pol_e_PBIAS), .PS(pol_e_PS), .POLN(pol_e_POLN), .PAD(BANDGAP), .VBG(vbg)
    );

    (* keep *) MIPI_IOPadRX rx_clk_p_pad (
        `ifdef USE_POWER_PINS
        .IOVDD(IOVDD_MIPI), .IOVSS(IOVSS_MIPI), .VDD(VDD), .VSS(VSS),
        `endif
        .POLN_RX(pol_e_POLN_RX), .VB(pol_e_VB), .PBIAS(pol_e_PBIAS), .PS(pol_e_PS), .POLN(pol_e_POLN), .PAD(RX_CLK_P), .OUT(rx_clk_p_hs), .P2C(rx_clk_p_lp)
    );

    (* keep *) MIPI_IOPadRX rx_clk_n_pad (
        `ifdef USE_POWER_PINS
        .IOVDD(IOVDD_MIPI), .IOVSS(IOVSS_MIPI), .VDD(VDD), .VSS(VSS),
        `endif
        .POLN_RX(pol_e_POLN_RX), .VB(pol_e_VB), .PBIAS(pol_e_PBIAS), .PS(pol_e_PS), .POLN(pol_e_POLN), .PAD(RX_CLK_N), .OUT(rx_clk_n_hs), .P2C(rx_clk_n_lp)
    );

    (* keep *) MIPI_IOPadRX rx_d0_p_pad (
        `ifdef USE_POWER_PINS
        .IOVDD(IOVDD_MIPI), .IOVSS(IOVSS_MIPI), .VDD(VDD), .VSS(VSS),
        `endif
        .POLN_RX(pol_e_POLN_RX), .VB(pol_e_VB), .PBIAS(pol_e_PBIAS), .PS(pol_e_PS), .POLN(pol_e_POLN), .PAD(RX_D0_P), .OUT(rx_d0_p_hs), .P2C(rx_d0_p_lp)
    );

    (* keep *) MIPI_IOPadRX rx_d0_n_pad (
        `ifdef USE_POWER_PINS
        .IOVDD(IOVDD_MIPI), .IOVSS(IOVSS_MIPI), .VDD(VDD), .VSS(VSS),
        `endif
        .POLN_RX(pol_e_POLN_RX), .VB(pol_e_VB), .PBIAS(pol_e_PBIAS), .PS(pol_e_PS), .POLN(pol_e_POLN), .PAD(RX_D0_N), .OUT(rx_d0_n_hs), .P2C(rx_d0_n_lp)
    );

    (* keep *) MIPI_IOPadRX rx_d1_p_pad (
        `ifdef USE_POWER_PINS
        .IOVDD(IOVDD_MIPI), .IOVSS(IOVSS_MIPI), .VDD(VDD), .VSS(VSS),
        `endif
        .POLN_RX(pol_e_POLN_RX), .VB(pol_e_VB), .PBIAS(pol_e_PBIAS), .PS(pol_e_PS), .POLN(pol_e_POLN), .PAD(RX_D1_P), .OUT(rx_d1_p_hs), .P2C(rx_d1_p_lp)
    );

    (* keep *) MIPI_IOPadRX rx_d1_n_pad (
        `ifdef USE_POWER_PINS
        .IOVDD(IOVDD_MIPI), .IOVSS(IOVSS_MIPI), .VDD(VDD), .VSS(VSS),
        `endif
        .POLN_RX(pol_e_POLN_RX), .VB(pol_e_VB), .PBIAS(pol_e_PBIAS), .PS(pol_e_PS), .POLN(pol_e_POLN), .PAD(RX_D1_N), .OUT(rx_d1_n_hs), .P2C(rx_d1_n_lp)
    );

    (* keep *) MIPI_IOPadRX rx_d2_p_pad (
        `ifdef USE_POWER_PINS
        .IOVDD(IOVDD_MIPI), .IOVSS(IOVSS_MIPI), .VDD(VDD), .VSS(VSS),
        `endif
        .POLN_RX(pol_e_POLN_RX), .VB(pol_e_VB), .PBIAS(pol_e_PBIAS), .PS(pol_e_PS), .POLN(pol_e_POLN), .PAD(RX_D2_P), .OUT(rx_d2_p_hs), .P2C(rx_d2_p_lp)
    );

    (* keep *) MIPI_IOPadRX rx_d2_n_pad (
        `ifdef USE_POWER_PINS
        .IOVDD(IOVDD_MIPI), .IOVSS(IOVSS_MIPI), .VDD(VDD), .VSS(VSS),
        `endif
        .POLN_RX(pol_e_POLN_RX), .VB(pol_e_VB), .PBIAS(pol_e_PBIAS), .PS(pol_e_PS), .POLN(pol_e_POLN), .PAD(RX_D2_N), .OUT(rx_d2_n_hs), .P2C(rx_d2_n_lp)
    );

    (* keep *) MIPI_IOPadRX rx_d3_p_pad (
        `ifdef USE_POWER_PINS
        .IOVDD(IOVDD_MIPI), .IOVSS(IOVSS_MIPI), .VDD(VDD), .VSS(VSS),
        `endif
        .POLN_RX(pol_e_POLN_RX), .VB(pol_e_VB), .PBIAS(pol_e_PBIAS), .PS(pol_e_PS), .POLN(pol_e_POLN), .PAD(RX_D3_P), .OUT(rx_d3_p_hs), .P2C(rx_d3_p_lp)
    );

    (* keep *) MIPI_IOPadRX rx_d3_n_pad (
        `ifdef USE_POWER_PINS
        .IOVDD(IOVDD_MIPI), .IOVSS(IOVSS_MIPI), .VDD(VDD), .VSS(VSS),
        `endif
        .POLN_RX(pol_e_POLN_RX), .VB(pol_e_VB), .PBIAS(pol_e_PBIAS), .PS(pol_e_PS), .POLN(pol_e_POLN), .PAD(RX_D3_N), .OUT(rx_d3_n_hs), .P2C(rx_d3_n_lp)
    );

    // Nord : TX et CLKIN
    (* keep *) MIPI_IOPadVdd vdd_pad (
        `ifdef USE_POWER_PINS
        .IOVDD(IOVDD_MIPI), .IOVSS(IOVSS_MIPI), .VDD(VDD), .VSS(VSS),
        `endif
        .POLN_RX(pol_n_POLN_RX), .VB(pol_n_VB), .PBIAS(pol_n_PBIAS), .PS(pol_n_PS), .POLN(pol_n_POLN)
    );

    (* keep *) MIPI_IOPadVss vss_pad (
        `ifdef USE_POWER_PINS
        .IOVDD(IOVDD_MIPI), .IOVSS(IOVSS_MIPI), .VDD(VDD), .VSS(VSS),
        `endif
        .POLN_RX(pol_n_POLN_RX), .VB(pol_n_VB), .PBIAS(pol_n_PBIAS), .PS(pol_n_PS), .POLN(pol_n_POLN)
    );

    (* keep *) MIPI_IOPadAnalog tx_analog_pad (
        `ifdef USE_POWER_PINS
        .IOVDD(IOVDD_MIPI), .IOVSS(IOVSS_MIPI), .VDD(VDD), .VSS(VSS),
        `endif
        .POLN_RX(pol_n_POLN_RX), .VB(pol_n_VB), .PBIAS(pol_n_PBIAS), .PS(pol_n_PS), .POLN(pol_n_POLN), .PAD(TX_ANALOG), .PADRES(tx_analog_padres_nc)
    );

    (* keep *) MIPI_IOPadTX tx_clk_p_pad (
        `ifdef USE_POWER_PINS
        .IOVDD(IOVDD_MIPI), .IOVSS(IOVSS_MIPI), .VDD(VDD), .VSS(VSS),
        `endif
        .POLN_RX(pol_n_POLN_RX), .VB(pol_n_VB), .PBIAS(pol_n_PBIAS), .PS(pol_n_PS), .POLN(pol_n_POLN), .PAD(TX_CLK_P), .IN_HS(tx_clk_hsp), .LP_IN(tx_clk_lpinp)
    );

    (* keep *) MIPI_IOPadTX tx_clk_n_pad (
        `ifdef USE_POWER_PINS
        .IOVDD(IOVDD_MIPI), .IOVSS(IOVSS_MIPI), .VDD(VDD), .VSS(VSS),
        `endif
        .POLN_RX(pol_n_POLN_RX), .VB(pol_n_VB), .PBIAS(pol_n_PBIAS), .PS(pol_n_PS), .POLN(pol_n_POLN), .PAD(TX_CLK_N), .IN_HS(tx_clk_hsn), .LP_IN(tx_clk_lpinn)
    );

    (* keep *) MIPI_IOPadTX tx_d0_p_pad (
        `ifdef USE_POWER_PINS
        .IOVDD(IOVDD_MIPI), .IOVSS(IOVSS_MIPI), .VDD(VDD), .VSS(VSS),
        `endif
        .POLN_RX(pol_n_POLN_RX), .VB(pol_n_VB), .PBIAS(pol_n_PBIAS), .PS(pol_n_PS), .POLN(pol_n_POLN), .PAD(TX_D0_P), .IN_HS(tx_d0_hsp), .LP_IN(tx_d0_lpinp)
    );

    (* keep *) MIPI_IOPadTX tx_d0_n_pad (
        `ifdef USE_POWER_PINS
        .IOVDD(IOVDD_MIPI), .IOVSS(IOVSS_MIPI), .VDD(VDD), .VSS(VSS),
        `endif
        .POLN_RX(pol_n_POLN_RX), .VB(pol_n_VB), .PBIAS(pol_n_PBIAS), .PS(pol_n_PS), .POLN(pol_n_POLN), .PAD(TX_D0_N), .IN_HS(tx_d0_hsn), .LP_IN(tx_d0_lpinn)
    );

    (* keep *) MIPI_IOPadTX tx_d1_p_pad (
        `ifdef USE_POWER_PINS
        .IOVDD(IOVDD_MIPI), .IOVSS(IOVSS_MIPI), .VDD(VDD), .VSS(VSS),
        `endif
        .POLN_RX(pol_n_POLN_RX), .VB(pol_n_VB), .PBIAS(pol_n_PBIAS), .PS(pol_n_PS), .POLN(pol_n_POLN), .PAD(TX_D1_P), .IN_HS(tx_d1_hsp), .LP_IN(tx_d1_lpinp)
    );

    (* keep *) MIPI_IOPadTX tx_d1_n_pad (
        `ifdef USE_POWER_PINS
        .IOVDD(IOVDD_MIPI), .IOVSS(IOVSS_MIPI), .VDD(VDD), .VSS(VSS),
        `endif
        .POLN_RX(pol_n_POLN_RX), .VB(pol_n_VB), .PBIAS(pol_n_PBIAS), .PS(pol_n_PS), .POLN(pol_n_POLN), .PAD(TX_D1_N), .IN_HS(tx_d1_hsn), .LP_IN(tx_d1_lpinn)
    );

    (* keep *) MIPI_IOPadTX tx_d2_p_pad (
        `ifdef USE_POWER_PINS
        .IOVDD(IOVDD_MIPI), .IOVSS(IOVSS_MIPI), .VDD(VDD), .VSS(VSS),
        `endif
        .POLN_RX(pol_n_POLN_RX), .VB(pol_n_VB), .PBIAS(pol_n_PBIAS), .PS(pol_n_PS), .POLN(pol_n_POLN), .PAD(TX_D2_P), .IN_HS(tx_d2_hsp), .LP_IN(tx_d2_lpinp)
    );

    (* keep *) MIPI_IOPadTX tx_d2_n_pad (
        `ifdef USE_POWER_PINS
        .IOVDD(IOVDD_MIPI), .IOVSS(IOVSS_MIPI), .VDD(VDD), .VSS(VSS),
        `endif
        .POLN_RX(pol_n_POLN_RX), .VB(pol_n_VB), .PBIAS(pol_n_PBIAS), .PS(pol_n_PS), .POLN(pol_n_POLN), .PAD(TX_D2_N), .IN_HS(tx_d2_hsn), .LP_IN(tx_d2_lpinn)
    );

    (* keep *) MIPI_IOPadTX tx_d3_p_pad (
        `ifdef USE_POWER_PINS
        .IOVDD(IOVDD_MIPI), .IOVSS(IOVSS_MIPI), .VDD(VDD), .VSS(VSS),
        `endif
        .POLN_RX(pol_n_POLN_RX), .VB(pol_n_VB), .PBIAS(pol_n_PBIAS), .PS(pol_n_PS), .POLN(pol_n_POLN), .PAD(TX_D3_P), .IN_HS(tx_d3_hsp), .LP_IN(tx_d3_lpinp)
    );

    (* keep *) MIPI_IOPadTX tx_d3_n_pad (
        `ifdef USE_POWER_PINS
        .IOVDD(IOVDD_MIPI), .IOVSS(IOVSS_MIPI), .VDD(VDD), .VSS(VSS),
        `endif
        .POLN_RX(pol_n_POLN_RX), .VB(pol_n_VB), .PBIAS(pol_n_PBIAS), .PS(pol_n_PS), .POLN(pol_n_POLN), .PAD(TX_D3_N), .IN_HS(tx_d3_hsn), .LP_IN(tx_d3_lpinn)
    );

    (* keep *) MIPI_IOPadRX clkin_n_pad (
        `ifdef USE_POWER_PINS
        .IOVDD(IOVDD_MIPI), .IOVSS(IOVSS_MIPI), .VDD(VDD), .VSS(VSS),
        `endif
        .POLN_RX(pol_n_POLN_RX), .VB(pol_n_VB), .PBIAS(pol_n_PBIAS), .PS(pol_n_PS), .POLN(pol_n_POLN), .PAD(CLKIN_N), .OUT(clkin_n_hs), .P2C(clkin_n_lp_nc)
    );

    (* keep *) MIPI_IOPadRX clkin_p_pad (
        `ifdef USE_POWER_PINS
        .IOVDD(IOVDD_MIPI), .IOVSS(IOVSS_MIPI), .VDD(VDD), .VSS(VSS),
        `endif
        .POLN_RX(pol_n_POLN_RX), .VB(pol_n_VB), .PBIAS(pol_n_PBIAS), .PS(pol_n_PS), .POLN(pol_n_POLN), .PAD(CLKIN_P), .OUT(clkin_p_hs), .P2C(clkin_p_lp_nc)
    );

    // Ouest et sud : alimentations et entrees numeriques du domaine IO
    (* keep *) MIPI_IOPadIOVdd iovdd_pad (
        `ifdef USE_POWER_PINS
        .IOVDD(IOVDD), .IOVSS(IOVSS), .VDD(VDD), .VSS(VSS),
        `endif
        .POLN_RX(pol_w_POLN_RX), .VB(pol_w_VB), .PBIAS(pol_w_PBIAS), .PS(pol_w_PS), .POLN(pol_w_POLN)
    );

    (* keep *) MIPI_IOPadIOVss iovss_pad (
        `ifdef USE_POWER_PINS
        .IOVDD(IOVDD), .IOVSS(IOVSS), .VDD(VDD), .VSS(VSS),
        `endif
        .POLN_RX(pol_w_POLN_RX), .VB(pol_w_VB), .PBIAS(pol_w_PBIAS), .PS(pol_w_PS), .POLN(pol_w_POLN)
    );

    (* keep *) MIPI_IOPadVdd vdd_s_pad (
        `ifdef USE_POWER_PINS
        .IOVDD(IOVDD), .IOVSS(IOVSS), .VDD(VDD), .VSS(VSS),
        `endif
        .POLN_RX(pol_s_POLN_RX), .VB(pol_s_VB), .PBIAS(pol_s_PBIAS), .PS(pol_s_PS), .POLN(pol_s_POLN)
    );

    (* keep *) MIPI_IOPadVss vss_s_pad (
        `ifdef USE_POWER_PINS
        .IOVDD(IOVDD), .IOVSS(IOVSS), .VDD(VDD), .VSS(VSS),
        `endif
        .POLN_RX(pol_s_POLN_RX), .VB(pol_s_VB), .PBIAS(pol_s_PBIAS), .PS(pol_s_PS), .POLN(pol_s_POLN)
    );

    (* keep *) MIPI_IOPadIn clk_sys_pad (
        `ifdef USE_POWER_PINS
        .IOVDD(IOVDD), .IOVSS(IOVSS), .VDD(VDD), .VSS(VSS),
        `endif
        .POLN_RX(pol_w_POLN_RX), .VB(pol_w_VB), .PBIAS(pol_w_PBIAS), .PS(pol_w_PS), .POLN(pol_w_POLN), .PAD(CLK_SYS), .P2C(clk_sys)
    );

    (* keep *) MIPI_IOPadIn rst_n_pad (
        `ifdef USE_POWER_PINS
        .IOVDD(IOVDD), .IOVSS(IOVSS), .VDD(VDD), .VSS(VSS),
        `endif
        .POLN_RX(pol_w_POLN_RX), .VB(pol_w_VB), .PBIAS(pol_w_PBIAS), .PS(pol_w_PS), .POLN(pol_w_POLN), .PAD(RST_N), .P2C(rst_n)
    );

    (* keep *) MIPI_IOPadIn renvoi_mode0_pad (
        `ifdef USE_POWER_PINS
        .IOVDD(IOVDD), .IOVSS(IOVSS), .VDD(VDD), .VSS(VSS),
        `endif
        .POLN_RX(pol_w_POLN_RX), .VB(pol_w_VB), .PBIAS(pol_w_PBIAS), .PS(pol_w_PS), .POLN(pol_w_POLN), .PAD(RENVOI_MODE0), .P2C(renvoi_mode[0])
    );

    (* keep *) MIPI_IOPadIn renvoi_mode1_pad (
        `ifdef USE_POWER_PINS
        .IOVDD(IOVDD), .IOVSS(IOVSS), .VDD(VDD), .VSS(VSS),
        `endif
        .POLN_RX(pol_w_POLN_RX), .VB(pol_w_VB), .PBIAS(pol_w_PBIAS), .PS(pol_w_PS), .POLN(pol_w_POLN), .PAD(RENVOI_MODE1), .P2C(renvoi_mode[1])
    );

    (* keep *) MIPI_IOPadIn en0_pad (
        `ifdef USE_POWER_PINS
        .IOVDD(IOVDD), .IOVSS(IOVSS), .VDD(VDD), .VSS(VSS),
        `endif
        .POLN_RX(pol_s_POLN_RX), .VB(pol_s_VB), .PBIAS(pol_s_PBIAS), .PS(pol_s_PS), .POLN(pol_s_POLN), .PAD(EN0), .P2C(enable[0])
    );

    (* keep *) MIPI_IOPadIn en1_pad (
        `ifdef USE_POWER_PINS
        .IOVDD(IOVDD), .IOVSS(IOVSS), .VDD(VDD), .VSS(VSS),
        `endif
        .POLN_RX(pol_s_POLN_RX), .VB(pol_s_VB), .PBIAS(pol_s_PBIAS), .PS(pol_s_PS), .POLN(pol_s_POLN), .PAD(EN1), .P2C(enable[1])
    );

    (* keep *) MIPI_IOPadIn en2_pad (
        `ifdef USE_POWER_PINS
        .IOVDD(IOVDD), .IOVSS(IOVSS), .VDD(VDD), .VSS(VSS),
        `endif
        .POLN_RX(pol_s_POLN_RX), .VB(pol_s_VB), .PBIAS(pol_s_PBIAS), .PS(pol_s_PS), .POLN(pol_s_POLN), .PAD(EN2), .P2C(enable[2])
    );

    (* keep *) MIPI_IOPadIn en3_pad (
        `ifdef USE_POWER_PINS
        .IOVDD(IOVDD), .IOVSS(IOVSS), .VDD(VDD), .VSS(VSS),
        `endif
        .POLN_RX(pol_s_POLN_RX), .VB(pol_s_VB), .PBIAS(pol_s_PBIAS), .PS(pol_s_PS), .POLN(pol_s_POLN), .PAD(EN3), .P2C(enable[3])
    );

    // RX : deserialiseur CML, machines d'etats, conversion vers CMOS
    (* keep *) sr16_rx4 sr16_rx4 (
        `ifdef USE_POWER_PINS
        .VDD(VDD), .VSS(VSS),
        `endif
        .POLN(pol_e_POLN), .CK_P(rx_clk_p_hs), .CK_N(rx_clk_n_hs),
        .D0_P(rx_d0_p_hs), .D0_N(rx_d0_n_hs), .D1_P(rx_d1_p_hs), .D1_N(rx_d1_n_hs), .D2_P(rx_d2_p_hs), .D2_N(rx_d2_n_hs), .D3_P(rx_d3_p_hs), .D3_N(rx_d3_n_hs),
        .MOT0_P(mot_p[0]), .MOT0_N(mot_n[0]), .MOT1_P(mot_p[1]), .MOT1_N(mot_n[1]), .MOT2_P(mot_p[2]), .MOT2_N(mot_n[2]), .MOT3_P(mot_p[3]), .MOT3_N(mot_n[3]), .MOT4_P(mot_p[4]), .MOT4_N(mot_n[4]), .MOT5_P(mot_p[5]), .MOT5_N(mot_n[5]), .MOT6_P(mot_p[6]), .MOT6_N(mot_n[6]), .MOT7_P(mot_p[7]), .MOT7_N(mot_n[7]), .MOT8_P(mot_p[8]), .MOT8_N(mot_n[8]), .MOT9_P(mot_p[9]), .MOT9_N(mot_n[9]), .MOT10_P(mot_p[10]), .MOT10_N(mot_n[10]), .MOT11_P(mot_p[11]), .MOT11_N(mot_n[11]), .MOT12_P(mot_p[12]), .MOT12_N(mot_n[12]), .MOT13_P(mot_p[13]), .MOT13_N(mot_n[13]), .MOT14_P(mot_p[14]), .MOT14_N(mot_n[14]), .MOT15_P(mot_p[15]), .MOT15_N(mot_n[15]), .MOT16_P(mot_p[16]), .MOT16_N(mot_n[16]), .MOT17_P(mot_p[17]), .MOT17_N(mot_n[17]), .MOT18_P(mot_p[18]), .MOT18_N(mot_n[18]), .MOT19_P(mot_p[19]), .MOT19_N(mot_n[19]), .MOT20_P(mot_p[20]), .MOT20_N(mot_n[20]), .MOT21_P(mot_p[21]), .MOT21_N(mot_n[21]), .MOT22_P(mot_p[22]), .MOT22_N(mot_n[22]), .MOT23_P(mot_p[23]), .MOT23_N(mot_n[23]), .MOT24_P(mot_p[24]), .MOT24_N(mot_n[24]), .MOT25_P(mot_p[25]), .MOT25_N(mot_n[25]), .MOT26_P(mot_p[26]), .MOT26_N(mot_n[26]), .MOT27_P(mot_p[27]), .MOT27_N(mot_n[27]), .MOT28_P(mot_p[28]), .MOT28_N(mot_n[28]), .MOT29_P(mot_p[29]), .MOT29_N(mot_n[29]), .MOT30_P(mot_p[30]), .MOT30_N(mot_n[30]), .MOT31_P(mot_p[31]), .MOT31_N(mot_n[31]),
        .CLK_W_P(clk_w_p), .CLK_W_N(clk_w_n)
    );
    (* keep *) cml_to_cmos c2c_mot0 (
        `ifdef USE_POWER_PINS
        .VDD(VDD), .VSS(VSS),
        `endif
        .INP(mot_p[0]), .INN(mot_n[0]), .Y(mots[0])
    );
    (* keep *) cml_to_cmos c2c_mot1 (
        `ifdef USE_POWER_PINS
        .VDD(VDD), .VSS(VSS),
        `endif
        .INP(mot_p[1]), .INN(mot_n[1]), .Y(mots[1])
    );
    (* keep *) cml_to_cmos c2c_mot2 (
        `ifdef USE_POWER_PINS
        .VDD(VDD), .VSS(VSS),
        `endif
        .INP(mot_p[2]), .INN(mot_n[2]), .Y(mots[2])
    );
    (* keep *) cml_to_cmos c2c_mot3 (
        `ifdef USE_POWER_PINS
        .VDD(VDD), .VSS(VSS),
        `endif
        .INP(mot_p[3]), .INN(mot_n[3]), .Y(mots[3])
    );
    (* keep *) cml_to_cmos c2c_mot4 (
        `ifdef USE_POWER_PINS
        .VDD(VDD), .VSS(VSS),
        `endif
        .INP(mot_p[4]), .INN(mot_n[4]), .Y(mots[4])
    );
    (* keep *) cml_to_cmos c2c_mot5 (
        `ifdef USE_POWER_PINS
        .VDD(VDD), .VSS(VSS),
        `endif
        .INP(mot_p[5]), .INN(mot_n[5]), .Y(mots[5])
    );
    (* keep *) cml_to_cmos c2c_mot6 (
        `ifdef USE_POWER_PINS
        .VDD(VDD), .VSS(VSS),
        `endif
        .INP(mot_p[6]), .INN(mot_n[6]), .Y(mots[6])
    );
    (* keep *) cml_to_cmos c2c_mot7 (
        `ifdef USE_POWER_PINS
        .VDD(VDD), .VSS(VSS),
        `endif
        .INP(mot_p[7]), .INN(mot_n[7]), .Y(mots[7])
    );
    (* keep *) cml_to_cmos c2c_mot8 (
        `ifdef USE_POWER_PINS
        .VDD(VDD), .VSS(VSS),
        `endif
        .INP(mot_p[8]), .INN(mot_n[8]), .Y(mots[8])
    );
    (* keep *) cml_to_cmos c2c_mot9 (
        `ifdef USE_POWER_PINS
        .VDD(VDD), .VSS(VSS),
        `endif
        .INP(mot_p[9]), .INN(mot_n[9]), .Y(mots[9])
    );
    (* keep *) cml_to_cmos c2c_mot10 (
        `ifdef USE_POWER_PINS
        .VDD(VDD), .VSS(VSS),
        `endif
        .INP(mot_p[10]), .INN(mot_n[10]), .Y(mots[10])
    );
    (* keep *) cml_to_cmos c2c_mot11 (
        `ifdef USE_POWER_PINS
        .VDD(VDD), .VSS(VSS),
        `endif
        .INP(mot_p[11]), .INN(mot_n[11]), .Y(mots[11])
    );
    (* keep *) cml_to_cmos c2c_mot12 (
        `ifdef USE_POWER_PINS
        .VDD(VDD), .VSS(VSS),
        `endif
        .INP(mot_p[12]), .INN(mot_n[12]), .Y(mots[12])
    );
    (* keep *) cml_to_cmos c2c_mot13 (
        `ifdef USE_POWER_PINS
        .VDD(VDD), .VSS(VSS),
        `endif
        .INP(mot_p[13]), .INN(mot_n[13]), .Y(mots[13])
    );
    (* keep *) cml_to_cmos c2c_mot14 (
        `ifdef USE_POWER_PINS
        .VDD(VDD), .VSS(VSS),
        `endif
        .INP(mot_p[14]), .INN(mot_n[14]), .Y(mots[14])
    );
    (* keep *) cml_to_cmos c2c_mot15 (
        `ifdef USE_POWER_PINS
        .VDD(VDD), .VSS(VSS),
        `endif
        .INP(mot_p[15]), .INN(mot_n[15]), .Y(mots[15])
    );
    (* keep *) cml_to_cmos c2c_mot16 (
        `ifdef USE_POWER_PINS
        .VDD(VDD), .VSS(VSS),
        `endif
        .INP(mot_p[16]), .INN(mot_n[16]), .Y(mots[16])
    );
    (* keep *) cml_to_cmos c2c_mot17 (
        `ifdef USE_POWER_PINS
        .VDD(VDD), .VSS(VSS),
        `endif
        .INP(mot_p[17]), .INN(mot_n[17]), .Y(mots[17])
    );
    (* keep *) cml_to_cmos c2c_mot18 (
        `ifdef USE_POWER_PINS
        .VDD(VDD), .VSS(VSS),
        `endif
        .INP(mot_p[18]), .INN(mot_n[18]), .Y(mots[18])
    );
    (* keep *) cml_to_cmos c2c_mot19 (
        `ifdef USE_POWER_PINS
        .VDD(VDD), .VSS(VSS),
        `endif
        .INP(mot_p[19]), .INN(mot_n[19]), .Y(mots[19])
    );
    (* keep *) cml_to_cmos c2c_mot20 (
        `ifdef USE_POWER_PINS
        .VDD(VDD), .VSS(VSS),
        `endif
        .INP(mot_p[20]), .INN(mot_n[20]), .Y(mots[20])
    );
    (* keep *) cml_to_cmos c2c_mot21 (
        `ifdef USE_POWER_PINS
        .VDD(VDD), .VSS(VSS),
        `endif
        .INP(mot_p[21]), .INN(mot_n[21]), .Y(mots[21])
    );
    (* keep *) cml_to_cmos c2c_mot22 (
        `ifdef USE_POWER_PINS
        .VDD(VDD), .VSS(VSS),
        `endif
        .INP(mot_p[22]), .INN(mot_n[22]), .Y(mots[22])
    );
    (* keep *) cml_to_cmos c2c_mot23 (
        `ifdef USE_POWER_PINS
        .VDD(VDD), .VSS(VSS),
        `endif
        .INP(mot_p[23]), .INN(mot_n[23]), .Y(mots[23])
    );
    (* keep *) cml_to_cmos c2c_mot24 (
        `ifdef USE_POWER_PINS
        .VDD(VDD), .VSS(VSS),
        `endif
        .INP(mot_p[24]), .INN(mot_n[24]), .Y(mots[24])
    );
    (* keep *) cml_to_cmos c2c_mot25 (
        `ifdef USE_POWER_PINS
        .VDD(VDD), .VSS(VSS),
        `endif
        .INP(mot_p[25]), .INN(mot_n[25]), .Y(mots[25])
    );
    (* keep *) cml_to_cmos c2c_mot26 (
        `ifdef USE_POWER_PINS
        .VDD(VDD), .VSS(VSS),
        `endif
        .INP(mot_p[26]), .INN(mot_n[26]), .Y(mots[26])
    );
    (* keep *) cml_to_cmos c2c_mot27 (
        `ifdef USE_POWER_PINS
        .VDD(VDD), .VSS(VSS),
        `endif
        .INP(mot_p[27]), .INN(mot_n[27]), .Y(mots[27])
    );
    (* keep *) cml_to_cmos c2c_mot28 (
        `ifdef USE_POWER_PINS
        .VDD(VDD), .VSS(VSS),
        `endif
        .INP(mot_p[28]), .INN(mot_n[28]), .Y(mots[28])
    );
    (* keep *) cml_to_cmos c2c_mot29 (
        `ifdef USE_POWER_PINS
        .VDD(VDD), .VSS(VSS),
        `endif
        .INP(mot_p[29]), .INN(mot_n[29]), .Y(mots[29])
    );
    (* keep *) cml_to_cmos c2c_mot30 (
        `ifdef USE_POWER_PINS
        .VDD(VDD), .VSS(VSS),
        `endif
        .INP(mot_p[30]), .INN(mot_n[30]), .Y(mots[30])
    );
    (* keep *) cml_to_cmos c2c_mot31 (
        `ifdef USE_POWER_PINS
        .VDD(VDD), .VSS(VSS),
        `endif
        .INP(mot_p[31]), .INN(mot_n[31]), .Y(mots[31])
    );
    (* keep *) cml_to_cmos c2c_clk_w (
        `ifdef USE_POWER_PINS
        .VDD(VDD), .VSS(VSS),
        `endif
        .INP(clk_w_p), .INN(clk_w_n), .Y(clk_w)
    );
    (* keep *) cml_to_cmos c2c_rx_clk (
        `ifdef USE_POWER_PINS
        .VDD(VDD), .VSS(VSS),
        `endif
        .INP(rx_clk_p_hs), .INN(rx_clk_n_hs), .Y(rx_clk)
    );
    (* keep *) cml_to_cmos c2c_tx_ck (
        `ifdef USE_POWER_PINS
        .VDD(VDD), .VSS(VSS),
        `endif
        .INP(clkin_p_hs), .INN(clkin_n_hs), .Y(tx_ck)
    );
    (* keep *) cml_to_cmos c2c_tx_dout0 (
        `ifdef USE_POWER_PINS
        .VDD(VDD), .VSS(VSS),
        `endif
        .INP(tx_dout_p[0]), .INN(tx_dout_n[0]), .Y(tx_dout[0])
    );
    (* keep *) cml_to_cmos c2c_tx_dout1 (
        `ifdef USE_POWER_PINS
        .VDD(VDD), .VSS(VSS),
        `endif
        .INP(tx_dout_p[1]), .INN(tx_dout_n[1]), .Y(tx_dout[1])
    );
    (* keep *) cml_to_cmos c2c_tx_dout2 (
        `ifdef USE_POWER_PINS
        .VDD(VDD), .VSS(VSS),
        `endif
        .INP(tx_dout_p[2]), .INN(tx_dout_n[2]), .Y(tx_dout[2])
    );
    (* keep *) cml_to_cmos c2c_tx_dout3 (
        `ifdef USE_POWER_PINS
        .VDD(VDD), .VSS(VSS),
        `endif
        .INP(tx_dout_p[3]), .INN(tx_dout_n[3]), .Y(tx_dout[3])
    );
    (* keep *) dphy_rx dphy_rx (
        `ifdef USE_POWER_PINS
        .VPWR(VDD), .VGND(VSS),
        `endif
        .PG(), .rx_clk(rx_clk), .clk_lp_p(rx_clk_p_lp), .clk_lp_n(rx_clk_n_lp),
        .clk_stop(), .clk_term_en(), .clk_rx_en(), .clk_miss(),
        .lp_p({rx_d3_p_lp, rx_d2_p_lp, rx_d1_p_lp, rx_d0_p_lp}),
        .lp_n({rx_d3_n_lp, rx_d2_n_lp, rx_d1_n_lp, rx_d0_n_lp}),
        .stop(stop), .term_en(), .hs_rx_en(), .hsreq(hsreq), .hspr(hspr)
    );
    assign statut_phy = {hspr[3], hsreq[3], stop[3], hspr[2], hsreq[2], stop[2], hspr[1], hsreq[1], stop[1], hspr[0], hsreq[0], stop[0]};

    // CSI-2 : macro dure t4 g13 (78524823). Entrees d'application a 0, sorties d'application libres.
    // Alimentation de csi2_top par PDN_MACRO_CONNECTIONS : sa boite noire n'a pas de broches VPWR / VGND.
    (* keep *) csi2_top csi2_top (
        .clk(clk_sys), .rst_n(rst_n), .enable(enable), .renvoi_mode(renvoi_mode),
        .clk_w(clk_w), .mots(mots), .hspr(hspr), .statut_phy(statut_phy),
        .cnt_gel(1'b0), .tx_pix_valid(1'b0), .tx_req_valid(1'b0), .tx_pix_data(112'b0),
        .tx_pix_nb(4'b0), .tx_req_dt(6'b0), .tx_req_vc(2'b0), .tx_req_width(16'b0),
        .fifo_tx_full(1'b0), .fifo_tx_wr(), .fifo_tx_wdata(), .fifo_tx_wlanes(), .fifo_tx_fin(), .tx_init()
    );

    // TX : machines d'etats, serialiseurs et pre-drivers. HS inactif en v1.0.0 (pas de pont TX ni de /4 TX).
    (* keep *) dphy_tx dphy_tx (
        `ifdef USE_POWER_PINS
        .VPWR(VDD), .VGND(VSS),
        `endif
        .PG(), .clk(tx_ck), .rst(~rst_n), .clk_request(1'b0), .clk_ready(),
        .clk_lp_p(tx_clk_lp_p), .clk_lp_n(tx_clk_lp_n), .clk_hs_oe(tx_clk_hs_oe), .clk_run(),
        .tx_request_hs(4'b0), .tx_ready_hs(), .hs_sync(), .hs_trail(),
        .lp_p(tx_lp_p), .lp_n(tx_lp_n), .hs_oe(tx_hs_oe)
    );
    (* keep *) cmos_to_cml c2l_tx_mot0 (
        `ifdef USE_POWER_PINS
        .VDD(VDD), .VSS(VSS),
        `endif
        .POLN(pol_n_POLN), .A(1'b0), .OUTP(tx_mot_p[0]), .OUTN(tx_mot_n[0])
    );
    (* keep *) cmos_to_cml c2l_tx_mot1 (
        `ifdef USE_POWER_PINS
        .VDD(VDD), .VSS(VSS),
        `endif
        .POLN(pol_n_POLN), .A(1'b0), .OUTP(tx_mot_p[1]), .OUTN(tx_mot_n[1])
    );
    (* keep *) cmos_to_cml c2l_tx_mot2 (
        `ifdef USE_POWER_PINS
        .VDD(VDD), .VSS(VSS),
        `endif
        .POLN(pol_n_POLN), .A(1'b0), .OUTP(tx_mot_p[2]), .OUTN(tx_mot_n[2])
    );
    (* keep *) cmos_to_cml c2l_tx_mot3 (
        `ifdef USE_POWER_PINS
        .VDD(VDD), .VSS(VSS),
        `endif
        .POLN(pol_n_POLN), .A(1'b0), .OUTP(tx_mot_p[3]), .OUTN(tx_mot_n[3])
    );
    (* keep *) cmos_to_cml c2l_tx_clk_w (
        `ifdef USE_POWER_PINS
        .VDD(VDD), .VSS(VSS),
        `endif
        .POLN(pol_n_POLN), .A(1'b0), .OUTP(tx_clk_w_p), .OUTN(tx_clk_w_n)
    );
    (* keep *) sr16_tx sr16_tx0 (
        `ifdef USE_POWER_PINS
        .VDD(VDD), .VSS(VSS),
        `endif
        .POLN(pol_n_POLN), .CK_P(clkin_p_hs), .CK_N(clkin_n_hs), .CLK_W_P(tx_clk_w_p), .CLK_W_N(tx_clk_w_n),
        .MOT0_P(tx_mot_p[0]), .MOT0_N(tx_mot_n[0]), .MOT1_P(tx_mot_p[0]), .MOT1_N(tx_mot_n[0]), .MOT2_P(tx_mot_p[0]), .MOT2_N(tx_mot_n[0]), .MOT3_P(tx_mot_p[0]), .MOT3_N(tx_mot_n[0]), .MOT4_P(tx_mot_p[0]), .MOT4_N(tx_mot_n[0]), .MOT5_P(tx_mot_p[0]), .MOT5_N(tx_mot_n[0]), .MOT6_P(tx_mot_p[0]), .MOT6_N(tx_mot_n[0]), .MOT7_P(tx_mot_p[0]), .MOT7_N(tx_mot_n[0]),
        .DOUT_P(tx_dout_p[0]), .DOUT_N(tx_dout_n[0])
    );
    (* keep *) sr16_tx sr16_tx1 (
        `ifdef USE_POWER_PINS
        .VDD(VDD), .VSS(VSS),
        `endif
        .POLN(pol_n_POLN), .CK_P(clkin_p_hs), .CK_N(clkin_n_hs), .CLK_W_P(tx_clk_w_p), .CLK_W_N(tx_clk_w_n),
        .MOT0_P(tx_mot_p[1]), .MOT0_N(tx_mot_n[1]), .MOT1_P(tx_mot_p[1]), .MOT1_N(tx_mot_n[1]), .MOT2_P(tx_mot_p[1]), .MOT2_N(tx_mot_n[1]), .MOT3_P(tx_mot_p[1]), .MOT3_N(tx_mot_n[1]), .MOT4_P(tx_mot_p[1]), .MOT4_N(tx_mot_n[1]), .MOT5_P(tx_mot_p[1]), .MOT5_N(tx_mot_n[1]), .MOT6_P(tx_mot_p[1]), .MOT6_N(tx_mot_n[1]), .MOT7_P(tx_mot_p[1]), .MOT7_N(tx_mot_n[1]),
        .DOUT_P(tx_dout_p[1]), .DOUT_N(tx_dout_n[1])
    );
    (* keep *) sr16_tx sr16_tx2 (
        `ifdef USE_POWER_PINS
        .VDD(VDD), .VSS(VSS),
        `endif
        .POLN(pol_n_POLN), .CK_P(clkin_p_hs), .CK_N(clkin_n_hs), .CLK_W_P(tx_clk_w_p), .CLK_W_N(tx_clk_w_n),
        .MOT0_P(tx_mot_p[2]), .MOT0_N(tx_mot_n[2]), .MOT1_P(tx_mot_p[2]), .MOT1_N(tx_mot_n[2]), .MOT2_P(tx_mot_p[2]), .MOT2_N(tx_mot_n[2]), .MOT3_P(tx_mot_p[2]), .MOT3_N(tx_mot_n[2]), .MOT4_P(tx_mot_p[2]), .MOT4_N(tx_mot_n[2]), .MOT5_P(tx_mot_p[2]), .MOT5_N(tx_mot_n[2]), .MOT6_P(tx_mot_p[2]), .MOT6_N(tx_mot_n[2]), .MOT7_P(tx_mot_p[2]), .MOT7_N(tx_mot_n[2]),
        .DOUT_P(tx_dout_p[2]), .DOUT_N(tx_dout_n[2])
    );
    (* keep *) sr16_tx sr16_tx3 (
        `ifdef USE_POWER_PINS
        .VDD(VDD), .VSS(VSS),
        `endif
        .POLN(pol_n_POLN), .CK_P(clkin_p_hs), .CK_N(clkin_n_hs), .CLK_W_P(tx_clk_w_p), .CLK_W_N(tx_clk_w_n),
        .MOT0_P(tx_mot_p[3]), .MOT0_N(tx_mot_n[3]), .MOT1_P(tx_mot_p[3]), .MOT1_N(tx_mot_n[3]), .MOT2_P(tx_mot_p[3]), .MOT2_N(tx_mot_n[3]), .MOT3_P(tx_mot_p[3]), .MOT3_N(tx_mot_n[3]), .MOT4_P(tx_mot_p[3]), .MOT4_N(tx_mot_n[3]), .MOT5_P(tx_mot_p[3]), .MOT5_N(tx_mot_n[3]), .MOT6_P(tx_mot_p[3]), .MOT6_N(tx_mot_n[3]), .MOT7_P(tx_mot_p[3]), .MOT7_N(tx_mot_n[3]),
        .DOUT_P(tx_dout_p[3]), .DOUT_N(tx_dout_n[3])
    );
    (* keep *) hs_tx_pd pd_clk (.d(tx_ck), .oe(tx_clk_hs_oe), .lpp(tx_clk_lp_p), .lpn(tx_clk_lp_n),
        .hsp(tx_clk_hsp), .hsn(tx_clk_hsn), .lpinp(tx_clk_lpinp), .lpinn(tx_clk_lpinn));
    (* keep *) hs_tx_pd pd_d0 (.d(tx_dout[0]), .oe(tx_hs_oe[0]), .lpp(tx_lp_p[0]), .lpn(tx_lp_n[0]),
        .hsp(tx_d0_hsp), .hsn(tx_d0_hsn), .lpinp(tx_d0_lpinp), .lpinn(tx_d0_lpinn));
    (* keep *) hs_tx_pd pd_d1 (.d(tx_dout[1]), .oe(tx_hs_oe[1]), .lpp(tx_lp_p[1]), .lpn(tx_lp_n[1]),
        .hsp(tx_d1_hsp), .hsn(tx_d1_hsn), .lpinp(tx_d1_lpinp), .lpinn(tx_d1_lpinn));
    (* keep *) hs_tx_pd pd_d2 (.d(tx_dout[2]), .oe(tx_hs_oe[2]), .lpp(tx_lp_p[2]), .lpn(tx_lp_n[2]),
        .hsp(tx_d2_hsp), .hsn(tx_d2_hsn), .lpinp(tx_d2_lpinp), .lpinn(tx_d2_lpinn));
    (* keep *) hs_tx_pd pd_d3 (.d(tx_dout[3]), .oe(tx_hs_oe[3]), .lpp(tx_lp_p[3]), .lpn(tx_lp_n[3]),
        .hsp(tx_d3_hsp), .hsn(tx_d3_hsn), .lpinp(tx_d3_lpinp), .lpinn(tx_d3_lpinn));

endmodule
