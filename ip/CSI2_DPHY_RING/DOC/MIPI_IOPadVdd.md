# MIPI_IOPadVdd

**Valeurs ESTIMÉES — pas une spécification ni une mesure**

Base : `MAG/drc/MIPI_IOPadVdd.gds` (md5 1e23c2c4…, 28/09 10:37), `MAG/LEF/MIPI_IOPadVdd.lef`, IHP-Open-PDK sg13g2_io.

## Rôle
Pad d'alimentation du cœur (VDD, 1,2 V) de l'anneau CSI2_DPHY_RING, avec clamp ESD VDD-IOVSS. Copie de **sg13g2_IOPadVdd** (IHP), avec les mêmes écarts qu'IOVdd plus les bords sous RC_INV (`WAIVERS.md`, proposés le 28/09). Générée par `MAG/ring_io.tcl`, table `POWER_PADS`, entrée `IOPadVdd`.

| Borne | Net | Rail (y, µm) |
|---|---|---|
| VDD (plot) | cœur 1,2 V, USE POWER | TopMetal1/Metal5 140-158, Metal4 140-160,2, Metal3 160-178 ; stub 0-3 |
| VSS | masse cœur | TopMetal1/Metal5 160-178, Metal3 140-158 |
| IOVDD | alim IO 3,3 V | M3-TopMetal1 66-119 ; TopMetal2 coupé en x 3,9-76,1 |
| IOVSS | masse IO | M3-TopMetal1 7-60 / 126-134 ; TopMetal2 coupé en x 3,9-76,1 |

Tous les rails TopMetal2 (IOVSS, IOVDD) sont coupés pour laisser passer les colonnes VDD ; ils sont repris en TopMetal1 par des TopVia2 aux bords (`rail_cut`).

## Taille
- Cellule : **80 × 180 µm** (LEF `SIZE 80.000 BY 180.000`, prBoundary 0,0-80,180 ; NWell déborde à -0,62/80,62).
- Site LEF : `sg13g2_ioSite`, `CLASS PAD POWER`. Aboutement : rails continus bord à bord (x = 0 et 80).

## Plot
- Zone de connexion au bond pad : **stub TopMetal2 70 × 3 µm** en bas de cellule (x 5-75, y 0-3), doublé de Metal2 à TopMetal1.
- Le bond pad n'est pas dans la cellule (macro ORFS `bondpad_70x70` ou PCell `bondpad`, voir `MIPI_IOPadIOVss.md`).

## Courant max DC (électromigration, 11 ans @105 °C)
**≈ 0,37 A par côté, soit ≈ 0,75 A si le courant se partage à égalité entre la gauche et la droite de l'anneau.** Le goulot est le rail VDD à la sortie de la cellule : TopMetal1 18 µm (270 mA), Metal5 18 µm (36 mA), Metal4 15,8 µm (32 mA) et Metal3 18 µm (36 mA).
- Montée du plot au rail : **3 colonnes TopMetal2** (x 7,5-25,83 / 30,83-49,16 / 54,17-72,5, y 3-132,5), soit 3 × 18,33 = 55,0 µm × 16 mA/µm = 880 mA. Elles arrivent sur une plaque TopMetal2 (y 132,5-156,5).
- Plaque vers rail TopMetal1 : 224 TopVia2 (2,2 A) en série, ce n'est pas le goulot. Vers les couches basses du rail : 266 TopVia1 (372 mA), 234 Via4, 92 Via3.
- Le rail est commun à tout l'anneau : les pads VDD voisins et le PDN du top en déchargent une partie. Le chiffre par côté vaut donc pour la seule sortie de cette cellule.

Méthode : `em_estimate.py --rail-y 127.5` (connectivité KLayout ; coupes horizontales du stub au rail ; largeur min par couche ; vias comptés par tranche stub / montée / rail ; coupes verticales du rail ; courant = largeur × J ou nombre × I, table 2.15). Les coudes et la répartition non uniforme ne sont pas pris en compte.

## Protection ESD
D'après la netlist IHP (`sg13g2_IOPadVdd`) :
- **Clamp** `sg13g2_Clamp_N43N43D4R` : 172 NMOS HV 4,4/0,6 µm (W total 757 µm), drain VDD, source IOVSS.
- **Déclencheur RC** : `sg13g2_RCClampResistor` (26 × `rppd` 5,239 kΩ ≈ 136 kΩ) vers VDD, et `sg13g2_RCClampInverter` alimenté par VDD (PMOS HV 350/0,5, NMOS HV 2 × 54/0,5, capacités MOS HV 2 × 63/9,5 µm).
- Prises substrat : `ptap1` IOVSS-sub! 0,46 Ω, VSS-sub! 22,5 Ω.

Analyse ESD : [../signoff/esd_MIPI_IOPadVdd.md](../signoff/esd_MIPI_IOPadVdd.md) (écrite par un autre agent, peut ne pas encore exister).

## Capacité et fuite vues du plot
Simulation ngspice de la netlist IHP, tt, VDD = 1,2 V, IOVDD = 3,3 V (`cap_fuite_MIPI_IOPadVdd.cir`). Sans parasites de métal.
- Capacité VDD-IOVSS : **≈ 5,9 pF sous 10 kHz** (capacités MOS du déclencheur à travers 136 kΩ) ; **≈ 0,86 pF de 10 à 100 MHz** ; 0,72 pF à 1 GHz.
- Fuite VDD vers IOVSS, clamp bloqué : **≈ 0,23 nA à 27 °C, ≈ 4,4 nA à 105 °C**.
