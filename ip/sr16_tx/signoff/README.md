# Signoff de la macro sr16_tx (GDS/sr16_tx.gds)

Construit le 29/09/2026 (nuit du tapeout) par une session Claude, branche `caelum`, worktree `~/LAYOUT/mipi-caelum`,
avec le Caelum installé (`/opt/nebula-eda/venv-lln`, qui reproduit `sr16_rx.gds` à l'identique : XOR nul) :
`PYTHONPATH=3_digital python3 SR16_TX.py`. **Rien n'est commité ; la fonction est une PROPOSITION non validée par
Lionel** (en-tête de `../HDL/sr16_tx.vhd`).

## La macro
- Fonction : `../HDL/sr16_tx.vhd`, sérialiseur 8 → 1 miroir de `sr16_mot.vhd` (RX). Registre de mot pris par
  CLK_W (reçu, ÷4 commun, pas de ÷4 interne) ; synchro du strobe p, q, r, t sur CK ; ld_a = q./t, lb = ld_a retardé
  d'une demi-période ; chaînes A (bits pairs, bascules au front montant) et B (bits impairs, front descendant) à
  chargement parallèle par MUX2 ; DOUT = sa0 pendant CK bas, sb0 pendant CK haut. MOT(0) émis le premier.
- Queue des chaînes sans MUX2 (ma3 ← h6, mb3 ← h7 en permanence) : golden mis à jour le 29/09 pour être identique au
  layout ; la queue ne sort jamais avant le chargement suivant.
- 53 cellules actives : 4 `hs_to_clk`, 37 `cml_tlatch`, 7 `cml_mux2`, 1 `cml_gate2`, 4 `cml_drvb` ; intercalaires
  `HSCLK_IN_1`, `interco_h`, `interco_ck`, et `vide` (nouvelle cellule du kit, `2_analog/CML_LIB/interconnect/vide.mag` :
  rails et cadre seuls, sans plot ; aucun intercalaire existant ne coupe à la fois les niveaux A et B autour d'un MUX2).
- Cadre 189/4 : 355,12 × 89,44 µm (4 × 22,36). Quatre rangées, de bas en haut (m = miroir) :

| Rangée | Contenu |
|---|---|
| 1 S | 18 vides, HSCLK_IN_1, hs_to_clk, interco_h, p q r t, 2 interco_ck, lb, vide, GATE2 (ld_a), vide |
| 2 (m) A | HSCLK_IN_1, hs_to_clk, 19 interco_h, (ma sa) × 4 séparés par 2 interco_ck, (vide MUX2) × 3, (vide DRVB) × 2, vide |
| 3 W | 20 vides, HSCLK_IN_1, hs_to_clk, interco_h, (hm h) × 8 séparés par 2 interco_ck, vide, MUX2 de sortie, vide |
| 4 (m) B | comme A, 21 interco_h, arbre de lb |

- Horloges et POLN : par aboutement le long de chaque rangée ; `interco_ck` × 2 = horloge recroisée deux fois (droite),
  donnée coupée. CK arrive sur la rangée S par une liaison droite, sur la rangée B par une liaison croisée (/CK : mb
  transparent CK haut). Aucune liaison vers un plot d'horloge de latch (le routeur ne les atteint pas).
- Coutures VSS (S-A, W-B) : le hs_to_clk de S et de W fait face aux interco_h de A et de B (sans Metal2) ; leur Metal2
  déborde du cadre côté VSS (M2.b contre un latch au premier essai).
- Sortance 2 (famille CML) : ld_a et lb passent chacun par deux DRVB.

## Broches
CK_N/P (bord gauche, XHSA.IN), CLK_W_N/P (XHSW.IN), MOT0..7_N/P (XHMi.IN), DOUT_N/P (XDO.X), POLN (XCKA), VDD / VSS
(Metal1, reliés par label : le PDN du top les relie).

## Vérifications
| Contrôle | Résultat | Où |
|---|---|---|
| DRC KLayout IHP (`run_drc.py --no_density`) | 0 violation | `work/drc/` |
| LVS netgen, extrait Magic contre intention écrite depuis `sr16_tx.vhd` | Circuits match uniquely, bornes équivalentes | `../../lvs/` (`make`), `work/lvs/lvs.rpt` |
| Banc `tb_sr16_tx.vhd` (golden) | PASS, 464 bits, 0 faux, PH 0,1 … 0,9 UI | `../HDL/TB/` |
| Banc analogique `tools/banc_sr16_tx.py` sur l'extrait, entrées CK / CLK_W / MOT par un `cml_drvb` du kit, 1 Gb/s, 16 mots, CLK_W à 0,3 UI | tt_typ_25 1,2 V : VRAI OK, 96 bits, 0 faux, latence 4 UI constante, marge 304 mV, I(VDD) 18,7 mA ; ss_wcs_125 1,08 V : VRAI OK, 96 bits, 0 faux, marge 67 mV, I(VDD) 12,9 mA | `work/tb/*_1g_16mots_drvb/` |
| Même banc, sources idéales directement sur la macro (`--direct`, niveaux fixes 0,94 / 0,48 V mesurés à 1,2 V) | tt : VRAI OK ; ss 1,08 V : ÉCHEC (niveaux d'entrée hors CML au corner, pas la macro : avec les DRVB d'entrée, ss passe) | `work/tb/tt_1g_24mots/`, `ss_1g_16mots/` |
| Liaison VHDL LP → HS → LP (dphy_tx + SR16_TX → dphy_rx + SR16) | 120 / 120 cas OK (3 corners tempo × 5 phases de CLK_W × 8 départs) | `../HDL/TB/tb_lien_lp_hs_lp.vhd` (sources DPHY_SM : branche StateMachines 50777b366) |

Limites : l'extrait est un extrait LVS (sans parasites) ; marge de 67 mV au corner lent (seuil du banc 50 mV) ;
seuls tt_typ_25 et ss_wcs_125 sont joués, une phase de CLK_W (0,3 UI) ; le ÷4 TX (source de CLK_W) n'existe pas encore et ses
fronts doivent tomber loin des fronts montants de CK (fermeture du latch p : cas métastable déclaré par le golden) ;
pas de `flow/config_*.yaml` (toolchain Nebula non jouée ici).

## Régénération du 29/09
Rejouée depuis `caelum` 02f57204 avec les cellules partagées courantes (GDS de `2_analog/CML_LIB/interconnect`
reconstruits par `make gds`), Caelum `~/projects/nebula/caelum_official` (`make gds MACRO=CML_SR/SR16_TX`).
- GDS : XOR KLayout nul sur toutes les couches, labels identiques (11 080) ; seules les métadonnées kfactory / KLayout
  diffèrent (2.4.7 / 0.30.9 au lieu de 3.0.4 / 0.30.12). LEF et DEF Caelum identiques octet pour octet.
- Ajout de `../../flow/config_drc.yaml` et `config_macro.yaml` (modèle sr16_rx) pour `make drc` / `make macro`.
- DRC : KLayout `--no_density` 0 violation ; NebulaCellDRC 9 = densité / fill seulement (`regles_drc_klayout.txt`) ;
  Magic 0.
- LVS `../../lvs` (`make`) : Circuits match uniquely, rapport identique. Extrait toolchain (`sr16_tx.hier.spice`) contre
  l'intention : match ; extrait à plat toolchain contre `sr16_tx.spice` : match. POLN : 37 `cml_tlatch` et 4
  `hs_to_clk` sur le net POLN, aucun POLN flottant.
- `../SPICE/sr16_tx.spice` reste l'extrait hiérarchique de `lvs/` (identique au commit) : `banc_sr16_tx.py` et le banc
  D-PHY prennent `cml_drvb` dans ce fichier, l'extrait à plat de la toolchain (`flatpost`) ne le définit pas.
- Bancs HDL : `tb_sr16_tx` 16 phases PASS ; `tb_mots` PASS (avec le `sr8_quartets.vhd` mono-lane de 421a3cfba) ;
  `tb_lien_lp_hs_lp` 168 / 168 OK (3 corners × CW_Q 1..7 × D0 0..7, avec `sr16_mot.vhd` multi-lane de SR16_RX).
- Banc SPICE `make tb MACRO=CML_SR/SR16_TX FIN=1e9` (tt_typ_25, 24 mots, entrées par DRVB) : VRAI OK, 160 bits, 0 faux,
  latence 4 UI, marge 304 mV, I(VDD) 18,70 mA.

## Régénération du 29/09 après fusion ANALOG_DESIGN
Après la fusion af2d308e (layouts de Yann, fe70f9b8) : `make gds` / `drc` / `macro` / `collat` et `lvs/` (`make`),
script `../../SR16_TX.py` **inchangé**.
- GDS sha1 `eea3f9ce49dfa66f3a76ac0a65d4dbbecf9c78e0` (avant `ab78a7b4`), = `final/gds` des runs `drc_20260929_155143_1`
  et `macro_20260929_155246`. Cadre inchangé (355,12 x 89,44 : la rangée W fixe la largeur). `cml_drvb` 11,52 -> 8,16 et
  `cml_gate2` 23,04 -> 12,48 µm : 7 instances de fin de rangée décalées vers la gauche (XDA2, XDB2, vides de fin ;
  XVGd 166,96 -> 156,40), rails VDD / VSS des rangées A, B, S raccourcis d'autant ; sonde LD_A déplacée
  (166,96 -> 156,40). Latch : contenu seul (cadre, bornes, POLN inchangés). Broches de signal inchangées.
- DRC KLayout `--no_density` : 0. NebulaCellDRC : 9 (densité / fill). Magic : 0.
- **Ordre des bornes de `cml_drvb` changé** par le layout de Yann (extrait : `VDD INP OUTN OUTP INN VSS`, avant
  `VDD INN INP OUTN OUTP VSS`). `lvs/intention.py` et `tools/banc_sr16_tx.py` instanciaient le drvb par position :
  corrigés pour lire l'ordre dans l'extrait (sans cela : LVS « Netlists do not match », banc aux entrées croisées).
  `3_digital/verif/banc_dphy_spice/banc_dphy.py` (l. 462) a le même motif positionnel et n'est **pas** corrigé.
- LVS `lvs/` : Circuits match uniquely. Extrait toolchain hiérarchique contre l'intention : match ; extrait à plat
  toolchain contre `../SPICE/sr16_tx.spice` : match.
- `../SPICE/sr16_tx.spice` reste l'extrait hiérarchique de `lvs/` (`work/lvs/sr16_tx_ext_vdd.spice`, recopié après
  `make macro` qui l'écrase) ; `sr16_tx.hier.spice` = extrait hiérarchique toolchain.
- Banc `make tb MACRO=CML_SR/SR16_TX` (24 mots, entrées par cml_drvb, 160 bits comparés ; pas de V_OD dans ce banc) :

| Corner | Débit | Bits faux | Latence | Marge min | I(VDD) | Verdict |
|---|---|---|---|---|---|---|
| tt_typ_25, 1,2 V | 1 Gb/s | 0 / 160 | 4 UI | 304 mV | 18,69 mA | VRAI OK |
| tt_typ_25, 1,2 V | 2,5 Gb/s | 0 / 160 | 5 UI | 351 mV | 18,29 mA | VRAI OK |
| ss_wcs_125, 1,08 V | 1 Gb/s | 0 / 160 | 4 UI | 67 mV | 12,85 mA | VRAI OK |
| ff_bcs_m40, 1,32 V | 2,5 Gb/s | 0 / 160 | 5 UI | 440 mV | 23,05 mA | VRAI OK |

  Runs : `../../work/tb/{tt_1e9_20260929_160346, tt_2.5e9_20260929_161659, ss_wcs_125_1e9_vdd1.08_20260929_161902,
  ff_bcs_m40_2.5e9_vdd1.32_20260929_161903}` (locaux). tt 1 Gb/s identique au 29/09 matin (304 mV, 18,70 mA). Marge ss faible (67 mV).
- Limite : extrait sans capacités (`ext2spice lvs`) : les parasites du nouveau layout ne sont pas simulés.
