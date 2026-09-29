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
    wire padres_sig_in_pad_nc;
    wire padres_sig_out_pad_nc;
    wire padres_flow_in_pad_nc;
    wire padres_flow_out_pad_nc;
    wire padres_thru_n_pad_nc;
    wire padres_thru_s_pad_nc;
    wire padres_open_pad_nc;

    (* keep *) sg13g2_IOPadIOVdd iovdd_pad (
        `ifdef USE_POWER_PINS
        .iovdd(IOVDD), .iovss(IOVSS), .vdd(VDD), .vss(VSS)
        `endif
    );
    (* keep *) sg13g2_IOPadIOVss iovss_pad (
        `ifdef USE_POWER_PINS
        .iovdd(IOVDD), .iovss(IOVSS), .vdd(VDD), .vss(VSS)
        `endif
    );
    (* keep *) sg13g2_IOPadVdd vdd_pad (
        `ifdef USE_POWER_PINS
        .iovdd(IOVDD), .iovss(IOVSS), .vdd(VDD), .vss(VSS)
        `endif
    );
    (* keep *) sg13g2_IOPadVss vss_pad (
        `ifdef USE_POWER_PINS
        .iovdd(IOVDD), .iovss(IOVSS), .vdd(VDD), .vss(VSS)
        `endif
    );
    (* keep *) sg13g2_IOPadVdd vdd_pad_1 (
        `ifdef USE_POWER_PINS
        .iovdd(IOVDD), .iovss(IOVSS), .vdd(VDD), .vss(VSS)
        `endif
    );
    (* keep *) sg13g2_IOPadAnalog sig_in_pad (
        `ifdef USE_POWER_PINS
        .iovdd(IOVDD), .iovss(IOVSS), .vdd(VDD), .vss(VSS),
        `endif
        .pad(sig_in_pad_PAD), .padres(padres_sig_in_pad_nc), .padbare(sig_in_pad_PAD)
    );
    (* keep *) sg13g2_IOPadAnalog sig_out_pad (
        `ifdef USE_POWER_PINS
        .iovdd(IOVDD), .iovss(IOVSS), .vdd(VDD), .vss(VSS),
        `endif
        .pad(sig_out_pad_PAD), .padres(padres_sig_out_pad_nc), .padbare(sig_out_pad_PAD)
    );
    (* keep *) sg13g2_IOPadAnalog flow_in_pad (
        `ifdef USE_POWER_PINS
        .iovdd(IOVDD), .iovss(IOVSS), .vdd(VDD), .vss(VSS),
        `endif
        .padres(padres_flow_in_pad_nc), .padbare(flow_in_c)
    );
    (* keep *) sg13g2_IOPadAnalog flow_out_pad (
        `ifdef USE_POWER_PINS
        .iovdd(IOVDD), .iovss(IOVSS), .vdd(VDD), .vss(VSS),
        `endif
        .padres(padres_flow_out_pad_nc), .padbare(flow_out_c)
    );
    (* keep *) sg13g2_IOPadAnalog thru_n_pad (
        `ifdef USE_POWER_PINS
        .iovdd(IOVDD), .iovss(IOVSS), .vdd(VDD), .vss(VSS),
        `endif
        .padres(padres_thru_n_pad_nc), .padbare(thru_c)
    );
    (* keep *) sg13g2_IOPadAnalog thru_s_pad (
        `ifdef USE_POWER_PINS
        .iovdd(IOVDD), .iovss(IOVSS), .vdd(VDD), .vss(VSS),
        `endif
        .padres(padres_thru_s_pad_nc), .padbare(thru_c)
    );
    (* keep *) sg13g2_IOPadAnalog open_pad (
        `ifdef USE_POWER_PINS
        .iovdd(IOVDD), .iovss(IOVSS), .vdd(VDD), .vss(VSS),
        `endif
        .pad(open_pad_PAD), .padres(padres_open_pad_nc), .padbare(open_pad_PAD)
    );
    //remplissage_gatpoly remplissage_so ();
    //remplissage_gatpoly remplissage_no ();
    //remplissage_gatpoly remplissage_se ();
    //remplissage_gatpoly remplissage_ne ();
    //suiveur_npn suiveur (.VCC(VDD), .VSS(VSS), .IN(sig_in_pad_PAD), .OUT(sig_out_pad_PAD));
    //suiveur_npn suiveur_flow (.VCC(VDD), .VSS(VSS), .IN(flow_in_c), .OUT(flow_out_c));

endmodule
