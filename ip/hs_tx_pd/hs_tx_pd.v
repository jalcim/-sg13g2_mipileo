// HS_TX_PD : pre-driver d une paire HS-TX (plots MIPI_IOPadTX P et N), cellules standard sg13g2 (29/09/2026).
// Meme netlist que hs_tx_pd.sp (la netlist simulee). A instancier par lane (et pour la lane horloge) dans le top,
// PLACE AU PLUS PRES des deux plots TX : chaque sortie HS charge ~0,4 pF de grille (derivation 162,7 um / 0,13 um).
//   hsp -> IN_HS du plot P, hsn -> IN_HS du plot N, lpinp -> LP_IN du plot P, lpinn -> LP_IN du plot N
//   oe = 0 : hsp = hsn = 0 (derivations bloquees), LP_IN = /lp -> le plot suit lp_p / lp_n
//   oe = 1 : hsp = /d, hsn = d (le plot P suit d), LP_IN = 1 -> sortie LP du plot a 0 (LP-00 sous le HS)
// Les cellules ne doivent pas etre retouchees par la synthese (dont_touch) : chemins P / N equilibres a la main.
module hs_tx_pd (
    input  wire d,      // dout (donnee HS serie)
    input  wire oe,     // hs_oe
    input  wire lpp,    // lp_p
    input  wire lpn,    // lp_n
    output wire hsp,
    output wire hsn,
    output wire lpinp,
    output wire lpinn
);
    wire db1, db2, db, dt, np, nn, oeb;
    sg13g2_inv_1   xdb1 (.Y(db1), .A(d));
    sg13g2_inv_1   xdb2 (.Y(db2), .A(db1));
    sg13g2_inv_1   xdb  (.Y(db),  .A(db2));
    sg13g2_buf_2   xdt  (.X(dt),  .A(d));
    sg13g2_nand2_2 xnp  (.Y(np),  .A(db), .B(oe));
    sg13g2_nand2_2 xnn  (.Y(nn),  .A(dt), .B(oe));
    sg13g2_inv_16  xop  (.Y(hsp), .A(np));
    sg13g2_inv_16  xon  (.Y(hsn), .A(nn));
    sg13g2_inv_1   xoeb (.Y(oeb), .A(oe));
    sg13g2_nand2_2 xlp  (.Y(lpinp), .A(lpp), .B(oeb));
    sg13g2_nand2_2 xln  (.Y(lpinn), .A(lpn), .B(oeb));
endmodule
