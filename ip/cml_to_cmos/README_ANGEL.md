# cml_to_cmos -- kit d'integration (27/09/2026)

Convertisseur CML -> CMOS : paire NMOS du DRVB (queue resistive rppd) chargee par un miroir PMOS, puis deux inverseurs qui
remettent de rail a rail. Y en phase avec INP. Dimensionnement : `CML_TO_CMOS.genes`. Spec : `cml_to_cmos_spec.tcl` (CMLO*).

| fichier | quoi | comment |
|---|---|---|
| GDS/cml_to_cmos.gds | layout de Yann G. (29/09), cadre 12,96 x 22,36 um (27 pistes de 0,48) | `MAG/make deploy-gds` (source GDS/cml_to_cmos_yg_fix.gds) |
| LEF/cml_to_cmos.lef | abstract ; bornes INP INN Y VDD VSS | `lef write -hide` |
| LIB/cml_to_cmos_dummy.lib | liberty minimal sans timing : bornes, rails, surface, C d'entree post-layout par borne | ecrit a la main |
| HDL/cml_to_cmos.v | modele Verilog, T_P post-layout tt 25 C 1,2 V | memes bornes que le LEF |
| SPICE/cml_to_cmos.spice | netlist livrable | `make netlist` |
| SPICE/cml_to_cmos_pex.spice | post-layout : extrait Magic enveloppe aux bornes de la livrable | `make pex-netlist` |
| DOC/, signoff/ | datasheet et verdicts, 27 points, schema et post-layout, banc ngspice tb_cml_to_cmos.sp | `make collaterals FORCE=1`, `make pex-campagne FORCE=1` |


## Layout de Yann G. (29/09)
- Source : `GDS/cml_to_cmos_yg.gds`, corrige par `MAG/fix_cml_to_cmos_yg.py` (texte Y remis sur sa borne, texte INP en trop retire, deux Via1 sans Metal2 retires).
- DRC KLayout IHP (`--no_density`) : 0. LVS netgen contre `MAG/cml_to_cmos_lvs_ref.spice` : Circuits match uniquely.
- Chaine : `make -C MAG mag-gds verif-gds drc-gds lvs-gds deploy-gds` (SHARED_MAGIC/gds_source.mk : le GDS est la source). Electrique post-layout (DOC, delais et capacites des Liberty) : encore celui de l'ancien layout tant que `make pex-campagne` n'est pas rejoue.

## Signoff layout (27/09, ancien layout autoroute 23,04)
- DRC KLayout IHP : 0. LVS netgen : Circuits match uniquely.

## Electrique, post-layout, pire cas sur 27 points -- verdict FAIL, datasheets FORCEES (Lionel 27/09)
- CML3 C_IN : INP 10,1 fF, INN 23,8 fF pour <= 9 fF. INN attaque le drain du miroir (noeud haute impedance) : Miller.
- CMLO14 D_DUTY : 2,03 % pour <= 2 %, un seul point (ss_wcs_m40, 1,08 V).
- CMLO12 T_P : 0,30 UI max pour <= 0,5 UI. Details : DOC/cml_to_cmos_pex_sim.md.
- VSW_IN, VCM_IN_LOW/HIGH : n.m. (critere DC de la famille non significatif sur un comparateur, methode a fixer).
