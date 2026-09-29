# Signoff de la macro sr16_rx4 (GDS/sr16_rx4.gds)

Construit le 29/09/2026 sur le serveur (Caelum `30488f9`, toolchain du devshell nix `cd28732`), branche `caelum`
(HEAD `02f57204`), par `make gds MACRO=CML_SR/SR16_RX4` (script `../../SR16_RX4.py`, routeur `3_digital/routage_cml.py`
et `3_digital/outils_caelum.py` NON modifiés). GDS sha1 `5f4aa8865b4a1db59b4e9deba5aa1e8042b26027`, identique au
`final/gds` des deux runs du flot : DRC KLayout `work/flows/runs/drc_20260929_113857_1`, macro
`work/flows/runs/macro_20260929_113902` (locaux). La macro mono-lane `sr16_rx` (`../../../SR16_RX/`) n'est pas touchée.

## La macro
- Fonction : le golden `../HDL/sr16_mot.vhd` (copie de `SR16_RX/COLLATERALS/HDL/sr16_mot.vhd`, golden du 28/09 de
  Lionel), entité `SR16` avec **N = 4** : un `DIV4` (Johnson /4 m0 s0 m1 s1, EN_A = m0./m1, EN_B = s0./s1, CLK_W = /m1)
  et quatre `SERDES16` (deux chaînes de 8 latchs + 8 latchs de tenue sur CK.EN_A et /CK.EN_B, portes DANS la lane).
  MOT(8p+7..8p) = mot de la lane p, tenu 4 périodes de CK, MOT(8p) = bit reçu le premier ; CLK_W = CK / 4 commun ;
  des 0xB8 émis ensemble tombent au même rang sur les 4 lanes (même /4). Pas de remise à zéro.
- 328 instances (noms : `../DEF/sr16_rx4.def`), dont 133 actives : 9 `hs_to_clk` (2 par lane + XCKJ), 100
  `cml_tlatch` (64 de chaîne, 32 de tenue, 4 Johnson), 10 `cml_drvb`, 10 `cml_gate2`, 4 `cml_drv` ; 195 intercalaires
  de 1,92 µm (`interco_bi`, `stub_bi`, `interco_down`, `HSCLK_IN_1/2`, `interco_h`, `interco_ck`, `vide`).
  Cadre 189/4 : **190,08 x 313,04 µm** (14 rangées de 22,36), 59 501 µm².
- Quatorze rangées, de bas en haut (m = miroir) :

| Rangée | y (µm) | Contenu | Largeur |
|---|---|---|---|
| 1 (m) A0, 2 B0 | 0..44,72 | chaînes de la lane 0 : XHSc0 -> XHHc0 (interco_h) -> XCKc0 -> XDc0 -> (Xc0_i + bi/stub) x 8 | 176,56 |
| 3 (m) H0 | 44,72..67,08 | tenue lane 0 : XGGA0 (CK.en_a) -> XDGA0 -> XHA0_3..0 (interco_ck entre deux) -> XV0 (vide) -> XGGB0 (/CK.en_b) -> XDGB0 -> XHB0_3..0 | 190,08 |
| 4 H1 | 67,08..89,44 | tenue lane 1 (même rangée) | 190,08 |
| 5 (m) A1, 6 B1 | 89,44..134,16 | chaînes de la lane 1 | 176,56 |
| 7 (m) D1 | 134,16..156,52 | XDEA (/m1) -> XGEA (en_a) -> XEA0 (cml_drv) -> 9 vides -> XCKJ -> (interco_h -> XJi) x 4 (m0 s0 m1 s1) | 168,88 |
| 8 D2 | 156,52..178,88 | XDEB (/s1) -> XGEB (en_b) -> XEB0 -> vide -> XEA1 -> vide -> XEB1 | 107,52 |
| 9 (m) A2, 10 B2 | 178,88..223,60 | chaînes de la lane 2 | 176,56 |
| 11 (m) H2, 12 H3 | 223,60..268,32 | tenues des lanes 2 et 3 | 190,08 |
| 13 (m) A3, 14 B3 | 268,32..313,04 | chaînes de la lane 3 | 176,56 |

