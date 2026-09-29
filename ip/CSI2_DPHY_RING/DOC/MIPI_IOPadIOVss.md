# MIPI_IOPadIOVss

**Valeurs ESTIMÉES — pas une spécification ni une mesure**

Base : `MAG/drc/MIPI_IOPadIOVss.gds` (md5 a2f087ab…, 28/09 10:35), `MAG/LEF/MIPI_IOPadIOVss.lef`, IHP-Open-PDK sg13g2_io.

## Rôle
Pad de masse des IO (IOVSS, 0 V) de l'anneau CSI2_DPHY_RING. Copie de **sg13g2_IOPadIOVss** (IHP), identique au XOR hors waivers (`WAIVERS.md`). Générée par `MAG/ring_io.tcl`, table `POWER_PADS`, entrée `IOPadIOVss`.

| Borne | Net | Rail (y, µm) |
|---|---|---|
| IOVSS (plot) | masse IO, USE GROUND | TopMetal2 8,5-31 / 36-58,5 / 127,5-132,5 ; M3-TopMetal1 7-32,5 / 34,5-60 / 126-134 ; stub 0-3 |
| IOVDD | alim IO 3,3 V | M3-TopMetal2 66-119 |
| VDD | cœur 1,2 V | TopMetal1/Metal5 140-158, Metal3 160-178 |
| VSS | masse cœur | TopMetal1/Metal5 160-178, Metal3 140-158 |

Texte `sub!` (substrat) : voir `waiver_control.md`.

## Taille
- Cellule : **80 × 180 µm** (LEF `SIZE 80.000 BY 180.000`, prBoundary GDS 0,0-80,180 ; NWell déborde à -0,62/80,62).
- Site LEF : `sg13g2_ioSite` (1 × 180 µm), `CLASS PAD POWER`, symétrie X Y R90.
- Aboutement : rails continus bord à bord sur toute la largeur (x = 0 et 80), comme les cellules IHP.

## Plot
- Zone de connexion au bond pad : **stub 70 × 3 µm** en bas de cellule (x 5-75, y 0-3) sur Metal3…TopMetal2 (Metal2 x 3,91-75).
- Le bond pad n'est **pas** dans la cellule. IHP ne le met pas dans `sg13g2_io` : il vient à part, soit la macro `bondpad_70x70` (70 × 70 µm, M2-TopMetal2, `CLASS COVER`) de la plateforme ORFS `ihp-sg13g2`, placée par `place_bondpad` sous le stub (offset 5 µm), soit la PCell KLayout `bondpad` de `sg13g2_pr` (octogone 80 µm, TopMetal2 par défaut).

## Courant max DC (électromigration, 11 ans @105 °C)
**≈ 0,88 A**, goulot = les 3 languettes TopMetal2 entre le stub et le 1er rail (x 7,5-25,83 / 30,83-49,16 / 54,17-72,5, y 3-8,5) : 3 × 18,33 = 55,0 µm × 16 mA/µm.
- Aucun via en série : le chemin plot → rail reste en TopMetal2. En parallèle, le Metal2 (57,9 µm, +116 mA) si le bond pad descend en Metal2 ; non compté.
- Metal3-TopMetal1 : coupés entre y = 3 et 7, pas de chemin direct ; les 35 TopVia2 du stub (350 mA) ne font que relier TopMetal1 au stub TopMetal2.
- Rail, par côté de la cellule : TopMetal2 50 µm (800 mA) + TopMetal1 59 µm (885 mA) + M3-M5 3 × 59 µm (354 mA) ≈ 2,0 A. Ce n'est pas le goulot.

Méthode (`em_estimate.py`) : connectivité KLayout (M1-TopMetal2 + vias), net du plot pris au stub (40 ; 1,5). Lignes de coupe horizontales de y = 0 au premier y où TopMetal2 couvre toute la largeur, puis largeur min du net par couche et nombre de vias par niveau. Courant = largeur × J (table 2.15, `SG13G2_os_process_spec.pdf`). Les coudes, la répartition non uniforme et l'échauffement ne sont pas pris en compte.

## Protection ESD
D'après la netlist IHP (`sg13g2_io.spice`, `sg13g2_IOPadIOVss`) :
- **DCP** `sg13g2_DCPDiode` : 2 × `dpantenna` 27,78 × 1,26 µm, anode IOVSS, cathode IOVDD (conduit si IOVSS > IOVDD).
- **DCN** `sg13g2_DCNDiode` : 2 × `dantenna` 27,78 × 1,26 µm, anode et cathode sur IOVSS, garde IOVDD (la netlist la court-circuite).
- Prises substrat : `ptap1` IOVSS-sub! 0,17 Ω, VSS-sub! 22,5 Ω.
- Diodes tirées de `sg13g2_esd.gds` (GDS IHP, lu en lecture seule).

Analyse ESD : [../signoff/esd_MIPI_IOPadIOVss.md](../signoff/esd_MIPI_IOPadIOVss.md) (écrite par un autre agent, peut ne pas encore exister).

## Capacité et fuite vues du plot
Simulation ngspice de la netlist IHP, tt, IOVDD = 3,3 V, VDD = 1,2 V (`cap_fuite_MIPI_IOPadIOVss.cir`). Sans parasites de métal.
- Capacité IOVSS-IOVDD ajoutée par la cellule : **≈ 36 fF** (DCP en inverse sous 3,3 V ; stable jusqu'à 100 MHz). Sans intérêt pour un pad de masse : IOVSS est aussi le substrat.
- Fuite : **non estimée**. La simulation donne 20 pA à 27 °C comme à 105 °C, soit le plancher gmin du simulateur, pas la diode.
