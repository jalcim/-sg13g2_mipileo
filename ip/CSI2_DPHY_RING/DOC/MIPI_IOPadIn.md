# MIPI_IOPadIn

**Chiffres de simulation ou relevés sur le dessin : ce n'est ni une spécification ni une mesure silicium.**

Base : `MAG/drc/MIPI_IOPadIn.gds` (md5 0e570e7c…, 29/09 13:03), `MAG/LEF/MIPI_IOPadIn.lef` (29/09 13:26), netlist `LVCMOS12/lvcmos12_schm_in/lvcmos12_schm_in.sp` (livrable `COLLATERALS/SPICE/lvcmos12_schm_in.spice`, md5 7c56b391…), IHP-Open-PDK sg13g2_io (`sg13g2_SecondaryProtection`, `sg13g2_DCNDiode`, `sg13g2_DCPDiode`).
Le .mag et le LEF (13:26) sont plus récents que le GDS passé au DRC (13:03). Je n'ai pas vérifié que le dessin est resté le même.

## Rôle
Entrée LVCMOS 1,2 V de l'anneau CSI2_DPHY_RING, dans le domaine IO MIPI 1,2 V (IOVDD_MIPI / IOVSS_MIPI, séparé du reste de l'anneau par `MIPI_CornerBreaker`). Il n'y a pas de domaine 1,8 V dans l'anneau (Lionel, 29/09).
PAD → protection secondaire → trigger de Schmitt → P2C vers le cœur. Générée par `MAG/ring_LVCMOS.tcl`, proc `IOPadIn`. Le cadre et les diodes DCN/DCP sont ceux de `IOPadRX` (`ring_RX.tcl`, `POWER_PADS IOPadRX`), aux positions de `sg13g2_IOPadIn`. Classe LEF `PAD INPUT` (`magcilib`, `PAD_CLASS`).

## Schéma
| Étage | Composants | Alimentation |
|---|---|---|
| ESD primaire | **DCN** `sg13g2_DCNDiode` : 2 × `dantenna` 27,78 × 1,26 µm, PAD → substrat/IOVSS ; **DCP** `sg13g2_DCPDiode` : 2 × `dpantenna` 27,78 × 1,26 µm, PAD → IOVDD | IOVSS / IOVDD |
| Protection secondaire | `sg13g2_SecondaryProtection` (IHP, celle de `sg13g2_LevelDown` dans `sg13g2_IOPadIn`) : `rppd` 586,9 Ω (l 2 / w 1 µm) PAD → core ; `dantenna` 3,1 × 0,64 µm core → substrat ; `dpantenna` 4,98 × 0,64 µm core → plus ; prise `ptap1` minus | plus = IOVDD, minus = IOVSS |
| Trigger de Schmitt | `lvcmos12_schm_in` : XM1, XM2 (NMOS empilés), XM3, XM4 (PMOS empilés), XM5 et XM6 (réaction), tous `sg13_lv_*` 1 / 0,13 µm, ng 1 | VDD / VSS cœur |
| Inverseur de sortie | XM7 (NMOS), XM8 (PMOS) 1 / 0,13 µm → P2C | VDD / VSS cœur |

Tous les MOS sont LV (oxyde mince). La netlist garde des bornes VDDIO/VSSIO non connectées : tout le trigger est sur VDD/VSS cœur. Dans l'anneau, seule la protection secondaire (plus, minus) touche IOVDD/IOVSS.

## Bornes
D'après `MAG/LEF/MIPI_IOPadIn.lef`. Coordonnées en µm, origine en bas à gauche, le plot est en bas (y = 0) et le cœur en haut (y = 180).

