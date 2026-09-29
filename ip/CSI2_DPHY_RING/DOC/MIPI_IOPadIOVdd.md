# MIPI_IOPadIOVdd

**Valeurs ESTIMÉES — pas une spécification ni une mesure**

Base : `MAG/drc/MIPI_IOPadIOVdd.gds` (md5 add52286…, 28/09 10:35), `MAG/LEF/MIPI_IOPadIOVdd.lef`, IHP-Open-PDK sg13g2_io.

## Rôle
Pad d'alimentation des IO (IOVDD, 3,3 V) de l'anneau CSI2_DPHY_RING, avec clamp ESD IOVDD-IOVSS. Copie de **sg13g2_IOPadIOVdd** (IHP), identique au XOR hors waivers (`WAIVERS.md`). Générée par `MAG/ring_io.tcl`, table `POWER_PADS`, entrée `IOPadIOVdd`.

| Borne | Net | Rail (y, µm) |
|---|---|---|
| IOVDD (plot) | alim IO 3,3 V, USE POWER | TopMetal2 67,5-90 / 95-117,5 ; M3-TopMetal1 66-91,5 / 93,5-119 ; stub 0-3 |
| IOVSS | masse IO | TopMetal2 8,5-31 / 36-58,5 (coupés en x 3,9-76,1 pour laisser passer les languettes) / 127,5-132,5 |
| VDD | cœur 1,2 V | TopMetal1 140-158 |
| VSS | masse cœur | TopMetal1 160-178 |

## Taille
- Cellule : **80 × 180 µm** (LEF `SIZE 80.000 BY 180.000`, prBoundary GDS 0,0-80,180 ; NWell déborde à -0,62/80,62).
- Site LEF : `sg13g2_ioSite` (1 × 180 µm), `CLASS PAD POWER`, symétrie X Y R90.
- Aboutement : rails continus bord à bord (x = 0 et 80). Les rails IOVSS en TopMetal2 sont coupés au milieu et repris en TopMetal1 par des TopVia2 aux bords (`rail_cut`).

## Plot
- Zone de connexion au bond pad : **stub TopMetal2 70 × 3 µm** en bas de cellule (x 5-75, y 0-3), doublé en TopMetal1.
- Le bond pad n'est **pas** dans la cellule. IHP ne le met pas dans `sg13g2_io` : il vient à part, soit la macro `bondpad_70x70` (70 × 70 µm, M2-TopMetal2, `CLASS COVER`) de la plateforme ORFS `ihp-sg13g2`, placée par `place_bondpad` sous le stub (offset 5 µm), soit la PCell KLayout `bondpad` de `sg13g2_pr` (octogone 80 µm, TopMetal2 par défaut).

## Courant max DC (électromigration, 11 ans @105 °C)
**≈ 0,88 A**, goulot = les 3 languettes TopMetal2 qui montent du stub au rail IOVDD (x 7,5-25,83 / 30,83-49,16 / 54,17-72,5, y 3-67,5) : 3 × 18,33 = 55,0 µm × 16 mA/µm.
- Aucun via en série : le chemin plot → rail reste en TopMetal2. Aucune autre couche ne relie le stub au rail.
- Rail, par côté de la cellule : TopMetal2 45 µm (720 mA) + TopMetal1 51 µm (765 mA) + M3-M5 3 × 51 µm (306 mA) ≈ 1,8 A. Ce n'est pas le goulot.

Méthode (`em_estimate.py`) : connectivité KLayout (M1-TopMetal2 + vias), net du plot pris au stub (40 ; 1,5). Lignes de coupe horizontales de y = 0 au premier y où TopMetal2 couvre toute la largeur, puis largeur min du net par couche et nombre de vias par niveau. Courant = largeur × J (table 2.15, `SG13G2_os_process_spec.pdf`). Les coudes, la répartition non uniforme et l'échauffement ne sont pas pris en compte.

## Protection ESD
D'après la netlist IHP (`sg13g2_io.spice`, `sg13g2_IOPadIOVdd`) :
- **Clamp** `sg13g2_Clamp_N43N43D4R` : 172 NMOS HV `sg13_hv_nmos` 4,4/0,6 µm (W total 757 µm), drain IOVDD, source IOVSS.
- **Déclencheur RC** : `sg13g2_RCClampResistor` (26 × `rppd` 5,239 kΩ ≈ 136 kΩ, 20/1 µm) et `sg13g2_RCClampInverter` (PMOS HV 350/0,5, NMOS HV 2 × 54/0,5, capacités MOS HV 2 × 63/9,5 µm).
- Prises substrat : `ptap1` IOVSS-sub! 0,45 Ω, VSS-sub! 22,5 Ω.

Analyse ESD : [../signoff/esd_MIPI_IOPadIOVdd.md](../signoff/esd_MIPI_IOPadIOVdd.md) (écrite par un autre agent, peut ne pas encore exister).

## Capacité et fuite vues du plot
Simulation ngspice de la netlist IHP, tt, IOVDD = 3,3 V, IOVSS = 0, VDD = 1,2 V (`cap_fuite_MIPI_IOPadIOVdd.cir`, `.global sub!` ajouté). Sans parasites de métal.
- Capacité IOVDD-IOVSS : **≈ 6,1 pF sous 10 kHz** (les capacités MOS du déclencheur, vues à travers 136 kΩ) ; **≈ 0,77 pF de 1 à 100 MHz** (jonctions du clamp et de l'inverseur) ; 0,65 pF à 1 GHz.
- Fuite IOVDD, clamp bloqué : **≈ 0,7 nA à 27 °C, ≈ 7 nA à 105 °C**.
