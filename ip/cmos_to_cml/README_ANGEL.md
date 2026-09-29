# cmos_to_cml -- kit d'integration (27/09/2026)

Convertisseur CMOS -> CML : paire NMOS attaquee par A et par /A (inverseur CMOS interne), charges rppd, queue en miroir NMOS
sur POLN (meme arbre et meme net que HS_TO_CLK). OUTP en phase avec A. Dimensionnement : `CMOS_TO_CML.genes`.
Spec : `cmos_to_cml_spec.tcl` (CMLI*).

| fichier | quoi | comment |
|---|---|---|
| GDS/cmos_to_cml.gds | layout, cadre 23,04 x 22,36 um (2 pas) | `MAG/make deploy-autoroute` |
| LEF/cmos_to_cml.lef | abstract ; bornes A OUTP OUTN POLN VDD VSS | `lef write -hide` |
| LIB/cmos_to_cml_dummy.lib | liberty minimal sans timing : bornes, rails, surface, C d'entree post-layout | ecrit a la main |
| HDL/cmos_to_cml.v | modele Verilog, T_P post-layout tt 25 C 1,2 V | memes bornes que le LEF |
| SPICE/cmos_to_cml.spice | netlist livrable | `make netlist` |
| SPICE/cmos_to_cml_pex.spice | post-layout : extrait Magic enveloppe aux bornes de la livrable | `make pex-netlist` |
| DOC/, signoff/ | datasheet et verdicts, 27 points, schema et post-layout, banc ngspice tb_cmos_to_cml.sp | `make collaterals FORCE=1`, `make pex-campagne FORCE=1` |

## Signoff layout (27/09)
- DRC KLayout IHP : 0. LVS netgen : Circuits match uniquely.

## Electrique, post-layout, pire cas sur 27 points -- verdict FAIL, datasheets FORCEES (Lionel 27/09)
- CML10 VCM_OUT : 0,934 a 1,19 V pour 0,95 ... 1,15 V : le mode commun suit VDD (VDD - 0,15 V) ; toute la famille est dans ce cas.
- Tout le reste PASS : T_P 0,093 UI, DT_PN 28,6 ps (<= 50), D_DUTY 0,76 % (<= 5), VSW_OUT >= 0,273 V, VOL >= 0,787 V.
- Banc : pente d'entree 50 ps (CMLI0a a fixer) ; VSW_OUT mesure a 1 Gb/s sur la cellule seule ; POLN par la replique HS_TO_CLK
  (700 uA dans 40u/0,1313u ng 4). C_IN_CMOS 24,3 fF et I_DD documentaires (lignes NA). Details : DOC/cmos_to_cml_pex_sim.md.