| Borne | Direction LEF | Domaine | Plage d'accès (couche, position) |
|---|---|---|---|
| PAD | INOUT, USE SIGNAL | IO 1,2 V | stub x 5-75, y 0-3 de Metal3 à TopMetal2 (Metal2 x 3,91-75). Tronc Metal2 x 61,02-61,86, y 3-73,25 jusqu'à la protection secondaire |
| P2C | OUTPUT | cœur 1,2 V | Metal2 x 31,555-31,845, y 122,85-180 : sort au bord haut (label y 179-180, `core_port`) |
| VDD | INOUT, USE POWER | cœur 1,2 V | rail Metal3 y 160-178 ; Metal5/TopMetal1 y 140-158 ; Metal4 y 140-155,8 |
| VSS | INOUT, USE GROUND | masse cœur | rail Metal3 y 140-158 ; Metal5/TopMetal1 y 160-178 ; Metal4 y 162,2-178 |
| IOVDD | INOUT | IO 1,2 V (IOVDD_MIPI) | Metal3 à TopMetal1 y 66-91,5 et 93,5-119 ; TopMetal2 y 67,5-90 et 95-117,5 |
| IOVSS | INOUT | masse IO | Metal3 à TopMetal1 y 7-32,5 / 34,5-60 / 126-134 ; TopMetal2 y 8,5-31 / 36-58,5 / 127,5-132,5 |

`ANTENNADIFFAREA` du PAD : 140,01 µm². Les rails vont d'un bord à l'autre (x = 0 et 80) et s'aboutent aux cellules voisines.

## Taille
- Cellule : **80 × 180 µm** (LEF `SIZE 80.000 BY 180.000`), site `sg13g2_ioSite`, symétrie X Y R90.
- Le bond pad n'est pas dans la cellule (voir `MIPI_IOPadIOVss.md`, section Plot).

## Protection ESD
- Primaire : DCN et DCP, comme dans `sg13g2_IOPadIn` (tableau ci-dessus).
- Secondaire : `sg13g2_SecondaryProtection` placée en (60 ; 72). Les grilles du trigger ne voient le PAD qu'à travers les 587 Ω, bridés par les diodes vers IOVDD et vers le substrat.
- Écart avec IHP : dans `sg13g2_IOPadIn`, `plus` va à l'IOVDD 3,3 V. Ici, IOVDD vaut 1,2 V, comme le VDD qui alimente le trigger.
- Analyse ESD (chemins de décharge, tensions) : **n.m.** (aucun `signoff/esd_MIPI_IOPadIn.md`).

## Implantation
- **Zone composants** `RX_ZONE` x 18-78, y 66-138. Les diodes ESD sont en colonne à gauche (DCN x 0,15-13,58, y 6-42,4 ; DCP y 65-101,4).
- **Trigger** : placement et routage LP de `IOPadRX` (`rx_route_lp` de `ring_RX.tcl`). Les 4 NMOS sont en rangée à y 118 et les 4 PMOS à y 124, sur x 20-31,5. Nwell commun x 19,3-32,2, y 123,4-128,4, avec sa prise nsd. Les MOS n'ont pas de via vers Metal2 : Metal2 isolé < M2.d, comme dans la lib CML. Le signal out_HV passe en Metal1 dans le canal entre les rangées (y 121,7-122). VDD monte par un via v2 dans le rail Metal3 VDD (y 170), VSS par un via v2 dans le rail Metal3 VSS (y 150). Le trigger est alimenté par VDD/VSS cœur, comme dans la netlist.
- **Protection secondaire** en (60 ; 72), près du tronc PAD :
  - minus → IOVSS : Metal2 vers le bas, vias v2 dans le rail Metal3 IOVSS (y 59,4) ;
  - plus → IOVDD : languette Metal1 à gauche de l'anneau, vias empilés jusqu'au rail Metal3 IOVDD ;
  - core → grilles : montée en Metal2 (x 62,5-63,5) jusqu'à y 116,5, puis branche Metal2 horizontale (y 116,2-116,5) jusqu'à la colonne d'entrée du trigger (x 19,355).

## Vérification physique
- **DRC** KLayout d'IHP (`--no_density`), jeux main et `sg13g2_maximal` : **0 erreur**. Source : `MAG/drc/drc_MIPI_IOPadIn.log` (29/09 13:03, rapport dans `MAG/drc/run_in/`).
- **Extraction** Magic 8.3.683, refaite le 29/09 à partir de `MAG/drc/MIPI_IOPadIn.gds`, dans un dossier temporaire hors dépôt. Résultat :
  - 8 MOS 1 / 0,13 µm, connectés comme dans `lvcmos12_schm_in.sp` (XM1…XM8) ;
  - `sg13g2_SecondaryProtection` : rppd 2 / 1, dantenna 3,1 × 0,64, dpantenna 4,98 × 0,64 ;
  - DCN et DCP : 2 × 27,78 × 1,26 chacune.
  
  Comparaison faite en relisant les deux netlists, sans LVS netgen. Magic signale `Ports "VSS" and "IOVSS" are electrically shorted` : les deux sont reliés au substrat par des prises ptap, comme dans les cellules IHP.
