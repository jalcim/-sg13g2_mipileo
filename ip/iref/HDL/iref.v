// iref.v -- boite noire de la reference de courant iref (2_analog/IREF, schema 2_analog/TEMPO/ISOURCE/iref.sp).
// PG : tension de grille des miroirs PMOS des cellules tempo (analogique, pas un signal logique).
// I = VDD/(4R), 10 uA a 1,2 V ; V(PG) = 0,508 V en tt_typ_25 post-extraction (COLLATERALS/DOC/corners_compare.txt).
(* blackbox *)
module iref (
    output wire PG,
    inout  wire VDD, VSS
);
endmodule
