// cml_gate2.v -- modele Verilog comportemental de la porte CML a deux entrees cml_gate2 (2_analog/CML_LIB/GATE2).
// GENERE le 2026-09-17 depuis la netlist livrable COLLATERALS/SPICE/cml_gate2.spice (md5 3b770f3de480ccd0b10e145e9034a5ae)
// et la campagne vernier cml_gate tt_typ_25 / 1,2 V (run/vernier/v1p20) : T_PAX 52 ps (A -> X, point de reference
// pente 0,2 UI x C_LOAD 40 fF ; 93 ps pire de grille), T_PBX 76 ps (B -> X, point de reference ; 100 ps sur l'extrait, 125 ps pire de grille). Fonction mesuree au
// .op : X = A quand B = 1, X = 0 quand B = 0, soit X = A & B (AND). Une paire differentielle = un bit :
// xp = a & b, xn = ~xp (an, bn sont les complements de ap, bp). Niveaux CML non modelises (queue resistive).
// pol : polarisation de la queue, sans effet dans ce modele (Rldpol vers VSS ; pas de broche dans le layout).
`timescale 1ps/1fs
module cml_gate2 (
    input  wire AP, AN, BP, BN,
    output wire XP, XN,
    inout  wire VDD, VSS
);
    assign XP = AP & BP;
    assign XN = ~(AP & BP);
    specify
        (AP => XP) = (52, 52);    // T_PAX tt, ps (montee, descente), entree du haut
        (AP => XN) = (52, 52);
        (AN => XP) = (52, 52);
        (AN => XN) = (52, 52);
        (BP => XP) = (76, 76);    // T_PBX tt, ps, entree du bas (point de reference)
        (BP => XN) = (76, 76);
        (BN => XP) = (76, 76);
        (BN => XN) = (76, 76);
    endspecify
endmodule
