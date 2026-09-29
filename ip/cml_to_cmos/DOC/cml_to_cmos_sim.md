# cml_to_cmos -- resultats de simulation, arch cml_to_cmos

**SIMULATION** -- pas une specification. Genere le 2026-09-27 par datasheet-sim.tcl.
Netlist du DUT : `cml_to_cmos.spice`, md5 `0dec5e85f985706f003c37e045cb63a0`.
**ARCHIVE EN FORCE : verdict global FAIL (CML3), archivee malgre les FAIL (make collaterals FORCE=1).**
Spec de reference : `cml_to_cmos_spec.tcl` (decisions de Lionel 2026-09-27 : frontiere CML -> CMOS apres division par 4, 1 Gb/s ; CML et CMOS dans le domaine coeur). Corners : tt_typ_25_v1p08, tt_typ_m40_v1p08, tt_typ_125_v1p08, ss_wcs_25_v1p08, ss_wcs_m40_v1p08, ss_wcs_125_v1p08, ff_bcs_25_v1p08, ff_bcs_m40_v1p08, ff_bcs_125_v1p08, tt_typ_25_v1p20, tt_typ_m40_v1p20, tt_typ_125_v1p20, ss_wcs_25_v1p20, ss_wcs_m40_v1p20, ss_wcs_125_v1p20, ff_bcs_25_v1p20, ff_bcs_m40_v1p20, ff_bcs_125_v1p20, tt_typ_25_v1p32, tt_typ_m40_v1p32, tt_typ_125_v1p32, ss_wcs_25_v1p32, ss_wcs_m40_v1p32, ss_wcs_125_v1p32, ff_bcs_25_v1p32, ff_bcs_m40_v1p32, ff_bcs_125_v1p32.
min / max = pire cas sur ces corners (corner indique) ; typ = tt_typ_25_v1p20 ; spec = bornes de la spec, pour le verdict. n.m. = non mesure : la spec attend une valeur, le banc ne l'a pas fournie (cle absente ou NaN) ; ce n'est pas un verdict.
Puis par temperature : min / max des corners du groupe, typ = corner tt du groupe a VDD nominal s'il existe.

## Conditions par corner

**VDD balaye 1.08, 1.2, 1.32 V (spec CML0 1.08 ... 1.32 V).**

| corner | MOS | R | T (C) | VDD (V) | VDDIO (V) | fichier de mesures |
|---|---|---|---|---|---|---|
| tt_typ_25_v1p08 | tt | typ | 25 | 1.08 | - | `mesures_cml_to_cmos_tt_typ_25.tcl` |
| tt_typ_m40_v1p08 | tt | typ | -40 | 1.08 | - | `mesures_cml_to_cmos_tt_typ_m40.tcl` |
| tt_typ_125_v1p08 | tt | typ | 125 | 1.08 | - | `mesures_cml_to_cmos_tt_typ_125.tcl` |
| ss_wcs_25_v1p08 | ss | wcs | 25 | 1.08 | - | `mesures_cml_to_cmos_ss_wcs_25.tcl` |
| ss_wcs_m40_v1p08 | ss | wcs | -40 | 1.08 | - | `mesures_cml_to_cmos_ss_wcs_m40.tcl` |
| ss_wcs_125_v1p08 | ss | wcs | 125 | 1.08 | - | `mesures_cml_to_cmos_ss_wcs_125.tcl` |
| ff_bcs_25_v1p08 | ff | bcs | 25 | 1.08 | - | `mesures_cml_to_cmos_ff_bcs_25.tcl` |
| ff_bcs_m40_v1p08 | ff | bcs | -40 | 1.08 | - | `mesures_cml_to_cmos_ff_bcs_m40.tcl` |
| ff_bcs_125_v1p08 | ff | bcs | 125 | 1.08 | - | `mesures_cml_to_cmos_ff_bcs_125.tcl` |
| tt_typ_25_v1p20 | tt | typ | 25 | 1.2 | - | `mesures_cml_to_cmos_tt_typ_25.tcl` |
| tt_typ_m40_v1p20 | tt | typ | -40 | 1.2 | - | `mesures_cml_to_cmos_tt_typ_m40.tcl` |
| tt_typ_125_v1p20 | tt | typ | 125 | 1.2 | - | `mesures_cml_to_cmos_tt_typ_125.tcl` |
| ss_wcs_25_v1p20 | ss | wcs | 25 | 1.2 | - | `mesures_cml_to_cmos_ss_wcs_25.tcl` |
| ss_wcs_m40_v1p20 | ss | wcs | -40 | 1.2 | - | `mesures_cml_to_cmos_ss_wcs_m40.tcl` |
| ss_wcs_125_v1p20 | ss | wcs | 125 | 1.2 | - | `mesures_cml_to_cmos_ss_wcs_125.tcl` |
| ff_bcs_25_v1p20 | ff | bcs | 25 | 1.2 | - | `mesures_cml_to_cmos_ff_bcs_25.tcl` |
| ff_bcs_m40_v1p20 | ff | bcs | -40 | 1.2 | - | `mesures_cml_to_cmos_ff_bcs_m40.tcl` |
| ff_bcs_125_v1p20 | ff | bcs | 125 | 1.2 | - | `mesures_cml_to_cmos_ff_bcs_125.tcl` |
| tt_typ_25_v1p32 | tt | typ | 25 | 1.32 | - | `mesures_cml_to_cmos_tt_typ_25.tcl` |
| tt_typ_m40_v1p32 | tt | typ | -40 | 1.32 | - | `mesures_cml_to_cmos_tt_typ_m40.tcl` |
| tt_typ_125_v1p32 | tt | typ | 125 | 1.32 | - | `mesures_cml_to_cmos_tt_typ_125.tcl` |
| ss_wcs_25_v1p32 | ss | wcs | 25 | 1.32 | - | `mesures_cml_to_cmos_ss_wcs_25.tcl` |
| ss_wcs_m40_v1p32 | ss | wcs | -40 | 1.32 | - | `mesures_cml_to_cmos_ss_wcs_m40.tcl` |
| ss_wcs_125_v1p32 | ss | wcs | 125 | 1.32 | - | `mesures_cml_to_cmos_ss_wcs_125.tcl` |
| ff_bcs_25_v1p32 | ff | bcs | 25 | 1.32 | - | `mesures_cml_to_cmos_ff_bcs_25.tcl` |
| ff_bcs_m40_v1p32 | ff | bcs | -40 | 1.32 | - | `mesures_cml_to_cmos_ff_bcs_m40.tcl` |
| ff_bcs_125_v1p32 | ff | bcs | 125 | 1.32 | - | `mesures_cml_to_cmos_ff_bcs_125.tcl` |