- Coutures : VSS en y = 0, 44,72, 89,44, 134,16, 178,88, 223,60, 268,32, 313,04 ; VDD entre les deux chaînes d'une
  lane (plots BOT face à face : CK et D passent de A à B, comme SR16_RX), entre H0/H1, D1/D2, H2/H3. Rails reliés par
  LABEL seulement (règle R1 du SR8) : c'est le PDN du top qui les relie.
- Ordre des rangées choisi contre les coutures dangereuses (bords relevés dans les GDS du kit) :
  - deux chaînes ne se font jamais face sur VSS (hs_to_clk contre hs_to_clk : V1.a du 28/09 ; plots TOP bi/stub face à
    face : court entre lanes) : entre deux paires de chaînes il y a toujours deux rangées de tenue ou du DIV4 ;
  - le `hs_to_clk` des chaînes (Metal2 jusqu'à 0,62 µm et Via1 jusqu'à 0,39 µm hors cadre côté VSS) est décalé à
    x = 3,84 par un `interco_h` entre HSCLK_IN et hs_to_clk : le Via1 / Metal2 hors cadre du drvb de tenue (x = 30,29)
    tombe à 0,53 µm du doigt Metal2 voisin (à x = 1,92 il le chevauchait : Via1 superposés), celui de XDEA / XDEB
    (x = 7,25) à 0,39 µm ;
  - XCKJ est à x = 74,88 : ses doigts Metal2 passent à 0,32 µm au moins du Metal2 des latchs de B1 en face (à
    cadre + 9,40 µm, 0,66 µm sous le bord) ; au premier build (x = 65,28) : 1 M2.b (0,04 µm), d'où les 9 vides ;
  - les plots TOP / BOT (Metal3 à cheval) ne font face qu'à des cellules sans Metal3 près de ce bord ; `vide` sépare
    les moitiés A / B des rangées de tenue (sortie MOT de XHAp_0 contre les entrées A / B de XGGBp), EA0 de XCKJ, etc.

## Règles CML (niveaux A / B, sortance)
- R1 : toute entrée B vient d'un `hs_to_clk` ou d'un `drvb` : CK des latchs de chaîne (XCKAp / XCKBp), du Johnson
  (XCKJ), de tenue (XDGAp / XDGBp) ; B de XGEA / XGEB par XDEA / XDEB ; **B de XGGAp = CKBp (= CK, sortie de XCKBp),
  B de XGGBp = CKAp (= /CK, sortie de XCKAp)** : horloge venue du récepteur HS, pas de la logique.
- R3 : validations en arbre (une porte ou un drv attaque 2 entrées) : XGEA -> XEA0 (aboutement) et XEA1 ; XEA0 -> A de
  XGGA0, XGGA1 ; XEA1 -> XGGA2, XGGA3 ; XGEB -> XEB0 (aboutement) et XEB1 ; XEB1 -> XGGB0, XGGB1 ; XEB0 -> XGGB2,
  XGGB3. Un `cml_drv` (tampon niveau A -> A) et non un drvb : EN_A / EN_B entrent sur A (niveau A) des portes.
  Johnson : m0 -> XJ2 + XGEA, s0 -> XJ3 + XGEB, s1 -> XJ1 + XDEB (2 chacun), m1 -> XJ4 + XDEA + broche CLK_W.
- Écarts R3 assumés, à juger au banc (voir « Banc ») : XCKAp / XCKBp attaquent 8 CK de latch + 1 B de porte (9 ; 8
  dans SR16_RX, spec 4) ; XDGAp / XDGBp (drvb) attaquent 4 CK de latch de tenue (comme SR16_RX, spec 2).

## Broches (79) et sondes
Toutes les broches de signal sont des pads Metal3 (.pin 30/2 + texte 30/25), VDD / VSS en Metal1 (15 rails).