- Livraison : la cellule est dans `NOT_DELIVERED` (`magcilib`). Elle n'est **pas** dans `COLLATERALS/GDS/MIPI_ring.gds` ni dans `LEF/MIPI_ring.lef`.

## Performances
Banc de spec `LVCMOS12/lvcmos12_schm_in/tb/schmitt_bench.tcl`, relancé le 29/09 à **tt_typ_25**. Conditions : VDD = VDDIO = 1,2 V, C_LOAD 24 fF, T_IN 0,2 ns, F_REF 10 MHz. Le résultat est identique au rapport du 27/09 (`LVCMOS12/lvcmos12_schm_in/COLLATERALS/signoff/rapport_lvcmos12_schm_in_tt_typ_25_v1p20.txt`, même netlist, md5 7c56b391…). Les bornes viennent de la spec `specification/specs/lvcmos12_schmitt_trigger_spec.tcl` (BROUILLON).
**Le DUT est le trigger seul** : sans la protection secondaire, sans DCN/DCP, sans parasites de dessin.

| id | Grandeur | tt_typ_25 | Verdict |
|---|---|---|---|
| S1a | VT_PLUS | 0,768 V | PASS |
| S1b | VT_MINUS | 0,428 V | PASS |
| S2 | VH | 0,340 V | PASS |
| S3 | V_CENTER | 2,2 mV | PASS |
| S4 | N_TRANS | 1 | PASS |
| S5a / S5b | VOH / VOL (P2C) | 1,181 V / 7,0 mV | PASS |
| S5c | V_OUT_MAX | 1,219 V | PASS |
| S6a / S6b | T_PLH / T_PHL (PAD → P2C, 24 fF) | 0,191 ns / 0,208 ns | PASS |
| S6c | T_R_F | 0,173 ns | sans borne |
| S7 | I_STAT (entrée au milieu de la fenêtre) | **17,2 µA** | **FAIL** (max 10 µA) |
| S7b | I_PEAK | 63,8 µA | sans borne |
| S7c | C_PD | 23,3 fF | sans borne |
| — | I_Q (repos) | 0,175 nA | — |
| S8 | C_IN du trigger (bas / haut) | 5,3 fF / 6,7 fF | sans borne |

Campagne complète (27 corners, 3 VDD), tableau min/max par corner : `LVCMOS12/lvcmos12_schm_in/COLLATERALS/DOC/lvcmos12_schmitt_trigger_sim.md` (16/09, même md5 de netlist).

Non mesuré :
- capacité vue du PAD (diodes DCN/DCP et protection secondaire comprises) : **n.m.** ;
- fuite du PAD : **n.m.** ;
- délai PAD → P2C à travers les 587 Ω : **n.m.** ;
- courant max DC du plot (électromigration) : **n.m.** (`em_estimate.py` non lancé sur cette cellule) ;
- post-layout : **n.m.**

## Points ouverts
- **FAIL S7** : I_STAT = 17,2 µA à tt_typ_25 (max 10 µA). C'est aussi le FAIL de la ligne LVCMOS12 RX de `BOM/BOM.md`. Sur la campagne 27 corners, la datasheet du 16/09 marque aussi FAIL S1a, S4, S5a (à 1,08 V) et S5c (à 1,32 V).
- Spec `lvcmos12_schmitt_trigger_spec.tcl` au statut BROUILLON.
- Aucun banc au niveau du pad (trigger + protection secondaire + diodes) ; pas de post-layout.
- Pas d'activation (IE), pas de pull-up ni de pull-down.
- Liberty de l'anneau : `COLLATERALS/LIB/MIPI_io_<corner>.lib` est en cours de production par un autre agent. Il n'existe aujourd'hui que `MIPI_ring_dummy.lib`. Le trigger seul a ses `.lib` vernier dans `LVCMOS12/lvcmos12_schm_in/COLLATERALS/LIB/`.
- Pas encore livrée dans le bundle `MIPI_ring` (`NOT_DELIVERED`).
- Le GDS vérifié (13:03) est antérieur au .mag et au LEF (13:26) : il faut repasser le DRC sur le dessin courant avant livraison.
