module hs_tx_pd (d,
    hsn,
    hsp,
    lpinn,
    lpinp,
    lpn,
    lpp,
    oe);
 input d;
 output hsn;
 output hsp;
 output lpinn;
 output lpinp;
 input lpn;
 input lpp;
 input oe;

 wire db;
 wire db1;
 wire db2;
 wire dt;
 wire nn;
 wire np;
 wire oeb;

 sg13g2_decap_8 FILLER_0_0 ();
 sg13g2_decap_8 FILLER_0_14 ();
 sg13g2_decap_8 FILLER_0_21 ();
 sg13g2_decap_8 FILLER_0_28 ();
 sg13g2_decap_8 FILLER_0_35 ();
 sg13g2_decap_8 FILLER_0_42 ();
 sg13g2_decap_8 FILLER_0_49 ();
 sg13g2_decap_4 FILLER_0_56 ();
 sg13g2_decap_8 FILLER_0_7 ();
 sg13g2_decap_4 FILLER_1_0 ();
 sg13g2_decap_8 FILLER_1_24 ();
 sg13g2_decap_8 FILLER_1_31 ();
 sg13g2_fill_2 FILLER_1_38 ();
 sg13g2_fill_1 FILLER_1_59 ();
 sg13g2_decap_8 FILLER_2_0 ();
 sg13g2_fill_1 FILLER_2_11 ();
 sg13g2_decap_4 FILLER_2_18 ();
 sg13g2_decap_8 FILLER_2_41 ();
 sg13g2_decap_8 FILLER_2_48 ();
 sg13g2_decap_4 FILLER_2_55 ();
 sg13g2_fill_1 FILLER_2_59 ();
 sg13g2_decap_4 FILLER_2_7 ();
 sg13g2_decap_8 FILLER_3_0 ();
 sg13g2_decap_8 FILLER_3_14 ();
 sg13g2_decap_8 FILLER_3_21 ();
 sg13g2_decap_8 FILLER_3_28 ();
 sg13g2_decap_8 FILLER_3_35 ();
 sg13g2_decap_8 FILLER_3_42 ();
 sg13g2_decap_8 FILLER_3_49 ();
 sg13g2_decap_4 FILLER_3_56 ();
 sg13g2_decap_8 FILLER_3_7 ();
 sg13g2_decap_8 FILLER_4_0 ();
 sg13g2_decap_8 FILLER_4_12 ();
 sg13g2_decap_8 FILLER_4_19 ();
 sg13g2_decap_8 FILLER_4_26 ();
 sg13g2_decap_8 FILLER_4_33 ();
 sg13g2_decap_8 FILLER_4_40 ();
 sg13g2_decap_8 FILLER_4_47 ();
 sg13g2_decap_4 FILLER_4_54 ();
 sg13g2_fill_2 FILLER_4_58 ();
 sg13g2_fill_2 FILLER_4_7 ();
 sg13g2_decap_8 FILLER_5_0 ();
 sg13g2_decap_8 FILLER_5_13 ();
 sg13g2_decap_8 FILLER_5_20 ();
 sg13g2_decap_8 FILLER_5_27 ();
 sg13g2_decap_8 FILLER_5_34 ();
 sg13g2_decap_8 FILLER_5_41 ();
 sg13g2_decap_8 FILLER_5_48 ();
 sg13g2_decap_4 FILLER_5_55 ();
 sg13g2_fill_1 FILLER_5_59 ();
 sg13g2_decap_8 FILLER_6_0 ();
 sg13g2_decap_8 FILLER_6_13 ();
 sg13g2_decap_8 FILLER_6_20 ();
 sg13g2_decap_8 FILLER_6_27 ();
 sg13g2_decap_8 FILLER_6_34 ();
 sg13g2_decap_8 FILLER_6_41 ();
 sg13g2_decap_8 FILLER_6_48 ();
 sg13g2_decap_4 FILLER_6_55 ();
 sg13g2_fill_1 FILLER_6_59 ();
 sg13g2_decap_8 FILLER_7_0 ();
 sg13g2_decap_8 FILLER_7_14 ();
 sg13g2_decap_8 FILLER_7_21 ();
 sg13g2_decap_8 FILLER_7_28 ();
 sg13g2_decap_8 FILLER_7_35 ();
 sg13g2_decap_8 FILLER_7_42 ();
 sg13g2_decap_8 FILLER_7_49 ();
 sg13g2_decap_4 FILLER_7_56 ();
 sg13g2_decap_8 FILLER_7_7 ();
 sg13g2_inv_1 xdb (.Y(db),
    .A(db2));
 sg13g2_inv_1 xdb1 (.Y(db1),
    .A(d));
 sg13g2_inv_1 xdb2 (.Y(db2),
    .A(db1));
 sg13g2_buf_2 xdt (.A(d),
    .X(dt));
 sg13g2_nand2_2 xln (.Y(lpinn),
    .A(lpn),
    .B(oeb));
 sg13g2_nand2_2 xlp (.Y(lpinp),
    .A(lpp),
    .B(oeb));
 sg13g2_nand2_2 xnn (.Y(nn),
    .A(dt),
    .B(oe));
 sg13g2_nand2_2 xnp (.Y(np),
    .A(db),
    .B(oe));
 sg13g2_inv_1 xoeb (.Y(oeb),
    .A(oe));
 sg13g2_inv_16 xon (.A(nn),
    .Y(hsn));
 sg13g2_inv_16 xop (.A(np),
    .Y(hsp));
endmodule
