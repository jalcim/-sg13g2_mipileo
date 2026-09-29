# ESD : MIPI_IOPadIOVdd

**ESTIMÉ PAR SIMULATION SPICE — pas une qualification**

Date : 28/09/2026. Cellule : `MIPI_IOPadIOVdd`, identique par XOR à `sg13g2_IOPadIOVdd`. Le pad est `iovdd`.
Contenu de la cellule dans la netlist (**constaté**) : un clamp RC entre iovdd et iovss. Le NMOS HV `Clamp_N43N43D4R` fait 172 × 4,4 µm / 0,6 µm. Il est déclenché par 26 × 5,24 kΩ de rppd et un condensateur MOS, avec un inverseur HV. Prises substrat : 0,45 Ω vers iovss et 22,5 Ω vers vss. `vdd` n'est pas connecté. La cellule ne contient pas de diode : en négatif, iovdd n'est protégé que par la jonction drain-substrat du clamp, ou dans le ring par la DCP d'IOPadIOVss.

## Verdict

| contexte | HBM ±2 kV | HBM max qui passe (toutes zaps) | MM ±200 V | CDM ±1000 V |
|---|---|---|---|---|
| **ring** (avec IOPadIOVss, IOPadVdd, IOPadVss) | paire iovdd/iovss : **PASS** (+ : 7,74 V / 1,24 A ; − : 0,90 V). Vers vdd : **FAIL** (13,6 V et 7,8 V sur vdd/vss). Vers vss : + **FAIL** (10,9 V), − PASS | **0,5 kV** (limité par iovdd− / vdd : V(vdd,vss) = 4,16 V à 0,75 kV). Paire iovdd/iovss seule : **2,1 kV** (7,91 V à 2,1 kV ; 8,07 V à 2,2 kV ; le courant atteindrait 1,51 A vers 2,45 kV) | **FAIL** (clamp 2,9 A, environ 10,5 V) | + : **PASS** (0,96 V) ; − : **FAIL** (10,3 V dès −250 V ; clamp 2,6 à 3,5 A ; le reste du courant passe par des jonctions en claquage, **supposé**) |
| seul | + / iovss : PASS (7,74 V) ; − / iovss : PASS mais non crédible (jonction PSP, voir Limites, point 2) ; vs vss : FAIL (28,6 V) | paire iovdd+/iovss : 2,1 kV ; toutes zaps : < 1 kV | FAIL | FAIL ou INVALIDE |

Lecture :
- La fonction de la cellule (clamp iovdd → iovss) tient **2,1 kV HBM**. La limite vient de la tension : le clamp « tout ouvert » laisse 7,7 V à 1,24 A. Vérification en DC, grille = drain : 0,46 A à 4 V, cohérent avec le transitoire où la grille monte à 7,2 V (**constaté**). En silicium réel, au-delà d'environ 8 à 10 V, le NMOS HV entrerait probablement en snapback, ce que le modèle ne simule pas.
- CDM négatif : le clamp RC ne descend pas sous 10 V pendant la première nanoseconde. Le FAIL dépend de la limite de 8 V, prise volontairement identique à celle à 100 ns (conservatif).

## Résultats (variante modèles de diodes ESD)

Colonnes : contexte, modèle d'agression, niveau, broche zappée / référence, grandeur mesurée (la plus proche de sa limite), valeur, critère, verdict.

### Niveaux normatifs (modèles de diodes ESD)

