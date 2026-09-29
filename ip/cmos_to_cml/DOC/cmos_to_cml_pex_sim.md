# cmos_to_cml -- resultats de simulation, arch cmos_to_cml_pex

**SIMULATION** -- pas une specification. Genere le 2026-09-27 par datasheet-sim.tcl.
Netlist du DUT : `cmos_to_cml_pex.spice`, md5 `4cbc48da57f83826585a3f02256a507b`.
Spec de reference : `cmos_to_cml_spec.tcl` (decisions de Lionel 2026-09-27 : frontiere CMOS -> CML a 1 Gb/s ; CML et CMOS dans le domaine coeur). Corners : tt_typ_25_v1p08, tt_typ_m40_v1p08, tt_typ_125_v1p08, ss_wcs_25_v1p08, ss_wcs_m40_v1p08, ss_wcs_125_v1p08, ff_bcs_25_v1p08, ff_bcs_m40_v1p08, ff_bcs_125_v1p08, tt_typ_25_v1p20, tt_typ_m40_v1p20, tt_typ_125_v1p20, ss_wcs_25_v1p20, ss_wcs_m40_v1p20, ss_wcs_125_v1p20, ff_bcs_25_v1p20, ff_bcs_m40_v1p20, ff_bcs_125_v1p20, tt_typ_25_v1p32, tt_typ_m40_v1p32, tt_typ_125_v1p32, ss_wcs_25_v1p32, ss_wcs_m40_v1p32, ss_wcs_125_v1p32, ff_bcs_25_v1p32, ff_bcs_m40_v1p32, ff_bcs_125_v1p32.
min / max = pire cas sur ces corners (corner indique) ; typ = tt_typ_25_v1p20 ; spec = bornes de la spec, pour le verdict. n.m. = non mesure : la spec attend une valeur, le banc ne l'a pas fournie (cle absente ou NaN) ; ce n'est pas un verdict.
Puis par temperature : min / max des corners du groupe, typ = corner tt du groupe a VDD nominal s'il existe.

## Conditions par corner

**VDD balaye 1.08, 1.2, 1.32 V (spec CML0 1.08 ... 1.32 V).**

| corner | MOS | R | T (C) | VDD (V) | VDDIO (V) | fichier de mesures |
|---|---|---|---|---|---|---|
| tt_typ_25_v1p08 | tt | typ | 25 | 1.08 | - | `mesures_cmos_to_cml_pex_tt_typ_25.tcl` |
| tt_typ_m40_v1p08 | tt | typ | -40 | 1.08 | - | `mesures_cmos_to_cml_pex_tt_typ_m40.tcl` |
| tt_typ_125_v1p08 | tt | typ | 125 | 1.08 | - | `mesures_cmos_to_cml_pex_tt_typ_125.tcl` |
| ss_wcs_25_v1p08 | ss | wcs | 25 | 1.08 | - | `mesures_cmos_to_cml_pex_ss_wcs_25.tcl` |
| ss_wcs_m40_v1p08 | ss | wcs | -40 | 1.08 | - | `mesures_cmos_to_cml_pex_ss_wcs_m40.tcl` |
| ss_wcs_125_v1p08 | ss | wcs | 125 | 1.08 | - | `mesures_cmos_to_cml_pex_ss_wcs_125.tcl` |
| ff_bcs_25_v1p08 | ff | bcs | 25 | 1.08 | - | `mesures_cmos_to_cml_pex_ff_bcs_25.tcl` |
| ff_bcs_m40_v1p08 | ff | bcs | -40 | 1.08 | - | `mesures_cmos_to_cml_pex_ff_bcs_m40.tcl` |
| ff_bcs_125_v1p08 | ff | bcs | 125 | 1.08 | - | `mesures_cmos_to_cml_pex_ff_bcs_125.tcl` |
| tt_typ_25_v1p20 | tt | typ | 25 | 1.2 | - | `mesures_cmos_to_cml_pex_tt_typ_25.tcl` |
| tt_typ_m40_v1p20 | tt | typ | -40 | 1.2 | - | `mesures_cmos_to_cml_pex_tt_typ_m40.tcl` |
| tt_typ_125_v1p20 | tt | typ | 125 | 1.2 | - | `mesures_cmos_to_cml_pex_tt_typ_125.tcl` |
| ss_wcs_25_v1p20 | ss | wcs | 25 | 1.2 | - | `mesures_cmos_to_cml_pex_ss_wcs_25.tcl` |
| ss_wcs_m40_v1p20 | ss | wcs | -40 | 1.2 | - | `mesures_cmos_to_cml_pex_ss_wcs_m40.tcl` |
| ss_wcs_125_v1p20 | ss | wcs | 125 | 1.2 | - | `mesures_cmos_to_cml_pex_ss_wcs_125.tcl` |
| ff_bcs_25_v1p20 | ff | bcs | 25 | 1.2 | - | `mesures_cmos_to_cml_pex_ff_bcs_25.tcl` |
| ff_bcs_m40_v1p20 | ff | bcs | -40 | 1.2 | - | `mesures_cmos_to_cml_pex_ff_bcs_m40.tcl` |
| ff_bcs_125_v1p20 | ff | bcs | 125 | 1.2 | - | `mesures_cmos_to_cml_pex_ff_bcs_125.tcl` |
| tt_typ_25_v1p32 | tt | typ | 25 | 1.32 | - | `mesures_cmos_to_cml_pex_tt_typ_25.tcl` |
| tt_typ_m40_v1p32 | tt | typ | -40 | 1.32 | - | `mesures_cmos_to_cml_pex_tt_typ_m40.tcl` |
| tt_typ_125_v1p32 | tt | typ | 125 | 1.32 | - | `mesures_cmos_to_cml_pex_tt_typ_125.tcl` |
| ss_wcs_25_v1p32 | ss | wcs | 25 | 1.32 | - | `mesures_cmos_to_cml_pex_ss_wcs_25.tcl` |
| ss_wcs_m40_v1p32 | ss | wcs | -40 | 1.32 | - | `mesures_cmos_to_cml_pex_ss_wcs_m40.tcl` |
| ss_wcs_125_v1p32 | ss | wcs | 125 | 1.32 | - | `mesures_cmos_to_cml_pex_ss_wcs_125.tcl` |
| ff_bcs_25_v1p32 | ff | bcs | 25 | 1.32 | - | `mesures_cmos_to_cml_pex_ff_bcs_25.tcl` |
| ff_bcs_m40_v1p32 | ff | bcs | -40 | 1.32 | - | `mesures_cmos_to_cml_pex_ff_bcs_m40.tcl` |
| ff_bcs_125_v1p32 | ff | bcs | 125 | 1.32 | - | `mesures_cmos_to_cml_pex_ff_bcs_125.tcl` |

