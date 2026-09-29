module chip_top (
    inout IOVDD,
    inout IOVSS,
    inout VDD,
    inout VSS,
    inout sig_in_pad_PAD,
    inout sig_out_pad_PAD,
    inout open_pad_PAD
);
    wire flow_in_c;
    wire flow_out_c;
    wire thru_c;
    wire PADRES_sig_in_pad_nc;
    wire PADRES_sig_out_pad_nc;
    wire PADRES_flow_in_pad_nc;
    wire PADRES_flow_out_pad_nc;
    wire PADRES_thru_n_pad_nc;
    wire PADRES_thru_s_pad_nc;
    wire PADRES_open_pad_nc;

    (* keep *) MIPI_CornerStop corner_ne (
        `ifdef USE_POWER_PINS
        .IOVDD_A(IOVDD), .IOVSS_A(IOVSS), .IOVDD_B(IOVDD), .IOVSS_B(IOVSS), .VDD(VDD), .VSS(VSS)
        `endif
    );
    
    (* keep *) MIPI_Corner corner_nw (
        `ifdef USE_POWER_PINS
        .IOVDD(IOVDD), .IOVSS(IOVSS), .VDD(VDD), .VSS(VSS)
        `endif
    );
    
    (* keep *) MIPI_Corner corner_se (
        `ifdef USE_POWER_PINS
        .IOVDD(IOVDD), .IOVSS(IOVSS), .VDD(VDD), .VSS(VSS)
        `endif
    );
    
    (* keep *) MIPI_Corner corner_sw (
        `ifdef USE_POWER_PINS
        .IOVDD(IOVDD), .IOVSS(IOVSS), .VDD(VDD), .VSS(VSS)
        `endif
    );
    


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
    (* keep *) MIPI_IOPadVdd vdd_pad (
        `ifdef USE_POWER_PINS
        .IOVDD(IOVDD), .IOVSS(IOVSS), .VDD(VDD), .VSS(VSS)
        `endif
    );
    (* keep *) MIPI_IOPadVss vss_pad (
        `ifdef USE_POWER_PINS
        .IOVDD(IOVDD), .IOVSS(IOVSS), .VDD(VDD), .VSS(VSS)
        `endif
    );
    (* keep *) MIPI_IOPadVdd vdd_pad_1 (
        `ifdef USE_POWER_PINS
        .IOVDD(IOVDD), .IOVSS(IOVSS), .VDD(VDD), .VSS(VSS)
        `endif
    );
    (* keep *) MIPI_IOPadAnalog sig_in_pad (
        `ifdef USE_POWER_PINS
        .IOVDD(IOVDD), .IOVSS(IOVSS), .VDD(VDD), .VSS(VSS),
        `endif
        .PAD(sig_in_pad_PAD), .PADRES(sig_in_pad_PAD)
    );
    (* keep *) MIPI_IOPadAnalog sig_out_pad (
        `ifdef USE_POWER_PINS
        .IOVDD(IOVDD), .IOVSS(IOVSS), .VDD(VDD), .VSS(VSS),
        `endif
        .PAD(sig_out_pad_PAD), .PADRES(sig_out_pad_PAD)
    );
    (* keep *) MIPI_IOPadAnalog flow_in_pad (
        `ifdef USE_POWER_PINS
        .IOVDD(IOVDD), .IOVSS(IOVSS), .VDD(VDD), .VSS(VSS),
        `endif
        .PADRES(flow_in_c)
    );
    (* keep *) MIPI_IOPadAnalog flow_out_pad (
        `ifdef USE_POWER_PINS
        .IOVDD(IOVDD), .IOVSS(IOVSS), .VDD(VDD), .VSS(VSS),
        `endif
        .PADRES(flow_out_c)
    );
    (* keep *) MIPI_IOPadAnalog thru_n_pad (
        `ifdef USE_POWER_PINS
        .IOVDD(IOVDD), .IOVSS(IOVSS), .VDD(VDD), .VSS(VSS),
        `endif
        .PADRES(thru_c)
    );
    (* keep *) MIPI_IOPadAnalog thru_s_pad (
        `ifdef USE_POWER_PINS
        .IOVDD(IOVDD), .IOVSS(IOVSS), .VDD(VDD), .VSS(VSS),
        `endif
        .PADRES(thru_c)
    );
    (* keep *) MIPI_IOPadAnalog open_pad (
        `ifdef USE_POWER_PINS
        .IOVDD(IOVDD), .IOVSS(IOVSS), .VDD(VDD), .VSS(VSS),
        `endif
        .PAD(open_pad_PAD), .PADRES(PADRES_open_pad_nc)
    );
    //remplissage_gatpoly remplissage_so ();
    //remplissage_gatpoly remplissage_no ();
    //remplissage_gatpoly remplissage_se ();
    //remplissage_gatpoly remplissage_ne ();
    //suiveur_npn suiveur (.VCC(VDD), .VSS(VSS), .IN(sig_in_pad_PAD), .OUT(sig_out_pad_PAD));
    //suiveur_npn suiveur_flow (.VCC(VDD), .VSS(VSS), .IN(flow_in_c), .OUT(flow_out_c));

endmodule
