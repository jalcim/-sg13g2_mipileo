// cml_to_cmos.v -- modele Verilog comportemental du convertisseur CML -> CMOS cml_to_cmos (2_analog/CML_LIB/CML_TO_CMOS).
// Ecrit le 2026-09-27 depuis la netlist livrable COLLATERALS/SPICE/cml_to_cmos.spice (md5 0dec5e85f985706f003c37e045cb63a0)
// et le datasheet POST-LAYOUT COLLATERALS/DOC/cml_to_cmos_pex_sim.md (CMLO12 T_P tt_typ_25 / 1,2 V : 241 ps).
// Paire NMOS chargee par un miroir PMOS, puis deux inverseurs : Y en phase avec INP (non inverseur).
// Sortie X si INP = INN (entree differentielle nulle, etat non defini).
`timescale 1ps/1fs
module cml_to_cmos (
    input  wire INP, INN,
    output wire Y,
    inout  wire VDD, VSS
);
    assign Y = (INP === ~INN) ? INP : 1'bx;
    specify
        (INP => Y) = (241, 241);   // T_P post-layout tt_typ_25/1,2V (CMLO12, cml_to_cmos_pex_sim.md), ps (montee, descente)
        (INN => Y) = (241, 241);
    endspecify
endmodule
