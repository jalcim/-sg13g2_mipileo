# MIPI_IOPadOut

**Chiffres de simulation ou relevés sur le dessin : ce n'est ni une spécification ni une mesure silicium. Netlist brouillon.**

Base : `MAG/drc/MIPI_IOPadOut.gds` (md5 f581c5f3…, 29/09 13:26), `MAG/LEF/MIPI_IOPadOut.lef` (29/09 13:26), netlist `LVCMOS12/lvcmos12_out/lvcmos12_out.sp` (brouillon du 29/09, md5 a73ba166…, non commitée), IHP-Open-PDK sg13g2_io (`sg13g2_DCNDiode`, `sg13g2_DCPDiode`).

## Rôle
Sortie LVCMOS 1,2 V de l'anneau CSI2_DPHY_RING, dans le domaine IO MIPI 1,2 V (IOVDD_MIPI / IOVSS_MIPI, séparé du reste de l'anneau par `MIPI_CornerBreaker`). Elle est donnée pour 4 mA et environ 50 Ω de sortie (en-tête de la netlist). PAD = A, sans inversion.
Générée par `MAG/ring_LVCMOS.tcl`, procs `IOPadOut` et `IOPadOut_route`. Le cadre et les diodes DCN/DCP sont ceux de `IOPadRX`. Classe LEF `PAD OUTPUT` (`magcilib`, `PAD_CLASS`).

## Schéma
Du cœur vers le plot. Tous les MOS sont LV (oxyde mince), L = 0,13 µm. W est le total, avec le nombre de doigts.

| Étage | NMOS | PMOS | Alimentation |
|---|---|---|---|
| Inverseur d'entrée (A → ab) | XI1N 1 µm | XI1P 2 µm | VDD / VSS cœur |
| Décaleur VDD → IOVDD, paire croisée (A, ab → ls, lsb) | XL1N, XL2N 2 µm | XL1P, XL2P 0,3 µm | IOVDD / IOVSS |
| Rampe 1 (ls → p1) | XP1N 0,6 µm | XP1P 1,5 µm | IOVDD / IOVSS |
| Rampe 2 (p1 → p2) | XP2N 2,2 µm | XP2P 6 µm (2 doigts) | IOVDD / IOVSS |
| Rampe 3 (p2 → p3) | XP3N 9 µm (2 doigts) | XP3P 24 µm (6 doigts) | IOVDD / IOVSS |
| Sortie (p3 → no, po) | XON 41 µm (8 doigts) | XOP 117 µm (24 doigts) | IOVDD / IOVSS |
| Résistances série | XRN `rsil` w 4 / l 17 µm (no → PAD) | XRP `rsil` w 4 / l 17 µm (po → PAD) | bulk IOVSS |

La netlist annonce environ 20 Ω pour l'étage de sortie et 30 Ω par `rsil`. Ces deux valeurs sont écrites dans la netlist, pas mesurées. Elle ne contient pas d'ESD : le plot apporte DCN et DCP.

## Bornes
D'après `MAG/LEF/MIPI_IOPadOut.lef`. Coordonnées en µm, le plot est en bas (y = 0) et le cœur en haut (y = 180).

| Borne | Direction LEF | Domaine | Plage d'accès (couche, position) |
|---|---|---|---|
| A | INPUT | cœur 1,2 V | Metal2 x 39,85-40,15, y 121,33-180 : sort au bord haut (label y 179-180, `core_port`). `ANTENNAGATEAREA` 0,65 µm² |
| PAD | INOUT, USE SIGNAL | IO 1,2 V | stub x 5-75, y 0-3 de Metal3 à TopMetal2 (Metal2 x 3,91-75). Deux bandes Metal2 x 30,02-33,42 et x 50,02-53,42, y 3-67, vers les rsil |
| VDD | INOUT, USE POWER | cœur 1,2 V | rail Metal3 y 160-178 ; Metal5/TopMetal1 y 140-158 ; Metal4 y 140-155,8 |
| VSS | INOUT, USE GROUND | masse cœur | rail Metal3 y 140-158 ; Metal5/TopMetal1 y 160-178 ; Metal4 y 162,2-178 |
| IOVDD | INOUT | IO 1,2 V (IOVDD_MIPI) | Metal3 à TopMetal1 y 66-91,5 et 93,5-119 ; TopMetal2 y 67,5-90 et 95-117,5 |
| IOVSS | INOUT | masse IO | Metal3 à TopMetal1 y 7-32,5 / 34,5-60 / 126-134 ; TopMetal2 y 8,5-31 / 36-58,5 / 127,5-132,5 |