## Sorties (OUTP, OUTN)

| id | Parametre | Sym | Min | Typ | Max | Min 25 C | Typ 25 C | Max 25 C | Min -40 C | Typ -40 C | Max -40 C | Min 125 C | Typ 125 C | Max 125 C | Unite | Spec | Verdict |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| CML8 | Niveau haut de sortie | `VOH` | 1.08 <sub>tt_typ_25_v1p08</sub> | 1.2 | 1.32 <sub>tt_typ_25_v1p32</sub> | 1.08 | 1.2 | 1.32 | 1.08 | 1.2 | 1.32 | 1.08 | 1.2 | 1.32 | V | - | sans borne |
| CML9 | Niveau bas de sortie | `VOL` | 0.787 <sub>ss_wcs_125_v1p08</sub> | 0.924 | 1.06 <sub>ff_bcs_m40_v1p32</sub> | 0.808 | 0.924 | 1.05 | 0.816 | 0.936 | 1.06 | 0.787 | 0.901 | 1.02 | V | >= 0.75 | PASS |
| CML10 | Mode commun de sortie | `VCM_OUT` | 0.934 <sub>ss_wcs_125_v1p08</sub> | 1.06 | 1.19 <sub>ff_bcs_m40_v1p32</sub> | 0.944 | 1.06 | 1.18 | 0.948 | 1.07 | 1.19 | 0.934 | 1.05 | 1.17 | V | 0.95 ... 1.15 | FAIL ff_bcs_125_v1p08 ff_bcs_125_v1p32 ff_bcs_25_v1p32 ff_bcs_m40_v1p32 ss_wcs_125_v1p08 ss_wcs_125_v1p32 ss_wcs_25_v1p08 ss_wcs_25_v1p32 ss_wcs_m40_v1p08 ss_wcs_m40_v1p32 tt_typ_125_v1p08 tt_typ_125_v1p32 tt_typ_25_v1p32 tt_typ_m40_v1p32 |
| CML11 | Swing differentiel de sortie a la frequence cible | `VSW_OUT` | 0.273 <sub>ff_bcs_m40_v1p08</sub> | 0.323 | 0.382 <sub>ss_wcs_125_v1p32</sub> | 0.277 | 0.323 | 0.37 | 0.273 | 0.318 | 0.367 | 0.294 | 0.337 | 0.382 | V | >= 0.25 | PASS |

## Vitesse

| id | Parametre | Sym | Min | Typ | Max | Min 25 C | Typ 25 C | Max 25 C | Min -40 C | Typ -40 C | Max -40 C | Min 125 C | Typ 125 C | Max 125 C | Unite | Spec | Verdict |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| CMLI12 | Delai de propagation | `T_P` | 0.0654 <sub>ff_bcs_125_v1p32</sub> | 0.0771 | 0.0926 <sub>ss_wcs_m40_v1p08</sub> | 0.066 | 0.0771 | 0.0913 | 0.0671 | 0.0784 | 0.0926 | 0.0654 | 0.0761 | 0.0899 | UI | <= 0.5 | PASS |
| CMLI13 | Decalage entre OUTP et OUTN | `DT_PN` | 20.8 <sub>ff_bcs_125_v1p32</sub> | 24 | 28.6 <sub>ss_wcs_m40_v1p08</sub> | 21.1 | 24 | 28 | 21.5 | 24.5 | 28.6 | 20.8 | 23.3 | 26.8 | ps | <= 50 | PASS |
| CMLI14 | Distorsion de rapport cyclique | `D_DUTY` | 0.448 <sub>ss_wcs_125_v1p08</sub> | 0.585 | 0.763 <sub>ss_wcs_m40_v1p32</sub> | 0.481 | 0.585 | 0.681 | 0.553 | 0.661 | 0.763 | 0.448 | 0.53 | 0.604 | % | <= 5 | PASS |

