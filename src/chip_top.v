module chip_top (
    inout IOVDD,
    inout IOVSS,
    
    inout IOVDD_MIPI,
    inout IOVSS_MIPI,
    
    inout VDD,
    inout VSS,

    inout RX_ANALOG_PAD,
    inout RX_CLK_LANE_P_PAD,
    inout RX_CLK_LANE_N_PAD,
    inout RX_1_LANE_P_PAD,
    inout RX_1_LANE_N_PAD,
    inout RX_2_LANE_P_PAD,
    inout RX_2_LANE_N_PAD,
    inout RX_3_LANE_P_PAD,
    inout RX_3_LANE_N_PAD,
    inout RX_4_LANE_P_PAD,
    inout RX_4_LANE_N_PAD,

    inout TX_ANALOG_PAD,
    inout TX_CLK_LANE_P_PAD,
    inout TX_CLK_LANE_N_PAD,
    inout TX_1_LANE_P_PAD,
    inout TX_1_LANE_N_PAD,
    inout TX_2_LANE_P_PAD,
    inout TX_2_LANE_N_PAD,
    inout TX_3_LANE_P_PAD,
    inout TX_3_LANE_N_PAD,
    inout TX_4_LANE_P_PAD,
    inout TX_4_LANE_N_PAD,
    inout CLKIN_N_PAD,
    inout CLKIN_P_PAD
    
);

    wire analog_routing;

    // Corners

    (* keep *) MIPI_Corner corner_ne (
        `ifdef USE_POWER_PINS
        .IOVDD(IOVDD_MIPI), .IOVSS(IOVSS_MIPI), .VDD(VDD), .VSS(VSS)
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
    (* keep *) MIPI_Corner corner_sw (
        `ifdef USE_POWER_PINS
        .IOVDD(IOVDD), .IOVSS(IOVSS), .VDD(VDD), .VSS(VSS)
        `endif
    );

    // East Side

    (* keep *) MIPI_IOPadIOVdd iovdd_mipi_pad (
        `ifdef USE_POWER_PINS
        .IOVDD(IOVDD_MIPI), .IOVSS(IOVSS_MIPI), .VDD(VDD), .VSS(VSS)
        `endif
    );
    (* keep *) MIPI_IOPadIOVss iovss_mipi_pad (
        `ifdef USE_POWER_PINS
        .IOVDD(IOVDD_MIPI), .IOVSS(IOVSS_MIPI), .VDD(VDD), .VSS(VSS)
        `endif
    );
    (* keep *) MIPI_IOPadAnalog rx_analog_pad (
        `ifdef USE_POWER_PINS
        .IOVDD(IOVDD_MIPI), .IOVSS(IOVSS_MIPI), .VDD(VDD), .VSS(VSS),
        `endif
        .PAD(RX_ANALOG_PAD), .PADRES(analog_routing)
    );
    (* keep *) MIPI_IOPadAnalog rx_clk_lane_p_pad (
        `ifdef USE_POWER_PINS
        .IOVDD(IOVDD_MIPI), .IOVSS(IOVSS_MIPI), .VDD(VDD), .VSS(VSS),
        `endif
        .PAD(RX_CLK_LANE_P_PAD), .PADRES(analog_routing)
    );
    (* keep *) MIPI_IOPadAnalog rx_clk_lane_n_pad (
        `ifdef USE_POWER_PINS
        .IOVDD(IOVDD_MIPI), .IOVSS(IOVSS_MIPI), .VDD(VDD), .VSS(VSS),
        `endif
        .PAD(RX_CLK_LANE_N_PAD), .PADRES(analog_routing)
    );
    (* keep *) MIPI_IOPadAnalog rx_1_lane_p_pad (
        `ifdef USE_POWER_PINS
        .IOVDD(IOVDD_MIPI), .IOVSS(IOVSS_MIPI), .VDD(VDD), .VSS(VSS),
        `endif
        .PAD(RX_1_LANE_P_PAD), .PADRES(analog_routing)
    );
    (* keep *) MIPI_IOPadAnalog rx_1_lane_n_pad (
        `ifdef USE_POWER_PINS
        .IOVDD(IOVDD_MIPI), .IOVSS(IOVSS_MIPI), .VDD(VDD), .VSS(VSS),
        `endif
        .PAD(RX_1_LANE_N_PAD), .PADRES(analog_routing)
    );
    (* keep *) MIPI_IOPadAnalog rx_2_lane_p_pad (
        `ifdef USE_POWER_PINS
        .IOVDD(IOVDD_MIPI), .IOVSS(IOVSS_MIPI), .VDD(VDD), .VSS(VSS),
        `endif
        .PAD(RX_2_LANE_P_PAD), .PADRES(analog_routing)
    );
    (* keep *) MIPI_IOPadAnalog rx_2_lane_n_pad (
        `ifdef USE_POWER_PINS
        .IOVDD(IOVDD_MIPI), .IOVSS(IOVSS_MIPI), .VDD(VDD), .VSS(VSS),
        `endif
        .PAD(RX_2_LANE_N_PAD), .PADRES(analog_routing)
    );
    (* keep *) MIPI_IOPadAnalog rx_3_lane_p_pad (
        `ifdef USE_POWER_PINS
        .IOVDD(IOVDD_MIPI), .IOVSS(IOVSS_MIPI), .VDD(VDD), .VSS(VSS),
        `endif
        .PAD(RX_3_LANE_P_PAD), .PADRES(analog_routing)
    );
    (* keep *) MIPI_IOPadAnalog rx_3_lane_n_pad (
        `ifdef USE_POWER_PINS
        .IOVDD(IOVDD_MIPI), .IOVSS(IOVSS_MIPI), .VDD(VDD), .VSS(VSS),
        `endif
        .PAD(RX_3_LANE_N_PAD), .PADRES(analog_routing)
    );
    (* keep *) MIPI_IOPadAnalog rx_4_lane_p_pad (
        `ifdef USE_POWER_PINS
        .IOVDD(IOVDD_MIPI), .IOVSS(IOVSS_MIPI), .VDD(VDD), .VSS(VSS),
        `endif
        .PAD(RX_4_LANE_P_PAD), .PADRES(analog_routing)
    );
    (* keep *) MIPI_IOPadAnalog rx_4_lane_n_pad (
        `ifdef USE_POWER_PINS
        .IOVDD(IOVDD_MIPI), .IOVSS(IOVSS_MIPI), .VDD(VDD), .VSS(VSS),
        `endif
        .PAD(RX_4_LANE_N_PAD), .PADRES(analog_routing)
    );

    // North Side

    (* keep *) MIPI_IOPadVdd vdd_pad (
        `ifdef USE_POWER_PINS
        .IOVDD(IOVDD_MIPI), .IOVSS(IOVSS_MIPI), .VDD(VDD), .VSS(VSS)
        `endif
    );
    (* keep *) MIPI_IOPadVss vss_pad (
        `ifdef USE_POWER_PINS
        .IOVDD(IOVDD_MIPI), .IOVSS(IOVSS_MIPI), .VDD(VDD), .VSS(VSS)
        `endif
    );
    (* keep *) MIPI_IOPadAnalog tx_analog_pad (
        `ifdef USE_POWER_PINS
        .IOVDD(IOVDD_MIPI), .IOVSS(IOVSS_MIPI), .VDD(VDD), .VSS(VSS),
        `endif
        .PAD(TX_ANALOG_PAD), .PADRES()
    );
    (* keep *) MIPI_IOPadAnalog tx_clk_lane_p_pad (
        `ifdef USE_POWER_PINS
        .IOVDD(IOVDD_MIPI), .IOVSS(IOVSS_MIPI), .VDD(VDD), .VSS(VSS),
        `endif
        .PAD(TX_CLK_LANE_P_PAD), .PADRES(analog_routing)
    );
    (* keep *) MIPI_IOPadAnalog tx_clk_lane_n_pad (
        `ifdef USE_POWER_PINS
        .IOVDD(IOVDD_MIPI), .IOVSS(IOVSS_MIPI), .VDD(VDD), .VSS(VSS),
        `endif
        .PAD(TX_CLK_LANE_N_PAD), .PADRES(analog_routing)
    );
    (* keep *) MIPI_IOPadAnalog tx_1_lane_p_pad (
        `ifdef USE_POWER_PINS
        .IOVDD(IOVDD_MIPI), .IOVSS(IOVSS_MIPI), .VDD(VDD), .VSS(VSS),
        `endif
        .PAD(TX_1_LANE_P_PAD), .PADRES(analog_routing)
    );
    (* keep *) MIPI_IOPadAnalog tx_1_lane_n_pad (
        `ifdef USE_POWER_PINS
        .IOVDD(IOVDD_MIPI), .IOVSS(IOVSS_MIPI), .VDD(VDD), .VSS(VSS),
        `endif
        .PAD(TX_1_LANE_N_PAD), .PADRES(analog_routing)
    );
    (* keep *) MIPI_IOPadAnalog tx_2_lane_p_pad (
        `ifdef USE_POWER_PINS
        .IOVDD(IOVDD_MIPI), .IOVSS(IOVSS_MIPI), .VDD(VDD), .VSS(VSS),
        `endif
        .PAD(TX_2_LANE_P_PAD), .PADRES(analog_routing)
    );
    (* keep *) MIPI_IOPadAnalog tx_2_lane_n_pad (
        `ifdef USE_POWER_PINS
        .IOVDD(IOVDD_MIPI), .IOVSS(IOVSS_MIPI), .VDD(VDD), .VSS(VSS),
        `endif
        .PAD(TX_2_LANE_N_PAD), .PADRES(analog_routing)
    );
    (* keep *) MIPI_IOPadAnalog tx_3_lane_p_pad (
        `ifdef USE_POWER_PINS
        .IOVDD(IOVDD_MIPI), .IOVSS(IOVSS_MIPI), .VDD(VDD), .VSS(VSS),
        `endif
        .PAD(TX_3_LANE_P_PAD), .PADRES(analog_routing)
    );
    (* keep *) MIPI_IOPadAnalog tx_3_lane_n_pad (
        `ifdef USE_POWER_PINS
        .IOVDD(IOVDD_MIPI), .IOVSS(IOVSS_MIPI), .VDD(VDD), .VSS(VSS),
        `endif
        .PAD(TX_3_LANE_N_PAD), .PADRES(analog_routing)
    );
    (* keep *) MIPI_IOPadAnalog tx_4_lane_p_pad (
        `ifdef USE_POWER_PINS
        .IOVDD(IOVDD_MIPI), .IOVSS(IOVSS_MIPI), .VDD(VDD), .VSS(VSS),
        `endif
        .PAD(TX_4_LANE_P_PAD), .PADRES(analog_routing)
    );
    (* keep *) MIPI_IOPadAnalog tx_4_lane_n_pad (
        `ifdef USE_POWER_PINS
        .IOVDD(IOVDD_MIPI), .IOVSS(IOVSS_MIPI), .VDD(VDD), .VSS(VSS),
        `endif
        .PAD(TX_4_LANE_N_PAD), .PADRES(analog_routing)
    );
    (* keep *) MIPI_IOPadAnalog clkin_n_pad (
        `ifdef USE_POWER_PINS
        .IOVDD(IOVDD_MIPI), .IOVSS(IOVSS_MIPI), .VDD(VDD), .VSS(VSS),
        `endif
        .PAD(CLKIN_N_PAD), .PADRES(analog_routing)
    );
    (* keep *) MIPI_IOPadAnalog clkin_p_pad (
        `ifdef USE_POWER_PINS
        .IOVDD(IOVDD_MIPI), .IOVSS(IOVSS_MIPI), .VDD(VDD), .VSS(VSS),
        `endif
        .PAD(CLKIN_P_PAD), .PADRES(analog_routing)
    );
  
    // West Side

    (* keep *) MIPI_IOPadIOVdd iovdd_pad (
        `ifdef USE_POWER_PINS
        .IOVDD(IOVDD), .IOVSS(IOVSS), .VDD(VDD), .VSS(VSS)
        `endif
    );
    (* keep *) MIPI_IOPadIOVss iovss_pad (
        `ifdef USE_POWER_PINS
        .IOVDD(IOVDD), .IOVSS(IOVSS), .VDD(VDD), .VSS(VSS)
        `endif
    );
  
    // South Side
  

  
  
    //remplissage_gatpoly remplissage_so ();
    //remplissage_gatpoly remplissage_no ();
    //remplissage_gatpoly remplissage_se ();
    //remplissage_gatpoly remplissage_ne ();
    //suiveur_npn suiveur (.VCC(VDD), .VSS(VSS), .IN(sig_in_pad_PAD), .OUT(sig_out_pad_PAD));
    //suiveur_npn suiveur_flow (.VCC(VDD), .VSS(VSS), .IN(flow_in_c), .OUT(flow_out_c));

endmodule