`ANTENNADIFFAREA` du PAD : 140,01 µm². Les rails vont d'un bord à l'autre (x = 0 et 80).

## Taille
- Cellule : **80 × 180 µm** (LEF `SIZE 80.000 BY 180.000`), site `sg13g2_ioSite`, symétrie X Y R90.
- Le bond pad n'est pas dans la cellule (voir `MIPI_IOPadIOVss.md`, section Plot).

## Protection ESD
- **DCN** `sg13g2_DCNDiode` (2 × `dantenna` 27,78 × 1,26 µm, PAD → substrat/IOVSS) et **DCP** `sg13g2_DCPDiode` (2 × `dpantenna` 27,78 × 1,26 µm, PAD → IOVDD). Mêmes positions que dans `sg13g2_IOPadIn`.
- Pas de protection secondaire. Les drains LV de l'étage de sortie voient le PAD à travers les rsil.
- Analyse ESD : **n.m.** (aucun `signoff/esd_MIPI_IOPadOut.md`). La tenue des drains à oxyde mince n'a pas été évaluée.

## Implantation
C'est un pré-placement : `OUT_PARTS` fixe la position et `IOPadOut_route` fait le routage.
- Le flux va du haut (cœur) vers le bas (PAD), une rangée par étage, à 2 µm l'une de l'autre :
  - XI1 : y 117,8 ;
  - décaleur : y 113,1 ;
  - XP1 : y 108,9 ;
  - XP2 : y 103,1 ;
  - XP3 : y 95,9 ;
  - sortie : y 88 ;
  - rsil : y 66,7 à 84,4.
- **NMOS à gauche** (x 30), sources sur un bus IOVSS en Metal2 (x 28, y 59-116), descendu par des vias v2 dans le rail Metal3 IOVSS (y 59,4). **PMOS à droite** (x 50), sources reliées par des vias empilés au rail Metal3 IOVDD juste au-dessus.
- **Couloir central** Metal2 vertical, une piste par nœud : p3 x 40, p2 x 42, p1 x 44, ls x 46, lsb x 48,35. Les drains de chaque étage vont au couloir et les grilles de l'étage suivant y sont reprises par un plot Metal1 commun à N et P, avec un seul via.
- **rsil** alignées sous leur transistor de sortie (XRN x 29,7-33,7 ; XRP x 49,7-53,7). Elles sont sans anneau et sans vias (`guard 0`, `vias 0`) : avec l'anneau de la gencell, la règle EXTB.c ne passe pas.
- **PMOS sans anneau.** Les prises nwell sont posées au routage : une colonne x 64,3-65,3, y 88,3-114, reliée à IOVDD par des vias empilés, plus une prise locale pour XI1P sur VDD cœur.
- **Inverseur d'entrée sur VDD/VSS cœur.** La source de XI1N monte au rail Metal3 VSS (y 150), celle de XI1P au rail Metal3 VDD (y 170).
- Les barres de grille inutilisées sont allongées (M1.d).

