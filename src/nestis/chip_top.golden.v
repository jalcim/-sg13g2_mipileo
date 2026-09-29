`timescale 1ns/10ps

`begin_keywords "1364-2005"

module chip_top (
    input IOVDD,
    input IOVSS,
    input VDD,
    input VSS,
    input sig_in_pad_PAD,
    output sig_out_pad_PAD,
    input open_pad_PAD
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

    sg13g2_IOPadIOVdd iovdd_pad (.iovdd(IOVDD), .iovss(IOVSS), .vdd(VDD), .vss(VSS));
    sg13g2_IOPadIOVss iovss_pad (.iovdd(IOVDD), .iovss(IOVSS), .vdd(VDD), .vss(VSS));
    sg13g2_IOPadVdd vdd_pad (.iovdd(IOVDD), .iovss(IOVSS), .vdd(VDD), .vss(VSS));
    sg13g2_IOPadVss vss_pad (.iovdd(IOVDD), .iovss(IOVSS), .vdd(VDD), .vss(VSS));
    sg13g2_IOPadVdd vdd_pad_1 (.iovdd(IOVDD), .iovss(IOVSS), .vdd(VDD), .vss(VSS));
    sg13g2_IOPadAnalog sig_in_pad (.iovdd(IOVDD), .iovss(IOVSS), .vdd(VDD), .vss(VSS), .pad(sig_in_pad_PAD), .padres(padres_sig_in_pad_nc), .padbare(sig_in_pad_PAD));
    sg13g2_IOPadAnalog sig_out_pad (.iovdd(IOVDD), .iovss(IOVSS), .vdd(VDD), .vss(VSS), .pad(sig_out_pad_PAD), .padres(padres_sig_out_pad_nc), .padbare(sig_out_pad_PAD));
    sg13g2_IOPadAnalog flow_in_pad (.iovdd(IOVDD), .iovss(IOVSS), .vdd(VDD), .vss(VSS), .padres(padres_flow_in_pad_nc), .padbare(flow_in_c));
    sg13g2_IOPadAnalog flow_out_pad (.iovdd(IOVDD), .iovss(IOVSS), .vdd(VDD), .vss(VSS), .padres(padres_flow_out_pad_nc), .padbare(flow_out_c));
    sg13g2_IOPadAnalog thru_n_pad (.iovdd(IOVDD), .iovss(IOVSS), .vdd(VDD), .vss(VSS), .padres(padres_thru_n_pad_nc), .padbare(thru_c));
    sg13g2_IOPadAnalog thru_s_pad (.iovdd(IOVDD), .iovss(IOVSS), .vdd(VDD), .vss(VSS), .padres(padres_thru_s_pad_nc), .padbare(thru_c));
    sg13g2_IOPadAnalog open_pad (.iovdd(IOVDD), .iovss(IOVSS), .vdd(VDD), .vss(VSS), .pad(open_pad_PAD), .padres(padres_open_pad_nc), .padbare(open_pad_PAD));
    remplissage_gatpoly remplissage_so ();
    remplissage_gatpoly remplissage_no ();
    remplissage_gatpoly remplissage_se ();
    remplissage_gatpoly remplissage_ne ();
    suiveur_npn suiveur (.VCC(VDD), .VSS(VSS), .IN(sig_in_pad_PAD), .OUT(sig_out_pad_PAD));
    suiveur_npn suiveur_flow (.VCC(VDD), .VSS(VSS), .IN(flow_in_c), .OUT(flow_out_c));

endmodule
`end_keywords
