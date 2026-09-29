// cmos_to_cml.v -- modele Verilog comportemental du convertisseur CMOS -> CML cmos_to_cml (2_analog/CML_LIB/CMOS_TO_CML).
// Ecrit le 2026-09-27 depuis la netlist livrable COLLATERALS/SPICE/cmos_to_cml.spice (md5 3b66b9857690e71288850bc1ab094f78)
// et le datasheet POST-LAYOUT COLLATERALS/DOC/cmos_to_cml_pex_sim.md (CMLI12 T_P tt_typ_25 / 1,2 V : 77 ps ;
// CMLI13 decalage OUTP/OUTN 24 ps, non modelise). Paire NMOS attaquee par A et /A, charge resistive :
// OUTP en phase avec A, OUTN = ~A. POLN : polarisation de la queue, sans effet dans ce modele.
`timescale 1ps/1fs
module cmos_to_cml (
    input  wire A,
    output wire OUTP, OUTN,
    inout  wire POLN, VDD, VSS
);
    assign OUTP = A;
    assign OUTN = ~A;
    specify
        (A => OUTP) = (77, 77);   // T_P post-layout tt_typ_25/1,2V (CMLI12, cmos_to_cml_pex_sim.md), ps (montee, descente)
        (A => OUTN) = (77, 77);
    endspecify
endmodule
