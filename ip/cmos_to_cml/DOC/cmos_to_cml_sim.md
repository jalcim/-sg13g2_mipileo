# cmos_to_cml -- resultats de simulation, arch cmos_to_cml

**SIMULATION** -- pas une specification. Genere le 2026-09-27 par datasheet-sim.tcl.
Netlist du DUT : `cmos_to_cml.spice`, md5 `3b66b9857690e71288850bc1ab094f78`.
**ARCHIVE EN FORCE : verdict global FAIL (CML10), archivee malgre les FAIL (make collaterals FORCE=1).**
Spec de reference : `cmos_to_cml_spec.tcl` (decisions de Lionel 2026-09-27 : frontiere CMOS -> CML a 1 Gb/s ; CML et CMOS dans le domaine coeur). Corners : tt_typ_25_v1p08, tt_typ_m40_v1p08, tt_typ_125_v1p08, ss_wcs_25_v1p08, ss_wcs_m40_v1p08, ss_wcs_125_v1p08, ff_bcs_25_v1p08, ff_bcs_m40_v1p08, ff_bcs_125_v1p08, tt_typ_25_v1p20, tt_typ_m40_v1p20, tt_typ_125_v1p20, ss_wcs_25_v1p20, ss_wcs_m40_v1p20, ss_wcs_125_v1p20, ff_bcs_25_v1p20, ff_bcs_m40_v1p20, ff_bcs_125_v1p20, tt_typ_25_v1p32, tt_typ_m40_v1p32, tt_typ_125_v1p32, ss_wcs_25_v1p32, ss_wcs_m40_v1p32, ss_wcs_125_v1p32, ff_bcs_25_v1p32, ff_bcs_m40_v1p32, ff_bcs_125_v1p32.
min / max = pire cas sur ces corners (corner indique) ; typ = tt_typ_25_v1p20 ; spec = bornes de la spec, pour le verdict. n.m. = non mesure : la spec attend une valeur, le banc ne l'a pas fournie (cle absente ou NaN) ; ce n'est pas un verdict.
Puis par temperature : min / max des corners du groupe, typ = corner tt du groupe a VDD nominal s'il existe.

## Conditions par corner

**VDD balaye 1.08, 1.2, 1.32 V (spec CML0 1.08 ... 1.32 V).**

| corner | MOS | R | T (C) | VDD (V) | VDDIO (V) | fichier de mesures |
|---|---|---|---|---|---|---|
| tt_typ_25_v1p08 | tt | typ | 25 | 1.08 | - | `mesures_cmos_to_cml_tt_typ_25.tcl` |
| tt_typ_m40_v1p08 | tt | typ | -40 | 1.08 | - | `mesures_cmos_to_cml_tt_typ_m40.tcl` |
| tt_typ_125_v1p08 | tt | typ | 125 | 1.08 | - | `mesures_cmos_to_cml_tt_typ_125.tcl` |
| ss_wcs_25_v1p08 | ss | wcs | 25 | 1.08 | - | `mesures_cmos_to_cml_ss_wcs_25.tcl` |
| ss_wcs_m40_v1p08 | ss | wcs | -40 | 1.08 | - | `mesures_cmos_to_cml_ss_wcs_m40.tcl` |
| ss_wcs_125_v1p08 | ss | wcs | 125 | 1.08 | - | `mesures_cmos_to_cml_ss_wcs_125.tcl` |
| ff_bcs_25_v1p08 | ff | bcs | 25 | 1.08 | - | `mesures_cmos_to_cml_ff_bcs_25.tcl` |
| ff_bcs_m40_v1p08 | ff | bcs | -40 | 1.08 | - | `mesures_cmos_to_cml_ff_bcs_m40.tcl` |
| ff_bcs_125_v1p08 | ff | bcs | 125 | 1.08 | - | `mesures_cmos_to_cml_ff_bcs_125.tcl` |
| tt_typ_25_v1p20 | tt | typ | 25 | 1.2 | - | `mesures_cmos_to_cml_tt_typ_25.tcl` |
| tt_typ_m40_v1p20 | tt | typ | -40 | 1.2 | - | `mesures_cmos_to_cml_tt_typ_m40.tcl` |
| tt_typ_125_v1p20 | tt | typ | 125 | 1.2 | - | `mesures_cmos_to_cml_tt_typ_125.tcl` |
| ss_wcs_25_v1p20 | ss | wcs | 25 | 1.2 | - | `mesures_cmos_to_cml_ss_wcs_25.tcl` |
| ss_wcs_m40_v1p20 | ss | wcs | -40 | 1.2 | - | `mesures_cmos_to_cml_ss_wcs_m40.tcl` |
| ss_wcs_125_v1p20 | ss | wcs | 125 | 1.2 | - | `mesures_cmos_to_cml_ss_wcs_125.tcl` |
| ff_bcs_25_v1p20 | ff | bcs | 25 | 1.2 | - | `mesures_cmos_to_cml_ff_bcs_25.tcl` |
| ff_bcs_m40_v1p20 | ff | bcs | -40 | 1.2 | - | `mesures_cmos_to_cml_ff_bcs_m40.tcl` |
| ff_bcs_125_v1p20 | ff | bcs | 125 | 1.2 | - | `mesures_cmos_to_cml_ff_bcs_125.tcl` |
| tt_typ_25_v1p32 | tt | typ | 25 | 1.32 | - | `mesures_cmos_to_cml_tt_typ_25.tcl` |
| tt_typ_m40_v1p32 | tt | typ | -40 | 1.32 | - | `mesures_cmos_to_cml_tt_typ_m40.tcl` |
| tt_typ_125_v1p32 | tt | typ | 125 | 1.32 | - | `mesures_cmos_to_cml_tt_typ_125.tcl` |
| ss_wcs_25_v1p32 | ss | wcs | 25 | 1.32 | - | `mesures_cmos_to_cml_ss_wcs_25.tcl` |
| ss_wcs_m40_v1p32 | ss | wcs | -40 | 1.32 | - | `mesures_cmos_to_cml_ss_wcs_m40.tcl` |
| ss_wcs_125_v1p32 | ss | wcs | 125 | 1.32 | - | `mesures_cmos_to_cml_ss_wcs_125.tcl` |
| ff_bcs_25_v1p32 | ff | bcs | 25 | 1.32 | - | `mesures_cmos_to_cml_ff_bcs_25.tcl` |
| ff_bcs_m40_v1p32 | ff | bcs | -40 | 1.32 | - | `mesures_cmos_to_cml_ff_bcs_m40.tcl` |
| ff_bcs_125_v1p32 | ff | bcs | 125 | 1.32 | - | `mesures_cmos_to_cml_ff_bcs_125.tcl` |