| contexte | modèle | niveau | broche zappée / réf. | grandeur limitante | valeur | critère | verdict | note |
|---|---|---|---|---|---|---|---|---|
| seul | CDM | +1000 V | iovdd (charge sur sub!) | V(iovdd,vss) | 26.7 V | ≤ 8 V | FAIL | run tronqué à 1.07 ns (max pris avant) |
| seul | CDM | +500 V | iovdd (charge sur sub!) | V(iovdd,vss) | 16 V | ≤ 8 V | FAIL | relancé en gear ; run tronqué à 2.01 ns (max pris avant) |
| seul | CDM | +250 V | iovdd (charge sur sub!) | V(iovdd,vss) | 10.1 V | ≤ 8 V | INVALIDE | run tronqué à 0.207 ns (max pris avant) |
| seul | CDM | -250 V | iovdd (charge sur sub!) | V(iovdd,vss) | 10.9 V | ≤ 8 V | FAIL |  |
| seul | CDM | -500 V | iovdd (charge sur sub!) | V(iovdd,vss) | 13.8 V | ≤ 8 V | FAIL |  |
| seul | CDM | -1000 V | iovdd (charge sur sub!) | I clamp IOPadIOVdd | 10.7 A | ≤ 4.53 A | FAIL |  |
| seul | HBM | +2000 V | iovdd / iovss | V(iovdd,iovss) | 7.74 V | ≤ 8 V | PASS |  |
| seul | HBM | -2000 V | iovdd / iovss | I clamp IOPadIOVdd | 1.26 A | ≤ 1.51 A | PASS | run tronqué à 14.8 ns (max pris avant) |
| seul | HBM | +2000 V | iovdd / vss | V(iovss,vss) | 28.7 V | ≤ 4 V | FAIL |  |
| seul | HBM | -2000 V | iovdd / vss | V(iovss,vss) | 28.5 V | ≤ 4 V | FAIL | run tronqué à 12.4 ns (max pris avant) |
| seul | MM | +200 V | iovdd / iovss | I clamp IOPadIOVdd | 2.93 A | ≤ 1.51 A | FAIL |  |
| seul | MM | -200 V | iovdd / iovss | I clamp IOPadIOVdd | 1.71 A | ≤ 1.51 A | INVALIDE | run tronqué à 7.1 ns (max pris avant) |
| seul | MM | +200 V | iovdd / vss | V(iovss,vss) | 54 V | ≤ 4 V | INVALIDE | relancé en gear ; run tronqué à 78.7 ns (max pris avant) |
| seul | MM | -200 V | iovdd / vss | V(iovss,vss) | 54.5 V | ≤ 4 V | INVALIDE | relancé en gear ; run tronqué à 38.7 ns (max pris avant) |
| ring | CDM | +1000 V | iovdd (charge sur sub!) | V(iovdd,vdd) | 0.961 V | ≤ 8 V | PASS |  |
| ring | CDM | +500 V | iovdd (charge sur sub!) | V(iovdd,vdd) | 0.909 V | ≤ 8 V | PASS |  |
| ring | CDM | +250 V | iovdd (charge sur sub!) | V(iovdd,vdd) | 0.865 V | ≤ 8 V | PASS |  |
| ring | CDM | -250 V | iovdd (charge sur sub!) | V(iovdd,vss) | 10.3 V | ≤ 8 V | FAIL |  |
| ring | CDM | -500 V | iovdd (charge sur sub!) | V(iovdd,vss) | 10.8 V | ≤ 8 V | FAIL |  |
| ring | CDM | -1000 V | iovdd (charge sur sub!) | V(iovdd,vss) | 10.8 V | ≤ 8 V | FAIL |  |
| ring | HBM | +2000 V | iovdd / iovss | V(iovdd,iovss) | 7.74 V | ≤ 8 V | PASS |  |
| ring | HBM | -2000 V | iovdd / iovss | V(iovdd,iovss) | 0.898 V | ≤ 8 V | PASS |  |
| ring | HBM | +2000 V | iovdd / vdd | V(iovdd,vdd) | 13.6 V | ≤ 8 V | FAIL | run tronqué à 13.7 ns (max pris avant) |
| ring | HBM | -2000 V | iovdd / vdd | V(vdd,vss) | 7.8 V | ≤ 4 V | FAIL |  |
| ring | HBM | +2000 V | iovdd / vss | V(iovdd,vss) | 10.9 V | ≤ 8 V | FAIL |  |
| ring | HBM | -2000 V | iovdd / vss | V(iovss,vss) | 3.2 V | ≤ 4 V | PASS |  |
| ring | MM | +200 V | iovdd / iovss | I clamp IOPadIOVdd | 2.93 A | ≤ 1.51 A | FAIL |  |
| ring | MM | -200 V | iovdd / iovss | I clamp IOPadIOVdd | 2.83 A | ≤ 1.51 A | FAIL |  |
| ring | MM | +200 V | iovdd / vdd | V(iovdd,vdd) | 15.7 V | ≤ 8 V | INVALIDE | run tronqué à 7.01 ns (max pris avant) |
| ring | MM | -200 V | iovdd / vdd | V(vdd,vss) | 10.8 V | ≤ 4 V | FAIL | run tronqué à 116 ns (max pris avant) |
| ring | MM | +200 V | iovdd / vss | V(iovdd,vss) | 15.3 V | ≤ 8 V | FAIL |  |
| ring | MM | -200 V | iovdd / vss | V(iovss,vss) | 7.58 V | ≤ 4 V | FAIL | relancé en gear |


