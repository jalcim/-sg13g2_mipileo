module hs_tx_pd (d,
    hsn,
    hsp,
    lpinn,
    lpinp,
    lpn,
    lpp,
    oe,
    VPWR,
    VGND);
 input d;
 output hsn;
 output hsp;
 output lpinn;
 output lpinp;
 input lpn;
 input lpp;
 input oe;
 inout VPWR;
 inout VGND;

 wire db;
 wire db1;
 wire db2;
 wire dt;
 wire nn;
 wire np;
 wire oeb;

 sg13g2_decap_8 FILLER_0_0 (.VDD(VPWR),
    .VSS(VGND));
 sg13g2_decap_8 FILLER_0_14 (.VDD(VPWR),
    .VSS(VGND));
 sg13g2_decap_8 FILLER_0_21 (.VDD(VPWR),
    .VSS(VGND));
 sg13g2_decap_8 FILLER_0_28 (.VDD(VPWR),
    .VSS(VGND));
 sg13g2_decap_8 FILLER_0_35 (.VDD(VPWR),
    .VSS(VGND));
 sg13g2_decap_8 FILLER_0_42 (.VDD(VPWR),
    .VSS(VGND));
 sg13g2_decap_8 FILLER_0_49 (.VDD(VPWR),
    .VSS(VGND));
 sg13g2_decap_4 FILLER_0_56 (.VDD(VPWR),
    .VSS(VGND));
 sg13g2_decap_8 FILLER_0_7 (.VDD(VPWR),
    .VSS(VGND));
 sg13g2_decap_4 FILLER_1_0 (.VDD(VPWR),
    .VSS(VGND));
 sg13g2_decap_8 FILLER_1_24 (.VDD(VPWR),
    .VSS(VGND));
 sg13g2_decap_8 FILLER_1_31 (.VDD(VPWR),
    .VSS(VGND));
 sg13g2_fill_2 FILLER_1_38 (.VDD(VPWR),
    .VSS(VGND));
 sg13g2_fill_1 FILLER_1_59 (.VDD(VPWR),
    .VSS(VGND));
 sg13g2_decap_8 FILLER_2_0 (.VDD(VPWR),
    .VSS(VGND));
 sg13g2_fill_1 FILLER_2_11 (.VDD(VPWR),
    .VSS(VGND));
 sg13g2_decap_4 FILLER_2_18 (.VDD(VPWR),
    .VSS(VGND));
 sg13g2_decap_8 FILLER_2_41 (.VDD(VPWR),
    .VSS(VGND));
 sg13g2_decap_8 FILLER_2_48 (.VDD(VPWR),
    .VSS(VGND));
 sg13g2_decap_4 FILLER_2_55 (.VDD(VPWR),
    .VSS(VGND));
 sg13g2_fill_1 FILLER_2_59 (.VDD(VPWR),
    .VSS(VGND));
 sg13g2_decap_4 FILLER_2_7 (.VDD(VPWR),
    .VSS(VGND));
 sg13g2_decap_8 FILLER_3_0 (.VDD(VPWR),
    .VSS(VGND));
 sg13g2_decap_8 FILLER_3_14 (.VDD(VPWR),
    .VSS(VGND));
 sg13g2_decap_8 FILLER_3_21 (.VDD(VPWR),
    .VSS(VGND));
 sg13g2_decap_8 FILLER_3_28 (.VDD(VPWR),
    .VSS(VGND));
 sg13g2_decap_8 FILLER_3_35 (.VDD(VPWR),
    .VSS(VGND));
 sg13g2_decap_8 FILLER_3_42 (.VDD(VPWR),
    .VSS(VGND));
 sg13g2_decap_8 FILLER_3_49 (.VDD(VPWR),
    .VSS(VGND));
 sg13g2_decap_4 FILLER_3_56 (.VDD(VPWR),
    .VSS(VGND));
 sg13g2_decap_8 FILLER_3_7 (.VDD(VPWR),
    .VSS(VGND));
 sg13g2_decap_8 FILLER_4_0 (.VDD(VPWR),
    .VSS(VGND));
 sg13g2_decap_8 FILLER_4_12 (.VDD(VPWR),
    .VSS(VGND));
 sg13g2_decap_8 FILLER_4_19 (.VDD(VPWR),
    .VSS(VGND));
 sg13g2_decap_8 FILLER_4_26 (.VDD(VPWR),
    .VSS(VGND));
 sg13g2_decap_8 FILLER_4_33 (.VDD(VPWR),
    .VSS(VGND));
 sg13g2_decap_8 FILLER_4_40 (.VDD(VPWR),
    .VSS(VGND));
 sg13g2_decap_8 FILLER_4_47 (.VDD(VPWR),
    .VSS(VGND));
 sg13g2_decap_4 FILLER_4_54 (.VDD(VPWR),
    .VSS(VGND));
 sg13g2_fill_2 FILLER_4_58 (.VDD(VPWR),
    .VSS(VGND));
 sg13g2_fill_2 FILLER_4_7 (.VDD(VPWR),
    .VSS(VGND));
 sg13g2_decap_8 FILLER_5_0 (.VDD(VPWR),
    .VSS(VGND));
 sg13g2_decap_8 FILLER_5_13 (.VDD(VPWR),
    .VSS(VGND));
 sg13g2_decap_8 FILLER_5_20 (.VDD(VPWR),
    .VSS(VGND));
 sg13g2_decap_8 FILLER_5_27 (.VDD(VPWR),
    .VSS(VGND));
 sg13g2_decap_8 FILLER_5_34 (.VDD(VPWR),
    .VSS(VGND));
 sg13g2_decap_8 FILLER_5_41 (.VDD(VPWR),
    .VSS(VGND));
 sg13g2_decap_8 FILLER_5_48 (.VDD(VPWR),
    .VSS(VGND));
 sg13g2_decap_4 FILLER_5_55 (.VDD(VPWR),
    .VSS(VGND));
 sg13g2_fill_1 FILLER_5_59 (.VDD(VPWR),
    .VSS(VGND));
 sg13g2_decap_8 FILLER_6_0 (.VDD(VPWR),
    .VSS(VGND));
 sg13g2_decap_8 FILLER_6_13 (.VDD(VPWR),
    .VSS(VGND));
 sg13g2_decap_8 FILLER_6_20 (.VDD(VPWR),
    .VSS(VGND));
 sg13g2_decap_8 FILLER_6_27 (.VDD(VPWR),
    .VSS(VGND));
 sg13g2_decap_8 FILLER_6_34 (.VDD(VPWR),
    .VSS(VGND));
 sg13g2_decap_8 FILLER_6_41 (.VDD(VPWR),
    .VSS(VGND));
 sg13g2_decap_8 FILLER_6_48 (.VDD(VPWR),
    .VSS(VGND));
 sg13g2_decap_4 FILLER_6_55 (.VDD(VPWR),
    .VSS(VGND));
 sg13g2_fill_1 FILLER_6_59 (.VDD(VPWR),
    .VSS(VGND));
 sg13g2_decap_8 FILLER_7_0 (.VDD(VPWR),
    .VSS(VGND));
 sg13g2_decap_8 FILLER_7_14 (.VDD(VPWR),
    .VSS(VGND));
 sg13g2_decap_8 FILLER_7_21 (.VDD(VPWR),
    .VSS(VGND));
 sg13g2_decap_8 FILLER_7_28 (.VDD(VPWR),
    .VSS(VGND));
 sg13g2_decap_8 FILLER_7_35 (.VDD(VPWR),
    .VSS(VGND));
 sg13g2_decap_8 FILLER_7_42 (.VDD(VPWR),
    .VSS(VGND));
 sg13g2_decap_8 FILLER_7_49 (.VDD(VPWR),
    .VSS(VGND));
 sg13g2_decap_4 FILLER_7_56 (.VDD(VPWR),
    .VSS(VGND));
 sg13g2_decap_8 FILLER_7_7 (.VDD(VPWR),
    .VSS(VGND));
 sg13g2_inv_1 xdb (.VDD(VPWR),
    .Y(db),
    .A(db2),
    .VSS(VGND));
 sg13g2_inv_1 xdb1 (.VDD(VPWR),
    .Y(db1),
    .A(d),
    .VSS(VGND));
 sg13g2_inv_1 xdb2 (.VDD(VPWR),
    .Y(db2),
    .A(db1),
    .VSS(VGND));
 sg13g2_buf_2 xdt (.A(d),
    .X(dt),
    .VDD(VPWR),
    .VSS(VGND));
 sg13g2_nand2_2 xln (.Y(lpinn),
    .A(lpn),
    .B(oeb),
    .VDD(VPWR),
    .VSS(VGND));
 sg13g2_nand2_2 xlp (.Y(lpinp),
    .A(lpp),
    .B(oeb),
    .VDD(VPWR),
    .VSS(VGND));
 sg13g2_nand2_2 xnn (.Y(nn),
    .A(dt),
    .B(oe),
    .VDD(VPWR),
    .VSS(VGND));
 sg13g2_nand2_2 xnp (.Y(np),
    .A(db),
    .B(oe),
    .VDD(VPWR),
    .VSS(VGND));
 sg13g2_inv_1 xoeb (.VDD(VPWR),
    .Y(oeb),
    .A(oe),
    .VSS(VGND));
 sg13g2_inv_16 xon (.A(nn),
    .Y(hsn),
    .VDD(VPWR),
    .VSS(VGND));
 sg13g2_inv_16 xop (.A(np),
    .Y(hsp),
    .VDD(VPWR),
    .VSS(VGND));
endmodule