## Sorties (OUTP, OUTN)

| id | Parametre | Sym | Min | Typ | Max | Min 25 C | Typ 25 C | Max 25 C | Min -40 C | Typ -40 C | Max -40 C | Min 125 C | Typ 125 C | Max 125 C | Unite | Spec | Verdict |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| CML8 | Niveau haut de sortie | `VOH` | 1.08 <sub>tt_typ_25_v1p08</sub> | 1.2 | 1.32 <sub>tt_typ_25_v1p32</sub> | 1.08 | 1.2 | 1.32 | 1.08 | 1.2 | 1.32 | 1.08 | 1.2 | 1.32 | V | - | sans borne |
| CML9 | Niveau bas de sortie | `VOL` | 0.783 <sub>ss_wcs_125_v1p08</sub> | 0.92 | 1.05 <sub>ff_bcs_m40_v1p32</sub> | 0.803 | 0.92 | 1.04 | 0.811 | 0.931 | 1.05 | 0.783 | 0.898 | 1.02 | V | >= 0.75 | PASS |
| CML10 | Mode commun de sortie | `VCM_OUT` | 0.932 <sub>ss_wcs_125_v1p08</sub> | 1.06 | 1.19 <sub>ff_bcs_m40_v1p32</sub> | 0.941 | 1.06 | 1.18 | 0.945 | 1.07 | 1.19 | 0.932 | 1.05 | 1.17 | V | 0.95 ... 1.15 | FAIL ff_bcs_125_v1p08 ff_bcs_125_v1p32 ff_bcs_25_v1p32 ff_bcs_m40_v1p32 ss_wcs_125_v1p08 ss_wcs_25_v1p08 ss_wcs_25_v1p32 ss_wcs_m40_v1p08 ss_wcs_m40_v1p32 tt_typ_125_v1p08 tt_typ_125_v1p32 tt_typ_25_v1p08 tt_typ_25_v1p32 tt_typ_m40_v1p32 |
| CML11 | Swing differentiel de sortie a la frequence cible | `VSW_OUT` | 0.262 <sub>ff_bcs_m40_v1p08</sub> | 0.31 | 0.371 <sub>ss_wcs_125_v1p32</sub> | 0.27 | 0.31 | 0.353 | 0.262 | 0.302 | 0.345 | 0.287 | 0.329 | 0.371 | V | >= 0.25 | PASS |

## Vitesse

| id | Parametre | Sym | Min | Typ | Max | Min 25 C | Typ 25 C | Max 25 C | Min -40 C | Typ -40 C | Max -40 C | Min 125 C | Typ 125 C | Max 125 C | Unite | Spec | Verdict |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| CMLI12 | Delai de propagation | `T_P` | 0.0507 <sub>ff_bcs_125_v1p32</sub> | 0.0608 | 0.075 <sub>ss_wcs_m40_v1p08</sub> | 0.0511 | 0.0608 | 0.0735 | 0.052 | 0.062 | 0.075 | 0.0507 | 0.0598 | 0.0719 | UI | <= 0.5 | PASS |
| CMLI13 | Decalage entre OUTP et OUTN | `DT_PN` | 14.1 <sub>ff_bcs_125_v1p32</sub> | 16.3 | 22.3 <sub>ss_wcs_m40_v1p08</sub> | 14.5 | 16.3 | 22 | 14.9 | 16.7 | 22.3 | 14.1 | 15.7 | 20.7 | ps | <= 50 | PASS |
| CMLI14 | Distorsion de rapport cyclique | `D_DUTY` | 0.484 <sub>ff_bcs_125_v1p32</sub> | 0.59 | 0.774 <sub>ss_wcs_m40_v1p32</sub> | 0.511 | 0.59 | 0.695 | 0.556 | 0.662 | 0.774 | 0.484 | 0.536 | 0.62 | % | <= 5 | PASS |