### Balayage HBM : niveau max qui passe (grille 1-2-3-4-6-8 kV ; + 2,1 à 2,8 kV sur iovdd+ / iovss ; + 0,5 et 0,75 kV sur les zaps vers vdd)

| contexte | broche zappée / réf. | polarité | max PASS | 1er FAIL | grandeur limitante au 1er FAIL |
|---|---|---|---|---|---|
| seul | iovdd / iovss | + | 2.1 kV | 2.2 kV | V(iovdd,iovss) = 8.07 V (FAIL) |
| seul | iovdd / iovss | - | 2 kV | 3 kV | I clamp IOPadIOVdd = 1.79 A (INVALIDE) |
| seul | iovdd / vss | + | < 1 kV | 1 kV | V(iovss,vss) = 14.4 V (FAIL) |
| seul | iovdd / vss | - | < 1 kV | 1 kV | V(iovss,vss) = 14.2 V (FAIL) |
| ring | iovdd / iovss | + | 2 kV | 2.2 kV | V(iovdd,iovss) = 8.08 V (FAIL) |
| ring | iovdd / iovss | - | 8 kV | > 8 kV (non atteint) | — |
| ring | iovdd / vdd | + | 0.75 kV | 1 kV | V(iovdd,vdd) = 8.92 V (FAIL) |
| ring | iovdd / vdd | - | 0.5 kV | 0.75 kV | V(vdd,vss) = 4.16 V (FAIL) |
| ring | iovdd / vss | + | 1 kV | 2 kV | V(iovdd,vss) = 10.9 V (FAIL) |
| ring | iovdd / vss | - | 2 kV | 3 kV | V(iovss,vss) = 4.72 V (FAIL) |

Note : le HBM ring iovss− / iovdd et le HBM ring iovdd+ / iovss sont la même agression physique. Le balayage fin (2,1 à 2,8 kV) n'a été fait que sous le nom iovdd+ / iovss.

### Contrôle de validité : même banc avec les modèles d'antenne du PDK (dantenna/dpantenna)

| contexte | modèle | niveau | broche zappée / réf. | grandeur limitante | valeur | critère | verdict | note |
|---|---|---|---|---|---|---|---|---|
| seul | HBM | +2000 V | iovdd / iovss | V(iovdd,iovss) | 7.74 V | ≤ 8 V | PASS | modèle antenne PDK |
| seul | HBM | -2000 V | iovdd / iovss | I clamp IOPadIOVdd | 1.26 A | ≤ 1.51 A | PASS | modèle antenne PDK ; run tronqué à 14.8 ns (max pris avant) |
| seul | HBM | +2000 V | iovdd / vss | V(iovss,vss) | 28.7 V | ≤ 4 V | FAIL | modèle antenne PDK |
| seul | HBM | -2000 V | iovdd / vss | V(iovss,vss) | 28.5 V | ≤ 4 V | FAIL | modèle antenne PDK ; run tronqué à 12.4 ns (max pris avant) |

IOPadIOVdd ne contient ni DCN ni DCP : les deux variantes sont identiques pour cette cellule seule (contrôle sans objet).

## Critères pass/fail (déclarés)

Une zap passe si **toutes** les grandeurs mesurées restent sous leur limite. Le tableau donne la grandeur la plus proche de sa limite (ou la plus au-delà).