## Entree donnees (INP, INN)

| id | Parametre | Sym | Min | Typ | Max | Min 25 C | Typ 25 C | Max 25 C | Min -40 C | Typ -40 C | Max -40 C | Min 125 C | Typ 125 C | Max 125 C | Unite | Spec | Verdict |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| CML1a | Mode commun d'entree, borne basse acceptee | `VCM_IN_LOW` | - <sub></sub> | - | - <sub></sub> | - | - | - | - | - | - | - | - | - | V | <= 0.85 | n.m. |
| CML1b | Mode commun d'entree, borne haute acceptee | `VCM_IN_HIGH` | - <sub></sub> | - | - <sub></sub> | - | - | - | - | - | - | - | - | - | V | >= 1.15 | n.m. |
| CML2 | Swing differentiel d'entree, minimum commute | `VSW_IN` | - <sub></sub> | - | - <sub></sub> | - | - | - | - | - | - | - | - | - | V | <= 0.25 | n.m. |
| CML3 | Capacite d'entree, par broche | `C_IN` | 14.9 <sub>ss_wcs_125_v1p08</sub> | 16.2 | 17.3 <sub>ff_bcs_m40_v1p32</sub> | 15.9 | 16.2 | 16.6 | 16.5 | 16.9 | 17.3 | 14.9 | 15.2 | 15.5 | fF | <= 9 | FAIL ff_bcs_125_v1p08 ff_bcs_125_v1p20 ff_bcs_125_v1p32 ff_bcs_25_v1p08 ff_bcs_25_v1p20 ff_bcs_25_v1p32 ff_bcs_m40_v1p08 ff_bcs_m40_v1p20 ff_bcs_m40_v1p32 ss_wcs_125_v1p08 ss_wcs_125_v1p20 ss_wcs_125_v1p32 ss_wcs_25_v1p08 ss_wcs_25_v1p20 ss_wcs_25_v1p32 ss_wcs_m40_v1p08 ss_wcs_m40_v1p20 ss_wcs_m40_v1p32 tt_typ_125_v1p08 tt_typ_125_v1p20 tt_typ_125_v1p32 tt_typ_25_v1p08 tt_typ_25_v1p20 tt_typ_25_v1p32 tt_typ_m40_v1p08 tt_typ_m40_v1p20 tt_typ_m40_v1p32 |

## Vitesse

| id | Parametre | Sym | Min | Typ | Max | Min 25 C | Typ 25 C | Max 25 C | Min -40 C | Typ -40 C | Max -40 C | Min 125 C | Typ 125 C | Max 125 C | Unite | Spec | Verdict |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| CMLO12 | Delai de propagation | `T_P` | 0.16 <sub>ff_bcs_m40_v1p32</sub> | 0.201 | 0.304 <sub>ss_wcs_m40_v1p08</sub> | 0.163 | 0.201 | 0.296 | 0.16 | 0.205 | 0.304 | 0.173 | 0.207 | 0.286 | UI | <= 0.5 | PASS |
| CMLO14 | Distorsion de rapport cyclique | `D_DUTY` | 0.00402 <sub>tt_typ_25_v1p20</sub> | 0.00402 | 1.66 <sub>ff_bcs_125_v1p32</sub> | 0.00402 | 0.00402 | 1.29 | 0.0872 | 0.26 | 1.61 | 0.0767 | 0.479 | 1.66 | % | <= 2 | PASS |

