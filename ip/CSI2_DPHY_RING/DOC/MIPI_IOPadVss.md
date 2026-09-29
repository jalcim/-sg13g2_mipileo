# MIPI_IOPadVss

**Valeurs ESTIMÉES — pas une spécification ni une mesure**

Base : `MAG/drc/MIPI_IOPadVss.gds` (md5 107a6901…, 28/09 10:35), `MAG/LEF/MIPI_IOPadVss.lef`, IHP-Open-PDK sg13g2_io.

## Rôle
Pad de masse du cœur (VSS, 0 V) de l'anneau CSI2_DPHY_RING. Copie de **sg13g2_IOPadVss** (IHP), avec les mêmes écarts qu'IOVss (`WAIVERS.md`, proposés le 28/09). Générée par `MAG/ring_io.tcl`, table `POWER_PADS`, entrée `IOPadVss`.

| Borne | Net | Rail (y, µm) |
|---|---|---|
| VSS (plot) | masse cœur, USE GROUND | Metal3 140-158 ; Metal4 157,8-178 ; Metal5/TopMetal1 160-178 ; stub 0-3 (M2-TopMetal2) |
| VDD | cœur 1,2 V | TopMetal1/Metal5 140-158, Metal3 160-178 |
| IOVDD | alim IO 3,3 V | TopMetal2 67,5-90 / 95-117,5 |
| IOVSS | masse IO | TopMetal2 8,5-31 / 36-58,5 / 127,5-132,5 |

## Taille
- Cellule : **80 × 180 µm** (LEF `SIZE 80.000 BY 180.000`, prBoundary 0,0-80,180 ; NWell déborde à -0,62/80,62).
- Site LEF : `sg13g2_ioSite`, `CLASS PAD POWER`. Aboutement : rails continus bord à bord (x = 0 et 80).

## Plot
- Zone de connexion au bond pad : **stub 70 × 3 µm** en bas de cellule (x 5-75, y 0-3), de Metal3 à TopMetal2, Metal2 de x 3,91 à 75. Pas de languette TopMetal2 : le stub TopMetal2 ne va nulle part ailleurs.
- Le bond pad n'est pas dans la cellule (macro ORFS `bondpad_70x70` ou PCell `bondpad`, voir `MIPI_IOPadIOVss.md`).

## Courant max DC (électromigration, 11 ans @105 °C)
**≈ 110 mA**, à condition que le bond pad descende en Metal2. C'est le cas de `bondpad_70x70` ORFS : M2-TopMetal2 empilés, pleins de vias.
Le goulot est formé des **3 bandes Metal2** qui montent du stub au rail VSS (x 15,59-34,06 / 36,06-54,53 / 56,53-75, y 3-140) : 3 × 18,47 = 55,4 µm × 2 mA/µm = 111 mA.
- Chemin : bandes Metal2, puis 4 234 Via2 (1,7 A) vers le rail Metal3 140-158.
- Sortie du rail : Metal3 18 µm = 36 mA par côté, et 92 Via3 (37 mA) vers Metal4/Metal5/TopMetal1. Au total ≈ 110 mA, du même ordre que les bandes.
- **Si le fil ne touche que le TopMetal2** (bond pad sans empilement) : la pile du stub est en série, avec 35 TopVia2 (350 mA), 35 TopVia1 (49 mA), 70 Via4 (28 mA), 70 Via3 (28 mA) puis 858 Via2 (343 mA). Le courant tombe alors à **≈ 28 mA** (Via3 ou Via4 du stub).

Méthode : `em_estimate.py --rail-y 140` (connectivité KLayout ; coupes horizontales du stub au rail ; largeur min par couche ; vias comptés par tranche stub / montée / rail ; courant = largeur × J ou nombre × I, table 2.15). Les coudes et la répartition non uniforme ne sont pas pris en compte.

## Protection ESD
D'après la netlist IHP (`sg13g2_IOPadVss`) :
- **DCN** `sg13g2_DCNDiode` : 2 × `dantenna` 27,78 × 1,26 µm, cathode VSS, anode substrat/IOVSS (conduit si VSS < IOVSS).
- **DCP** `sg13g2_DCPDiode` : 2 × `dpantenna` 27,78 × 1,26 µm, anode VSS, cathode IOVDD (conduit si VSS > IOVDD).
- Prises substrat : `ptap1` IOVSS-sub! 0,17 Ω, VSS-sub! 22,8 Ω.
- Pas de clamp dans cette cellule.

Analyse ESD : [../signoff/esd_MIPI_IOPadVss.md](../signoff/esd_MIPI_IOPadVss.md) (écrite par un autre agent, peut ne pas encore exister).

## Capacité et fuite vues du plot
Simulation ngspice de la netlist IHP, tt, VDD = 1,2 V, IOVDD = 3,3 V (`cap_fuite_MIPI_IOPadVss.cir`). Sans parasites de métal.
- Capacité VSS vers IOVSS et IOVDD : **≈ 0,10 pF** jusqu'à 100 MHz (DCN à 0 V, DCP en inverse sous 3,3 V).
- Fuite : **non estimée**. La simulation donne 20 pA à 27 °C comme à 105 °C, soit le plancher gmin du simulateur.