| grandeur | limite | justification | statut |
|---|---|---|---|
| tension entre deux rails dont l'un est iovdd (V(iovdd,iovss), V(iovdd,vss), V(iovdd,vdd)) | **8,0 V** | Entre ces rails on ne trouve en fonctionnement que des dispositifs 3,3 V à oxyde épais. tox HV = 7,43 nm (nmos) / 6,95 nm (pmos) dans `sg13g2_moshv_parm.lib` : **constaté**. Claquage transitoire d'un oxyde SiO2 de 5 à 7 nm sous impulsion d'environ 100 ns : de l'ordre de 12 à 15 MV/cm. C'est un ordre de grandeur publié (TLP sur oxydes de grille), non vérifié pour IHP : **supposé**. Sur 6,95 nm, 8 V font environ 11,5 MV/cm, donc une marge de 15 à 25 % est prise. 8 V reste aussi sous le claquage des jonctions dans les modèles (vbr PSP = 10 V, bv des diodes ESD de 10 à 11,8 V : **constaté**). | supposé |
| tension entre deux rails sans iovdd (V(iovss,vss), V(vdd,vss), V(iovss,vdd)) | **4,0 V** | Un oxyde mince de 1,2 V peut se trouver entre ces rails (cœur, décaleurs de niveau). tox LV = 2,24 nm (nmos) / 1,97 nm (pmos) : **constaté**. Claquage à 100 ns de l'ordre de 5 V pour des oxydes d'environ 2 nm : **supposé**. On garde environ 20 % de marge. | supposé, conservatif |
| courant crête dans le clamp NMOS (172 × 4,4 µm = 756,8 µm, L = 0,6 µm, HV) | **1,51 A** (2 mA/µm) | Il n'existe aucune donnée IHP de défaillance du clamp en mode actif. On retient une densité conservative déclarée. | supposé |
| courant crête dans une diode DCP ou DCN (2 éléments de 27,78 × 1,26 µm) | **2,67 A** (1,33 A par élément) | L'élément a exactement la géométrie de `diodevdd_2kv` / `diodevss_2kv` de `sg13g2_esd.lib` (A = 35 µm², P = 58,08 µm) : **constaté**. On lit le suffixe « 2kv » comme une tenue HBM de 2 kV, soit 1,33 A : **supposé**. | supposé |
| CDM (impulsion d'environ 1 ns) | limites de courant × 3 | Wunsch-Bell (puissance de défaillance ∝ t^-1/2) donnerait × 10 entre 100 ns et 1 ns ; × 3 est conservatif. Les limites de tension restent inchangées (conservatif). | supposé |

Validité d'un run : le pic de la contrainte doit avoir été simulé. En HBM, il faut Izap ≥ 0,95 × 0,640 A/kV × (niveau − Vpaire) et une fin de run ≥ 10 ns. En MM, il faut une fin de run ≥ 100 ns (trois demi-périodes). En CDM, il faut une fin de run ≥ 1 ns (le pic est à 0,17 ns). Les maxima sont pris sur [0, fin]. Un run qui ne satisfait pas ces conditions est noté **INVALIDE** : ce n'est pas un résultat.

## Modèles d'agression

Les sources sont des sources équivalentes à éléments localisés. Elles sont vérifiées sur court-circuit avec `esd_bench/cal_sources.spice` (**constaté**).

| modèle | norme | circuit | vérification sur court-circuit |
|---|---|---|---|
| HBM | ANSI/ESDA/JEDEC JS-001 | 100 pF chargés, 2,5 µH, 1500 Ω | Ip = 0,640 A/kV (norme : 0,60 à 0,73), tr(10-90 %) = 3,2 ns (norme : 2 à 10 ns), décroissance du pic à 36,8 % = 150 ns (norme : 130 à 170 ns) |
| MM | JESD22-A115 / ESDA STM5.2 (JEDEC JEP172 déconseille le MM pour la qualification ; donné ici à titre indicatif) | 200 pF chargés, 0,75 µH, 1 Ω (amortissement numérique et contact) | Ip1 = 3,22 A à 200 V (norme : environ 2,8 à 3,8 A), sonnerie à 13,0 MHz (norme : 11 à 16 MHz) |
| CDM | ANSI/ESDA/JEDEC JS-002, **simplifié** | corps du circuit (nœud `sub!`) chargé à ±V par 6,8 pF vis-à-vis du plan de champ ; broche zappée reliée au plan par un pogo de 5 nH + 70 Ω | Ip = 5,67 A à 500 V, FWHM = 0,50 ns |

Un condensateur chargé est modélisé par un condensateur déchargé en série avec un échelon de tension de 10 ps (équivalent de Thévenin). On obtient ainsi un point de repos cohérent, sans `uic`.

**Simplification CDM.** En FICDM réel, chaque réseau de la puce a sa propre capacité vers le plan de champ. La décharge est distribuée et passe par le boîtier. Ici, toute la charge est placée sur le substrat (`sub!`), qui est la plus grosse capacité d'une puce, avec une seule capacité localisée égale à celle du petit module de vérification. Le pogo (5 nH + 70 Ω) est calé pour obtenir un ordre de grandeur de forme d'onde JS-002 (Ip d'environ 5,7 A à 500 V, largeur d'environ 0,5 ns). Il n'est **pas** recalé sur la table normative (**supposé**). Il n'y a ni boîtier ni capacité propre des rails. CDM positif = corps chargé positivement : le courant sort par la broche zappée.

**Combinaisons de zaps.** On zappe le pad de la cellule en positif et en négatif contre chacun des autres rails d'alimentation exposés par la netlist (iovss/iovdd, vss, vdd). Les broches non concernées sont flottantes (fuite de 1 GΩ). C'est la règle JS-001 réduite aux rails. En CDM, la broche zappée est le pad de la cellule.

**Deux contextes.**
- *seul* : la cellule isolée. `vdd` n'est connecté à rien dans ces deux cellules (**constaté** dans la netlist), donc aucune zap contre vdd n'est faite en « seul ».
- *ring* : les quatre cellules d'alimentation IHP que définit `SPICE/CSI2_DPHY_RING.spice` (`sg13g2_IOPadVdd`, `sg13g2_IOPadVss`, `sg13g2_IOPadIOVdd`, `sg13g2_IOPadIOVss`), une instance de chaque, sur des rails communs, sans fillers ni coins. C'est le contexte réaliste : les deux cellules d'alimentation IO se protègent mutuellement. Le nombre d'instances réellement placées dans le ring n'a pas été vérifié.

## Corner

Un seul corner : `mos_tt` (LV et HV), `res_typ`, `dio_tt`, 25 °C. Circuit **non alimenté** (le VDD 1,2 V / IOVDD 3,3 V n'est pas appliqué), comme pendant une zap de qualification : toutes les alimentations sont flottantes, seules la broche zappée et la référence (masse) sont connectées.

## Versions

- ngspice : `/home/lsaintecluque/local/bin/ngspice`, ngspice-47+, KLU, compilé le 30/08/2026.
- OSDI : `$PDK_ROOT/ihp-sg13g2/libs.tech/ngspice/osdi/psp103.osdi` (md5 962e045ac38ea96b2e63dec7a1b653a4) et `r3_cmc.osdi` (md5 40cfc76d1aed512cdb82322eef64bc01), datés du 09/09/2026. Ils se chargent sans recompilation. openvaf de référence : `~/local/bin/openvaf` 23.5.0.
- PDK : `/home/lsaintecluque/IHP-Open-PDK`, commit 5e6d592e (01/09/2026). Fichiers de modèles (md5) : cornerMOShv.lib 0f392e5d…, cornerMOSlv.lib 326e3b79…, cornerRES.lib a201cd1e…, cornerDIO.lib 2ffe4554…, sg13g2_moshv_parm.lib f69b91b7…, diodes.lib 8ea0f491…, sg13g2_esd.lib 5e2b761b…, resistors_mod.lib 34e804d2….

## Netlist

- Source : `/home/lsaintecluque/IHP-Open-PDK/ihp-sg13g2/libs.ref/sg13g2_io/spice/sg13g2_io.spice`, md5 **f6ba2e12788d6cf078e2c4db41f6cc57**. On l'utilise parce que MIPI_IOPadIOVss et MIPI_IOPadIOVdd sont identiques par XOR aux cellules sg13g2 (commits 414b8eb6 et fe4de92b ; XOR non refait ici). `sub!` est déclaré `.global`.
- Copies dérivées (`esd_bench/derive_netlists.py`, la source n'est pas modifiée) :
  - `io_probe_pdk.spice` (md5 9ac0b4f6877c5e8390d02bb498d43dda) : sources de 0 V de mesure en série avec le clamp NMOS, la DCN et la DCP. La diode d'antenne de grille du clamp (`XD0 dantenna 0,48 × 0,48 µm`) est remplacée par `diodevss_mod` de même surface. Avec le modèle `dantenna`, le transitoire se bloque (pas de temps < 1 fs à environ 85 ps) : **constaté**. L'effet électrique d'une jonction de 0,23 µm² est négligeable : **supposé**.
  - `io_probe_esd.spice` (md5 e5d102a67e9d8702ffcf8ec46fb61bcb) : même chose, et DCN/DCP remplacées par les modèles ESD d'IHP de même géométrie (`diodevss_4kv` / `diodevdd_4kv`, A = 70 µm², P = 116,2 µm, avec leur diode nwell/psub `dsub_4kv`). **C'est la variante qui donne les résultats.**
- Pourquoi substituer : les modèles `dantenna` / `dpantenna` sont annoncés « designed for reverse direction » et ont une résistance série de plusieurs kΩ. En direct à 2 kV HBM, ils donnent 1 140 V sur la DCP (tableau « contrôle de validité ») : **constaté**. Ils sont inutilisables en ESD.

## Bancs (relançables)

Dossier : `/home/lsaintecluque/LAYOUT/mipi-analog/2_analog/CSI2_DPHY_RING/COLLATERALS/signoff/esd_bench/`

- `run_all.sh [logdir]` régénère les netlists et les decks, puis lance tout (8 jobs, environ 1 h sur la machine partagée). Il produit `results_raw.txt` et la liste des runs interrompus.
- `summarize.py results_raw.txt IOVss|IOVdd` applique les critères et imprime les tableaux de ce document.
- `gen_decks.py` écrit `decks/*.spice` (liste principale `decks/LIST`, plus `decks/LIST_extra` : balayage fin entre 2 et 2,8 kV, points à 0,5 et 0,75 kV vers vdd, relances en gear).
- `cal_sources.spice` : vérification des trois sources sur court-circuit.
- `aborted_runs.txt` : 24 decks ont au moins un niveau interrompu (« timestep too small »). Le tableau les note « run tronqué » ou INVALIDE.
- Logs de ce run : `/tmp/claude-1001/esd/logs2/` (temporaire).

## Limites de la méthode

1. **Aucun snapback, aucune défaillance thermique ni second claquage.** Les modèles compacts (PSP 103, diodes SPICE) ne représentent pas le déclenchement du NPN parasite du NMOS HV, la tenue It2 ou la fusion. Un PASS signifie seulement « les tensions et courants restent sous les limites déclarées dans un modèle sans défaillance ». Au-delà d'environ 8 à 10 V sur le clamp, le silicium réel entrerait probablement en snapback, ce qui peut aussi bien limiter la tension que détruire le dispositif.
2. **Modèles non calibrés à l'ampère.** La jonction drain-substrat du clamp (JUNCAP PSP, IMAX = 2 mA) conduit en direct avec une chute anormalement élevée : 6,1 V à 1,26 A en « seul », iovdd négatif. Tous les chemins qui ne passent que par cette jonction (IOVdd « seul » en négatif, CDM positif « seul ») sont **non crédibles** (pessimistes). Les diodes ESD sont des modèles IHP dédiés, utilisés hors de leur domaine de mesure (**supposé** acceptable).
3. **Netlist schématique.** Pas de résistance de métal, de via ou de bus ESD, pas de bond ni de boîtier. Le substrat se réduit aux résistances `ptap1` de la netlist. C'est optimiste pour les chutes ohmiques et pessimiste pour l'absence de chemins parallèles.
4. **Contexte ring minimal.** Une seule instance de chaque cellule d'alimentation, sans fillers, coins, autres IO (HS/LP) ni cœur (pas de découplage). Le vrai ring a peut-être plusieurs clamps en parallèle : c'est pessimiste.
5. **Critères déclarés, pas des données IHP.** Le verdict dépend directement des limites de 8 V, 4 V, 2 mA/µm et 1,33 A par élément. En particulier, les zaps vers les rails cœur (vdd/vss) échouent surtout sur la limite de 4 V de l'oxyde mince. Le clamp cœur d'IHP (`IOPadVdd`) est référencé à iovss et utilise le même NMOS HV : il laisse environ 7,7 V entre vdd et vss à 2 kV (**constaté**).
6. **Numérique.** 24 decks ont eu des transitoires interrompus (pas de temps < 1e-21 s). Les relances en gear n'ont pas tout rattrapé. Voir `aborted_runs.txt` et la colonne « note ».
7. Un seul corner (tt, 25 °C). Le HBM n'a pas les parasites du testeur (pré-impulsion, capacité de la carte). Le MM est une norme retirée pour la qualification.
