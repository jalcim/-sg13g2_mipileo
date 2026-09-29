# cml_gate2 / cml_nand2 / cml_or2 / cml_nor2 -- kit d'integration (24/09/2026)

Porte CML a deux entrees : cml_gate2 X = A.B (AND) ; cml_nand2, cml_or2, cml_nor2 = MEME layout, seul le cablage
pad -> noeud interne change (table Lionel 17/09). Dimensionnement : `GATE2.genes` = candidat C (genes = 1, choix Lionel
24/09 contre le recordman du GA, qui ne voyait pas les delais). Vehicule d'integration pour le POC : verdict electrique
FAIL documente, pas d'optimisation avant tapeout sauf temps disponible (Lionel 24/09).

| fichier (x 4 portes) | quoi | comment |
|---|---|---|
| GDS/cml_<porte>.gds | layout de Yann G. (29/09), cadre 12,48 x 22,36 um (26 pistes de 0,48), cellule au nom cml_<porte> | `MAG/make variantes-gds` (sources GDS/cml_<porte>_yg_fix.gds) |
| LEF/cml_<porte>.lef | abstract, CLASS BLOCK, SIZE 12,48 x 22,36 ; 8 bornes, memes positions pour les 4 | `lef write -hide` |
| LIB/cml_<porte>_dummy.lib | liberty minimal sans timing : bornes, rails, surface, capacites d'entree post-layout | ecrit a la main |
| HDL/cml_<porte>.v | modele Verilog comportemental ; POL retiree (non dessinee, 24/09) | memes bornes que le LEF |
| SPICE/cml_<porte>.spice | netlist livrable (enveloppes de cml_gate2 aux broches permutees, gate2.sp) | `make netlist` / netlist.tcl -name |
| SPICE/cml_gate2_pex.spice | post-layout de cml_gate2 : extrait Magic enveloppe aux bornes de la livrable | `make pex-netlist` |
| DOC/, signoff/ | datasheet et verdicts, 27 points (9 corners x 3 VDD), schema et post-layout (cml_gate2) | `make collaterals FORCE=1`, `make pex-campagne` |

## Cadre et bornes (convention DRVB)

Rails a cheval sur le cadre : VDD y -1,00..1,00 (bas), VSS y 21,36..23,36 (haut), Metal1. Bornes Metal3 0,30 x 0,60,
debordant de 0,15 hors du cadre :

| borne | bord | y (repere du cadre) | hauteur de famille |
|---|---|---|---|
| AN / AP | gauche | 3,00..3,60 / 4,10..4,70 | h_INA |
| XN / XP | droit | 3,00..3,60 / 4,10..4,70 | h_INA : X s'aboute a l'entree A de la cellule suivante |
| BN / BP | gauche | 17,00..17,60 / 18,10..18,70 | h_INB (niveau bas, celui de l'horloge du latch) |

Pas de borne POL : Rldpol (1 GOhm ideal, netlist) n'est pas dessine, comme DRVB, TLATCH, MUX2.

| pad | AND (cml_gate2) | NAND | OR | NOR |
|---|---|---|---|---|
| AP / AN | grille xamp.xn / xamp.xp | idem | xamp.xp / xamp.xn | xamp.xp / xamp.xn |
| BP / BN | grille xmux.xp / xmux.xn | idem | xmux.xn / xmux.xp | xmux.xn / xmux.xp |
| XP / XN | noeud xp / xn | xn / xp | xn / xp | xp / xn |


## Layout de Yann G. (29/09)
- Source : `GDS/cml_gate2_yg.gds` (AND), corrige par `MAG/fix_gate2_yg.py` (XN etait ouvert : equerre Metal3 ajoutee). nand2, nor2, or2 en sont declines par `MAG/variantes_gate2_yg.py` : croisements en Metal3 pres des bornes (table du 17/09), transistors et resistances non touches.
- DRC KLayout IHP (`--no_density`) : 0. LVS netgen contre `MAG/cml_<porte>_lvs_ref.spice` : Circuits match uniquely.
- Chaine : `make -C MAG variantes-gds` (SHARED_MAGIC/gds_source.mk : le GDS est la source). Electrique post-layout (DOC, delais et capacites des Liberty) : encore celui de l'ancien layout tant que `make pex-campagne` n'est pas rejoue.

## Signoff layout (24/09, ancien layout autoroute 23,04), les quatre portes
- DRC KLayout IHP (`--no_density`) : 0 violation.
- LVS netgen contre `MAG/cml_<porte>_lvs_ref.spice` : Circuits match uniquely, sans erreur de propriete.

## Electrique (cml_gate2, 27 points)

| spec | limite | schema (pire) | post-layout (pire) |
|---|---|---|---|
| T_PAX (A -> X) | <= 0,1 UI | 0,101 FAIL (1/27) | 0,125 FAIL (21/27) |
| T_PBX (B -> X) | <= 0,2 UI | 0,156 PASS | 0,201 FAIL (1/27) |
| C_IN (A) | <= 9 fF | 7,42 PASS | 12,0 FAIL (27/27) |
| C_CK (B) | <= 9 fF | 7,96 PASS | 12,9 FAIL (27/27) |
| VOL | >= 0,75 V | 0,71 FAIL (3/27) | 0,711 FAIL (3/27) |
| VCM_OUT | 0,95..1,15 V | 0,894..1,22 FAIL | 0,895..1,22 FAIL (15/27) |
| VSW_OUT | >= 0,25 V | 0,206 FAIL (9/27) | 0,205 FAIL (9/27) |
| I_DD | <= 300 uA | 217 PASS | 217 PASS |

Paires de la declaration renommees A / B / X le 24/09 (etaient IN / CK / Q) : T_PAX / T_PBX, n.m. auparavant, sont
maintenant lus. `make vernier` : les regles latch de vernier attendent une sortie `Q` (KNOWN_BUGS 14), a revoir.
