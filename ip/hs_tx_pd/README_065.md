# Macro hs_tx_pd (prompt 066)

Pré-driver d'une paire HS-TX, vers les plots MIPI_IOPadTX P et N.

Netlist de Lionel, ANALOG_DESIGN 25a940756 (`2_analog/HS_TX_PD/hs_tx_pd.v`), copiée telle quelle : md5 7afdb5e7bcccc631fe624eaa319aea31.

Onze cellules standard sg13g2, chemins P et N équilibrés à la main.

## Fonction

- `hsp` = `oe` et non `d`, vers IN_HS du plot P.
- `hsn` = `oe` et `d`, vers IN_HS du plot N.
- `lpinp` = non (`lpp` et non `oe`), vers LP_IN du plot P.
- `lpinn` = non (`lpn` et non `oe`), vers LP_IN du plot N.
- `oe` = 0 : dérivations bloquées, les plots suivent `lpp` et `lpn`.
- `oe` = 1 : LP-00 sous le HS, le plot P suit `d`.

## Dans les puces

- Cinq instances par puce : les quatre lanes de données et la lane d'horloge, communes aux deux puces.
- `d` : DOUT de `sr16_tx` (lanes de données) ou l'horloge de ligne (lane d'horloge), `oe` : `hs_oe` de `dphy_tx`, `lpp` et `lpn` : `lp_p` et `lp_n` de `dphy_tx`.
- Chaque instance au plus près de ses deux plots : `hsp` et `hsn` chargent chacun environ 0,4 pF de grille.

## Macro

- `macro/config_hs_tx_pd.json` : élaboration seule (`SYNTH_ELABORATE_ONLY`), aucune réparation ni optimisation du placeur, cellules intouchables (`RSZ_DONT_TOUCH_RX`), pas d'arbre d'horloge.
- Boîte de 40,32 × 45,36 µm, marges de deux rangées en haut et en bas et de 5,76 µm sur les côtés : cœur de 28,8 × 30,24 µm (8 rangées de 3,78 µm) pour 143 µm² de cellules. Alimentation en TopMetal1 seul, TopMetal2 laissé à la puce.
- Premier run (hs_tx_pd_R1_13) : boîte de 30,72 × 30,24 µm, les marges par défaut (4 rangées en haut et en bas) ne laissaient aucune rangée (IFP-0002).
- Entrées à l'ouest, sorties à l'est (côté plots).
- `macro/hs_tx_pd.sdc` : horloge virtuelle d'une UI, charges des plots.

## Run de la macro (hs_tx_pd_R1_13c, 9e897ffcc, 29/09/2026 18:52 UTC)

Vues dans `COLLATERALS/` (GDS, LEF, netlists, Liberty, SDF et SPEF des trois coins, SPICE extrait, métriques), empreintes dans `COLLATERALS/MANIFESTE.md5`.

- Boîte 40,32 × 45,36 µm, bornes en Metal3, alimentation VPWR et VGND en TopMetal1.
- DRC Magic 0, DRC KLayout 0, DRC du routeur 0, LVS sans écart, antennes 0.
- Setup : +0,355 ns au coin lent (borne d'une UI de `d` aux sorties), hold ≥ +0,028 ns.
- Latence de `d` aux plots avec 0,4 pF : 0,65 ns au plus au coin lent, la même pour toutes les lanes.

Écart P/N au croisement (`tests/appariement.py`, OpenSTA sur la netlist routée et le SPEF) :

| Coin | d monte : écart | d descend : écart | Pentes de hsp et hsn |
|---|---|---|---|
| lent | 90 ps | 167 ps | 163 à 204 ps |
| typique | 54 ps | 106 ps | 108 à 137 ps |
| rapide | 43 ps | 85 ps | 79 à 99 ps |

Sur `d` descendant, `hsp` monte après la descente de `hsn` : dissymétrie connue de Lionel (60 à 77 ps en SPICE), plus forte en STA. Point remonté à Lionel, netlist inchangée.

Avertissement restant : deux pentes au-dessus de la borne de 250 ps de `hs_tx_pd.sdc`, au coin lent seulement, sur le nœud interne `np` (sortie de `xnp`, `sg13g2_nand2_2`, entrée de `xop`, `sg13g2_inv_16`) : 250,1 et 250,2 ps.

Ce n'est pas sur `hsp` ni `hsn` (163 à 204 ps sous 0,4 pF). C'est le dimensionnement de Lionel (nand2_2 devant inv_16), dépassement de 0,2 ps sur une borne que j'ai choisie (un quart d'UI), sans effet à 1 Gb/s : laissé tel quel.

## Vérification

`tests/verifie.sh` : copie identique à 25a940756, 16 combinaisons des entrées sur les modèles sg13g2 contre la fonction ci-dessus.
