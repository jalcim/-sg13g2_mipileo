# ESD : MIPI_IOPadIOVss

**ESTIMÉ PAR SIMULATION SPICE — pas une qualification**

Date : 28/09/2026. Cellule : `MIPI_IOPadIOVss`, identique par XOR à `sg13g2_IOPadIOVss`. Le pad est `iovss`.
Contenu de la cellule dans la netlist (**constaté**) : une DCP iovss → iovdd, une DCN court-circuitée (sub! → iovss), une prise substrat de 0,17 Ω vers iovss et de 22,5 Ω vers vss. `vdd` n'est pas connecté.

## Verdict

| contexte | HBM ±2 kV | HBM max qui passe (toutes zaps) | MM ±200 V | CDM ±1000 V |
|---|---|---|---|---|
| **ring** (avec IOPadIOVdd, IOPadVdd, IOPadVss) | paire iovss/iovdd : **PASS** (+ : 0,90 V ; − : 7,74 V, clamp d'IOPadIOVdd). Vers vss/vdd : **FAIL** sur 3 zaps sur 4 (5,5 à 7,7 V > 4 V ; iovss+ / vss passe avec 3,2 V) | **0,5 kV** (limité par iovss− / vdd : 4,13 V à 0,75 kV). Paire iovss/iovdd seule : **2,1 kV** (limite 8 V atteinte vers 2,15 kV, voir IOVdd) | **FAIL** (clamp 2,9 A > 1,51 A) | **PASS** (≤ 0,67 V) |
| seul | **FAIL** (iovss− / iovdd : claquage de la DCP à 11 V ; vs vss : 28,6 V sur 22 Ω de substrat) | < 1 kV | FAIL | PASS |

Lecture :
- Seule, la cellule n'a ni protection iovdd → iovss (c'est le rôle du clamp d'IOPadIOVdd) ni chemin vers vss (c'est le rôle d'IOPadVss). Le FAIL « seul » est attendu. Le verdict utile est celui du **ring**.
- Dans le ring, la paire d'alimentation IO tient 2 kV avec 3 % de marge sur la tension. Ce qui échoue, ce sont les zaps vers les rails cœur, jugés sur la limite de 4 V de l'oxyde mince (voir Critères et Limites, point 5), ainsi que le MM.

## Résultats (variante modèles de diodes ESD)

Colonnes : contexte, modèle d'agression, niveau, broche zappée / référence, grandeur mesurée (la plus proche de sa limite), valeur, critère, verdict.

### Niveaux normatifs (modèles de diodes ESD)

| contexte | modèle | niveau | broche zappée / réf. | grandeur limitante | valeur | critère | verdict | note |
|---|---|---|---|---|---|---|---|---|
| seul | CDM | +1000 V | iovss (charge sur sub!) | V(iovss,vss) | 1.8 V | ≤ 4 V | PASS |  |
| seul | CDM | +500 V | iovss (charge sur sub!) | V(iovss,vss) | 0.919 V | ≤ 4 V | PASS |  |
| seul | CDM | +250 V | iovss (charge sur sub!) | V(iovss,vss) | 0.46 V | ≤ 4 V | PASS |  |
| seul | CDM | -250 V | iovss (charge sur sub!) | V(iovss,vss) | 0.46 V | ≤ 4 V | PASS |  |
| seul | CDM | -500 V | iovss (charge sur sub!) | V(iovss,vss) | 0.921 V | ≤ 4 V | PASS |  |
| seul | CDM | -1000 V | iovss (charge sur sub!) | V(iovss,vss) | 1.84 V | ≤ 4 V | PASS |  |
| seul | HBM | +2000 V | iovss / iovdd | V(iovdd,iovss) | 1.06 V | ≤ 8 V | PASS |  |
| seul | HBM | -2000 V | iovss / iovdd | V(iovdd,iovss) | 11 V | ≤ 8 V | FAIL |  |
| seul | HBM | +2000 V | iovss / vss | V(iovss,vss) | 28.6 V | ≤ 4 V | FAIL |  |
| seul | HBM | -2000 V | iovss / vss | V(iovss,vss) | 28.6 V | ≤ 4 V | FAIL |  |
| seul | MM | +200 V | iovss / iovdd | V(iovdd,iovss) | 11.3 V | ≤ 8 V | FAIL |  |
| seul | MM | -200 V | iovss / iovdd | V(iovdd,iovss) | 11.3 V | ≤ 8 V | FAIL |  |
| seul | MM | +200 V | iovss / vss | V(iovss,vss) | 56.4 V | ≤ 4 V | FAIL |  |
| seul | MM | -200 V | iovss / vss | V(iovss,vss) | 56.4 V | ≤ 4 V | FAIL |  |
| ring | CDM | +1000 V | iovss (charge sur sub!) | V(iovss,vss) | 0.669 V | ≤ 4 V | PASS |  |
| ring | CDM | +500 V | iovss (charge sur sub!) | V(iovss,vss) | 0.335 V | ≤ 4 V | PASS |  |
| ring | CDM | +250 V | iovss (charge sur sub!) | V(iovss,vss) | 0.167 V | ≤ 4 V | PASS |  |
| ring | CDM | -250 V | iovss (charge sur sub!) | V(iovss,vss) | 0.167 V | ≤ 4 V | PASS |  |
| ring | CDM | -500 V | iovss (charge sur sub!) | V(iovss,vss) | 0.335 V | ≤ 4 V | PASS |  |
| ring | CDM | -1000 V | iovss (charge sur sub!) | V(iovss,vss) | 0.669 V | ≤ 4 V | PASS |  |
| ring | HBM | +2000 V | iovss / iovdd | V(iovdd,iovss) | 0.898 V | ≤ 8 V | PASS |  |
| ring | HBM | -2000 V | iovss / iovdd | V(iovdd,iovss) | 7.74 V | ≤ 8 V | PASS |  |
| ring | HBM | +2000 V | iovss / vdd | V(iovss,vdd) | 5.94 V | ≤ 4 V | FAIL | run tronqué à 13.2 ns (max pris avant) |
| ring | HBM | -2000 V | iovss / vdd | V(iovss,vdd) | 7.74 V | ≤ 4 V | FAIL |  |
| ring | HBM | +2000 V | iovss / vss | V(iovss,vss) | 3.23 V | ≤ 4 V | PASS |  |
| ring | HBM | -2000 V | iovss / vss | V(iovss,vss) | 5.47 V | ≤ 4 V | FAIL |  |
| ring | MM | +200 V | iovss / iovdd | I clamp IOPadIOVdd | 2.83 A | ≤ 1.51 A | FAIL | run tronqué à 115 ns (max pris avant) |
| ring | MM | -200 V | iovss / iovdd | I clamp IOPadIOVdd | 2.93 A | ≤ 1.51 A | FAIL |  |
| ring | MM | +200 V | iovss / vdd | V(iovss,vdd) | 7.1 V | ≤ 4 V | INVALIDE | run tronqué à 6.85 ns (max pris avant) |
| ring | MM | -200 V | iovss / vdd | V(iovss,vdd) | 10.7 V | ≤ 4 V | FAIL |  |
| ring | MM | +200 V | iovss / vss | V(iovss,vss) | 11.1 V | ≤ 4 V | FAIL |  |
| ring | MM | -200 V | iovss / vss | V(iovss,vss) | 11.9 V | ≤ 4 V | FAIL |  |


### Balayage HBM : niveau max qui passe (grille 1-2-3-4-6-8 kV ; + 2,1 à 2,8 kV sur iovdd+ / iovss ; + 0,5 et 0,75 kV sur les zaps vers vdd)

| contexte | broche zappée / réf. | polarité | max PASS | 1er FAIL | grandeur limitante au 1er FAIL |
|---|---|---|---|---|---|
| seul | iovss / iovdd | + | 8 kV | > 8 kV (non atteint) | — |
| seul | iovss / iovdd | - | < 1 kV | 1 kV | V(iovdd,iovss) = 10.9 V (FAIL) |
| seul | iovss / vss | + | < 1 kV | 1 kV | V(iovss,vss) = 14.3 V (FAIL) |
| seul | iovss / vss | - | < 1 kV | 1 kV | V(iovss,vss) = 14.3 V (FAIL) |
| ring | iovss / iovdd | + | 8 kV | > 8 kV (non atteint) | — |
| ring | iovss / iovdd | - | 2 kV | 3 kV | I clamp IOPadIOVdd = 1.84 A (FAIL) |
| ring | iovss / vdd | + | 1 kV | 2 kV | V(iovss,vdd) = 5.94 V (FAIL) |
| ring | iovss / vdd | - | 0.5 kV | 0.75 kV | V(iovss,vdd) = 4.13 V (FAIL) |
| ring | iovss / vss | + | 2 kV | 3 kV | V(iovss,vss) = 4.5 V (FAIL) |
| ring | iovss / vss | - | 1 kV | 2 kV | V(iovss,vss) = 5.47 V (FAIL) |

Note : le HBM ring iovss− / iovdd et le HBM ring iovdd+ / iovss sont la même agression physique. Le balayage fin (2,1 à 2,8 kV) n'a été fait que sous le nom iovdd+ / iovss.

### Contrôle de validité : même banc avec les modèles d'antenne du PDK (dantenna/dpantenna)

| contexte | modèle | niveau | broche zappée / réf. | grandeur limitante | valeur | critère | verdict | note |
|---|---|---|---|---|---|---|---|---|
| seul | HBM | +2000 V | iovss / iovdd | V(iovdd,iovss) | 1.14e+03 V | ≤ 8 V | FAIL | modèle antenne PDK |
| seul | HBM | -2000 V | iovss / iovdd | V(iovdd,iovss) | 1.16e+03 V | ≤ 8 V | FAIL | modèle antenne PDK |
| seul | HBM | +2000 V | iovss / vss | V(iovss,vss) | 28.6 V | ≤ 4 V | FAIL | modèle antenne PDK ; run tronqué à 156 ns (max pris avant) |
| seul | HBM | -2000 V | iovss / vss | V(iovss,vss) | 28.6 V | ≤ 4 V | FAIL | modèle antenne PDK |

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