## Vérification physique
- **DRC** KLayout d'IHP (`--no_density`), jeux main et `sg13g2_maximal` : **0 erreur**. Source : `MAG/drc/drc_MIPI_IOPadOut.log` (29/09 13:27, rapport dans `MAG/drc/run_out/`).
- **Extraction** Magic 8.3.683, refaite le 29/09 à partir de `MAG/drc/MIPI_IOPadOut.gds`, dans un dossier temporaire hors dépôt. Résultat :
  - 16 composants, connectés comme dans `lvcmos12_out.sp` : XON 8 × 5,13 µm, XOP 24 × 4,88 µm (arrondis du dessin de 5,125 et 4,875), rsil 4 / 17 à bulk VSS ;
  - DCN et DCP : 2 × 27,78 × 1,26 chacune.
  
  Comparaison faite en relisant les deux netlists, sans LVS netgen. Magic signale `Ports "VSS" and "IOVSS" are electrically shorted` : les deux sont reliés au substrat par des prises ptap, comme dans les cellules IHP.
- Livraison : la cellule est dans `NOT_DELIVERED` (`magcilib`). Elle n'est **pas** dans `COLLATERALS/GDS/MIPI_ring.gds` ni dans `LEF/MIPI_ring.lef`.

## Performances
Banc `LVCMOS12/lvcmos12_out/banc_sortie.py`, lancé le 29/09 dans un dossier temporaire : `banc_sortie.py lvcmos12_out.sp lvcmos12_out 25e6 1.2`. Conditions :
- VDDIO = VDD, soit 1,2 V à tt, 1,08 V à ss et 1,32 V à ff ;
- charge C_L = 30 pF, entrée à 25 MHz (fréquence choisie pour ce lancement) avec fronts de 100 ps ;
- netlist schéma seule : sans parasites, sans DCN/DCP.

Le banc fait tourner ses trois corners en dur. Le typique demandé est tt_typ_25 ; les deux autres corners sont reportés parce qu'ils ont été simulés.

| Grandeur | tt_typ_25 | ss_wcs_125 | ff_bcs_m40 |
|---|---|---|---|
| Ron haut (PAD tiré de 4 mA) | 49,8 Ω | 75,2 Ω | 33,7 Ω |
| Ron bas (4 mA injectés) | 47,7 Ω | 73,5 Ω | 34,5 Ω |
| t_PLH (A 50 % VDD → PAD 50 % VDDIO) | 1,54 ns | 2,36 ns | 1,03 ns |
| t_PHL | 1,49 ns | 2,34 ns | 1,05 ns |
| Montée 10-90 % | 3,42 ns | 5,12 ns | 2,31 ns |
| Descente 90-10 % | 3,38 ns | 5,17 ns | 2,43 ns |

VOH et VOL à ±4 mA se déduisent de Ron : VOH = VDDIO − 4 mA · Ron haut, VOL = 4 mA · Ron bas.
Le banc imprime aussi un courant I(VDDIO) de 4,92 mA à tt. Il n'est **pas** reporté comme consommation, car la même source VDDIO alimente l'instance DC qui débite 4 mA dans le PAD. La consommation dynamique sur 30 pF est donc **n.m.**

Non mesuré :
- capacité et fuite vues du PAD : **n.m.** ;
- courant de court-circuit : **n.m.** ;
- courant max DC du plot (électromigration, les bandes PAD en Metal2 font 3,4 µm) : **n.m.** ;
- post-layout : **n.m.** ;
- corners de rails décalés (VDD ≠ VDDIO) : **n.m.**

## Points ouverts
- **Netlist brouillon** du 29/09, non commitée. Aucune spec de sortie LVCMOS 1,2 V dans `specification/specs/` (seule existe la spec du trigger d'entrée), donc aucun verdict.
- Pas d'activation (OE), pas de tri-state, pas de réglage de courant de sortie.
- Aucun banc de spec (chaîne make, corners, verdict) : seulement `banc_sortie.py`, 3 corners, sans parasites.
- Liberty de l'anneau : `COLLATERALS/LIB/MIPI_io_<corner>.lib` est en cours de production par un autre agent. Il n'existe aujourd'hui que `MIPI_ring_dummy.lib`.
- Pas encore livrée dans le bundle `MIPI_ring` (`NOT_DELIVERED`). Pas de HDL.
- Pas d'analyse ESD pour les drains LV reliés au PAD.