| Broche | Pad | Accès | Position (µm) |
|---|---|---|---|
| CK_N / CK_P | XHSA0.INN / INP (-> XCKA0, XCKB0 par l'aboutement ; XCKA1..3 et XCKJ par la liaison CKIN) | bord gauche | (0 ; 19,06) / (0 ; 17,96) |
| Dp_N / Dp_P | XAp_1.INN / INP (et XBp_1 par XDAp / XDBp) | pad intérieur | x = 38,32 ; y 19,06 / 17,96 (+ 89,44 p) |
| POLN | XCKA0.POLN (XPOL) ; un seul net : 9 hs_to_clk + queues des 100 latchs | pad intérieur | (23,52 ; 3,73) |
| MOT(8p+2i)_N / _P | XHAp_i.OUTN / OUTP | pad intérieur | x = 48,00 / 63,36 / 78,72 / 94,08 (i = 3..0) |
| MOT(8p+2i+1)_N / _P | XHBp_i.OUTN / OUTP | pad intérieur (i = 0 : bord droit) | x = 144,00 / 159,36 / 174,72 / 190,08 |
| CLK_W_N / CLK_W_P | XJ3.OUTP / OUTN (paire croisée : CLK_W = /m1) | pad intérieur | (153,52 ; 152,12 / 153,22) |

y des MOT : lane 0 63,78 / 62,68 ; lane 1 70,38 / 71,48 ; lane 2 242,66 / 241,56 ; lane 3 249,26 / 250,36 (N / P).
NEBULA_IN_PORTS : CK_N/P, D0..D3_N/P, POLN ; NEBULA_OUT_PORTS : MOT0..31_N/P, CLK_W_N/P. Sondes (textes seuls, noms
= nets de l'intention, pour `tools/banc_sr16_rx4.py`) : CKJ, J1, J2, J4, NM1, NS1, ENA, ENB, ENA0, ENA1, ENB0, ENB1 et
par lane CKAp, CKBp, GAp, GBp, CKHAp, CKHBp, Ap_2, Ap_8, Bp_2, Bp_8 : 52 sondes, 104 textes (OBS dans le LEF toolchain).

## Liaisons routées (Metal4 / Metal5)
- 118 liaisons (`../../SR16_RX4.py`, LIAISONS ; noms = nets de l'intention), dans l'ordre de routage : CKIN (5 plots
  par fil : entrées de XCKA0..3 et XCKJ, prises à x = 3,84 et non sur le bord gauche, gardé pour les entrées des
  portes), arbre des validations (ENA0, ENA1, ENB0, ENB1, ENA, ENB), Johnson (J4, CLK_W, J1, J2), prises des chaînes
  vers la tenue (la chaîne éloignée de chaque lane d'abord : A0, B1, A2, B3), horloges des portes (CKBp -> XGGAp.B,
  CKAp -> XGGBp.B), POLN en 16 morceaux (hs_to_clk pris à leur plot intérieur XPOL, latchs de tenue à leur bord droit).
- Longueurs estimées (Metal4 + Metal5, µm par fil) : CKIN 432, ENA0/ENA1 185-213, ENB0/ENB1 131-151, ENA 33-35,
  ENB 53, J4 / J1 / J2 118-182, CLK_W 159, prises A 72-138, prises B 42-107, CKBp 44-84, CKAp 69-107, POLN 1155 en tout.
- LEF Caelum (`../LEF/sr16_rx4.lef`) : OBS Metal5 sur toute la macro + le Metal4 routé ; **le top ne doit pas router
  en Metal5 au-dessus de la macro.**

## Verdicts
| Contrôle | Résultat | Source |
|---|---|---|
| DRC KLayout du flot (deck complet) | 9 violations, toutes de densité globale (AFil.g, GFil.g, M1.j..M5.j, TM1.c, TM2.c), tolérées par NEBULA_KLAYOUT_DRC_MAX: 9 (dette déclarée, pas un pass) | metrics_drc.json, sr16_rx4.lyrdb, regles_drc_klayout.txt |
| DRC KLayout hors flot, sans densité | **0** (premier build : 1 M2.b, XCKJ contre un latch de B1) | `run_drc.py --no_density --mp 8` |
| DRC Magic | **0** (flot : « 0 error rectangles » ; hors flot, script type librelane : 0 ; le même script trouve 11 erreurs sur un GDS témoin) | rapport_drc_magic.txt, metrics_macro.json |
| LVS hors flot | **MATCH**, 1103 composants, 631 nets, contre `~/verif_srrx/lvs/sr16_rx4.intent.spice`. Témoins MISMATCH : GDS sans le Via3 de XGGA2.BP (CKB2_P) ; intention à B de XGGA2 croisé ; intention à XEB0 sur ENA | `~/verif_srrx/lvs/lvs4.sh` |
| LVS du flot | non jouée (NEBULA_LVS_GOLDEN: none, skip déclaré) | rapport_verdicts.txt |
| Intention = golden (N = 4) | OK : intention -> VHDL structurel, simulée contre `SR16(GOLDEN)` N = 4, 5 graines aléatoires (4 flux indépendants) + PRBS7 (lanes décalées) + aléatoire à 0xB8 synchrone, 4000 bits par lane chacune : 3960 comparaisons, 495 mots de 32 bits, 0 écart ; 5 mutants attrapés (B de XGGA2 croisé, prise de XHB3_1, XEB0 sur ENA, lanes 1 / 2 permutées, Johnson décroisé) | `~/verif_srrx/lvs/logique4/lancer4.sh` |
| Extrait = golden | OK : la même simulation sur `../SPICE/sr16_rx4.hier.spice` (extrait du flot), 0 écart | idem, avec l'extrait (INIT par noms extraits) |
| Golden de Lionel | `tb_mots` : SR16 4 lanes PASS, B8 synchrones au rang 1 du mot 24 | `COLLATERALS/HDL/TB` (copie hors dépôt) |
| Fonction (flot) | CheckFunction non jugée (not-run) | metrics_macro.json |
| ERC | 67 faux « port absent » (MOT0_P .. CLK_W_P : ports sur les lignes `+` du `.subckt`, bug toolchain connu) | metrics_macro.json |
| LEF toolchain | 79 PIN (VDD, VSS, 11 INPUT, 66 OUTPUT), SIZE 190.080 BY 313.040, sondes en OBS | sr16_rx4_toolchain.lef |
| Avertissements | pads plus étroits que le pas de 0,48 ; 104 textes-sondes hors ports (attendu) ; « partial prBoundary » (cadre 190,08 x 313,04, bbox 190,38 x 315,04 : pads Metal3 et demi-rails à cheval) | avertissements.txt |

SPICE à plat : `../SPICE/sr16_rx4.spice`, renommé `.subckt flatpost` -> `.subckt sr16_rx4` / `.ends sr16_rx4`
(`~/verif_sr8/renommer_flatpost.sh`) ; vue hiérarchique `../SPICE/sr16_rx4.hier.spice`. Aucune capacité (`ext2spice lvs`).

## Banc
`make tb MACRO=CML_SR/SR16_RX4` (`3_digital/tools/banc_sr16_rx4.py`, BANC_PY de `macro.mk`) sur `../SPICE/sr16_rx4.spice`
(extrait du flot SANS capacités de fil) : un HS-RX par lane data + un d'horloge, PRBS7 décalé de 32 p bits par lane,
0xB8 écrit au même bit sur les 4 lanes, 128 bits par lane (96 comparés, 12 mots), tt_typ_25, 1,2 V, V_OD 0,2 V.

| Run | Bits faux (4 lanes) | Marge | Décalage o | B8 | CLK_W | I sr16_rx4 | Verdict |
|---|---|---|---|---|---|---|---|
| intention (avant layout, cellules PEX), 1 Gb/s | 0 / 4 x 96 | 523 mV | 27 partout | mot 5 rang 0, 4 lanes | 8 UI, 50 % | 45,7 mA | VRAI OK |
| extrait, 1 Gb/s (`work/tb/tt_1e9_20260929_115056`) | 0 / 4 x 96 | 515 mV | 27 partout | mot 5 rang 0, 4 lanes | 8 UI, 50 % | 46,1 mA | VRAI OK |
| extrait, 2,5 Gb/s (`work/tb/tt_2.5e9_20260929_121613`) | 0 / 4 x 96 | 514 mV | 21 partout | mot 5 rang 6, 4 lanes | 8 UI, 50 % | 44,3 mA | VRAI OK |

Horloges sensibles à la sortance (extrait, différentiel crête à crête ; 4 lanes identiques à 5 mV près), 1 / 2,5 Gb/s :
CKAp / CKBp (hs_to_clk, 8 latchs + 1 B de porte) 0,99 / 0,84 V (crête min 0,49 / 0,40 V) ; CKJ 1,00 / 0,98 V ;
GAp / GBp (portes) impulsion 0,39 / 0,35 V ; CKHAp / CKHBp (drvb -> 4 latchs de tenue) impulsion 0,56 / **0,32 V**
pendant 0,97 / 0,36 ns (0,38 V noté pour SR16_RX à 2,5 Gb/s) ; ENA / ENB 1,06 V ; ENA0/1, ENB0/1 (après cml_drv)
1,02-1,04 V, crête min 0,50 V ; NM1 / NS1 1,46 V. POLN 0,548 V (ondulation 9-11 mV). Latence 3,78 / 4,01 UI ; MOT
stable avant / après le front de CLK_W 3,76 / 3,22 UI et 3,45 / 3,52 UI. Non joué : intention à 2,5 Gb/s, coins ss / ff.

## Non vérifié
- Parasites de fil : l'extrait du flot n'a aucune capacité. Les liaisons longues (CKIN 432 µm vers 5 hs_to_clk, ENA0 /
  ENA1 jusqu'à 213 µm, prises A jusqu'à 138 µm, CKAp / CKBp jusqu'à 107 µm) ne sont vues par aucune simulation.
- Comportement aux coins lents (ss_wcs_125, 1,08 V) : non joué ; SR16_RX échouait déjà avant layout à ce coin (cellules).
- Électromigration et IR des rails ; vérification par labels des rails et horloges (`rails_et_horloges.txt`) non faite.
- Intégration au top, à décider avec Jérémy :
  - Accès aux broches : CK_N / CK_P au bord gauche, MOT1 / 9 / 17 / 25 au bord droit ; les 67 autres sont des pads
    Metal3 intérieurs, sous l'OBS Metal5 pleine macro (LEF Caelum) ou sous les OBS Metal4 / Metal5 (LEF toolchain) :
    un routeur ne peut pas les atteindre en l'état (même situation que SR16_RX).
  - PDN : l'OBS Metal5 interdit de descendre sur les rails intérieurs ; les 15 rails ne sont joignables que par leurs
    bouts (x = 0 et bout droit de chaque rangée).
  - Charge de la broche CK : 5 entrées de hs_to_clk par la liaison CKIN (+ XCKB0) : c'est le HS-RX d'horloge du top
    qui la voit.

## Reproduire
```
cd 2_analog/CML_LIB/interconnect && make gds        # vide.gds (nouveau), interco_h.gds, interco_ck.gds (GDS ignorés par git)
cd 3_digital && make gds MACRO=CML_SR/SR16_RX4 && make drc MACRO=CML_SR/SR16_RX4 && make macro MACRO=CML_SR/SR16_RX4 \
  && make collat MACRO=CML_SR/SR16_RX4
~/verif_sr8/renommer_flatpost.sh $PWD/CML_SR/SR16_RX4/COLLATERALS/SPICE/sr16_rx4.spice sr16_rx4
python3 ~/verif_srrx/lvs/gen_sr16_rx4_intent.py                                          # intention
~/verif_srrx/lvs/lvs4.sh CML_SR/SR16_RX4/COLLATERALS/GDS/sr16_rx4.gds <dossier>           # MATCH
~/verif_srrx/lvs/logique4/lancer4.sh                                                     # intention = golden
INIT=Xcml_tlatch_95=0,Xcml_tlatch_94=0,Xcml_tlatch_93=0,Xcml_tlatch_92=0 \
  ~/verif_srrx/lvs/logique4/lancer4.sh $PWD/CML_SR/SR16_RX4/COLLATERALS/SPICE/sr16_rx4.hier.spice -   # extrait = golden
python3.13 $PDK_ROOT/$PDK/libs.tech/klayout/tech/drc/run_drc.py --path <gds> --run_dir <dossier> --no_density --mp 8
make tb MACRO=CML_SR/SR16_RX4 FIN=1e9 ; make tb MACRO=CML_SR/SR16_RX4 FIN=2.5e9
```
Le GDS `../GDS/sr16_rx4.gds` est ignoré par `.gitignore` (`*.gds`) : à ajouter avec `git add -f`, comme celui de SR16_RX.
