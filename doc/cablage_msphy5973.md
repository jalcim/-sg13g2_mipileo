# Câblage de MSPHY5973 sur l'anneau 7efada02e (proposition de prompt-063-leo, 29/09/2026)

Mise à jour : brochage aligné sur la livraison 1 (sg13g2_26a 38f9686, prompt-061, maître du câblage).
Bandgap à l'est, tx_analog gardé au nord, pistes de polarisation en un net par côté (pol_<côté>_<piste>),
car les coins n'ont pas de piste. PG des dphy libre. La ligne « un seul bandgap au nord » et « pistes continues sur est et nord » ci-dessous sont remplacées par ceci.

Proposition à valider par 061 et le coordinateur.
Elle sert aux deux livraisons (même brochage, mêmes connexions).
Rien n'est inventé côté bloc : chaque ligne renvoie à une vue livrée.
Les trous sont listés à la fin, avec les options.

## Blocs et sources

| Bloc | Source | Taille (µm) | Rôle |
|---|---|---|---|
| MIPI_ring (plots, coins, bandgap) | ANALOG_DESIGN 7efada02e | plot 80 × 180, bandgap 160 × 180 | HS-RX et LP-RX dans MIPI_IOPadRX, HS-TX et LP-TX dans MIPI_IOPadTX |
| csi2_top | mipi 78524823 (t4 g13) | 1 368,5 × 1 387,2 | LM, LLP, renvoi |
| dphy_rx | DPHY_SM 501b142a8 | 360,7 × 302,0 | machines d'états RX, CMOS |
| sr16_rx4 | caelum a0f94510f | 189,4 × 315,0 | désérialiseur CML 4 lanes, ÷4 commun (CLK_W) |
| dphy_tx | DPHY_SM 501b142a8 | 285,9 × 302,0 | machines d'états TX, CMOS |
| sr16_tx × 4 | 501b142a8 | 355,3 × 91,4 | sérialiseur CML 8 vers 1, une lane par instance (proposition non validée par Lionel) |
| hs_tx_pd × 5 | ANALOG_DESIGN 25a940756 | cellules standard | pré-driver d'une paire TX, contre les plots |
| cml_to_cmos | CML_LIB (caelum) | 13,0 × 22,4 | CML différentiel vers CMOS |
| cmos_to_cml | CML_LIB (caelum) | voir LEF | CMOS vers CML différentiel, polarisé par POLN |

## Anneau

| Côté | Plots, dans l'ordre | Domaine |
|---|---|---|
| Est (RX) | iovdd_mipi, iovss_mipi, bandgap, rx_clk_p, rx_clk_n, rx_d0_p, rx_d0_n, rx_d1_p, rx_d1_n, rx_d2_p, rx_d2_n, rx_d3_p, rx_d3_n | IOVDD_MIPI |
| Nord (TX) | vdd, vss, tx_analog, tx_clk_p, tx_clk_n, tx_d0_p, tx_d0_n, tx_d1_p, tx_d1_n, tx_d2_p, tx_d2_n, tx_d3_p, tx_d3_n, clkin_n, clkin_p | IOVDD_MIPI |
| Ouest | iovdd, iovss, clk_sys, rst_n, renvoi_mode0, renvoi_mode1 | IOVDD |
| Sud | vdd_s, vss_s, en0, en1, en2, en3 | IOVDD |

- Lanes RX : MIPI_IOPadRX (plus de MIPI_IOPadAnalog ni de PADRES).
- Lanes TX : MIPI_IOPadTX.
- CLKIN P et N : MIPI_IOPadRX, pour que l'horloge TX entre en CML par le HS-RX du plot (à confirmer par Lionel).
- rx_analog et tx_analog de Léo : retirés (le bandgap et ses pistes remplacent la polarisation par plot). Plot de mesure à garder si Lionel le veut.
- MIPI_IOPadBandgap : un seul, au nord, sur le domaine MIPI. Sa broche PAD reçoit la résistance externe de 11 kΩ (commit 9ab74c027).
- Pistes POLN_RX, VB, PBIAS, PS, POLN : continues par aboutement sur tout le domaine MIPI (est et nord).
  Dans le Verilog, un net par piste, relié à tous les plots et fillers du domaine.
  Ouest et sud (domaine IOVDD) : pistes coupées par les MIPI_CornerBreaker, nets à part, laissés flottants (à confirmer par Lionel).
- Plots numériques : MIPI_IOPadIn, sortie P2C vers le cœur.

## Chaîne RX

| De | Vers | Remarque |
|---|---|---|
| rx_clk_p/OUT, rx_clk_n/OUT | sr16_rx4 CK_P, CK_N | CML, ruban apparié |
| rx_dk_p/OUT, rx_dk_n/OUT | sr16_rx4 Dk_P, Dk_N (k = 0..3) | CML, ruban apparié |
| rx_clk_p/OUT, rx_clk_n/OUT | cml_to_cmos, Y vers dphy_rx rx_clk | Fclk = 2 UI |
| rx_clk_p/P2C, rx_clk_n/P2C | dphy_rx clk_lp_p, clk_lp_n | LP-RX, CMOS |
| rx_dk_p/P2C, rx_dk_n/P2C | dphy_rx lp_p[k], lp_n[k] | LP-RX, CMOS |
| sr16_rx4 MOTi_P, MOTi_N (i = 0..31) | 32 cml_to_cmos, Y vers csi2_top mots[i] | mots[8p+7:8p] = lane p, bit 0 reçu le premier (sr16_mot.vhd) |
| sr16_rx4 CLK_W_P, CLK_W_N | cml_to_cmos, Y vers csi2_top clk_w | Wclk = HSCLK / 4 |
| dphy_rx hspr[3:0] | csi2_top hspr[3:0] | |
| dphy_rx {hspr[p], hsreq[p], stop[p]} | csi2_top statut_phy[3p+2:3p] | comme top_rx.vhd (501b142a8) |
| POLN (piste de l'anneau) | sr16_rx4 POLN | analogique, NDR 1,2 µm |
| dphy_rx term_en, hs_rx_en, clk_term_en, clk_rx_en, clk_stop, clk_miss | non connectés | MIPI_IOPadRX n'a pas d'entrée de commande (trou 3) |
| dphy_rx PG | à relier au bias (MACRO.md, l. 67), net à fixer par Lionel | trou 4 |

## Chaîne TX

| De | Vers | Remarque |
|---|---|---|
| clkin_p/OUT, clkin_n/OUT | CK_P, CK_N des 4 sr16_tx | horloge HS TX en CML |
| CK TX (cml_to_cmos) | dphy_tx clk, hs_tx_pd de la lane horloge (d) | |
| ÷4 TX | CLK_W des sr16_tx et du pont TX | n'existe pas (trou 2) |
| csi2_top fifo_tx_*, tx_init | pont TX | n'existe pas (trou 1) |
| pont TX, mots CMOS de la lane p | 8 cmos_to_cml par lane, vers sr16_tx[p] MOT0..7_P/N | 32 cmos_to_cml |
| sr16_tx[p] DOUT_P, DOUT_N | cml_to_cmos, Y vers hs_tx_pd[p] d | |
| dphy_tx hs_oe[p], lp_p[p], lp_n[p] | hs_tx_pd[p] oe, lpp, lpn | |
| dphy_tx clk_hs_oe, clk_lp_p, clk_lp_n | hs_tx_pd de la lane horloge | |
| hs_tx_pd hsp, hsn | IN_HS des plots P et N | au plus près des plots (note de 25a940756) |
| hs_tx_pd lpinp, lpinn | LP_IN des plots P et N | |
| PBIAS, PS (pistes) | plots TX | par aboutement |
| dphy_tx rst | rst_n (clk_sys) inversé, resynchronisé sur CK TX | |

## Trous et options

1. **Pont TX absent** entre csi2_top (fifo_tx_wr, wdata[31:0], wlanes[3:0], fin, full, tx_init) et dphy_tx (tx_request_hs, tx_ready_hs, hs_sync, hs_trail) plus sr16_tx (mots par lane au rythme de CLK_W).
   Il faut une FIFO asynchrone clk_sys vers Wclk TX, le démarrage du burst et l'insertion de 0xB8 et du trail.
   Le RTL existe en partie (lm_fifo_async_p.v, lm_demarrage_tx.v, écrit « côté PHY (Lionel) »).
   - A : écrire et durcir ce pont maintenant (plusieurs heures, bancs compris).
   - B : puce sans renvoi RX vers TX. fifo_tx_full tenu à 0, TX en LP seul, écart écrit en tête du README. Le critère « renvoi RX vers TX » tombe.
   - C : pont minimal en cellules standard dans le top, synthétisé par le flot de Léo (hors flot nebula, qui ne synthétise pas).
2. **÷4 TX absent** (signoff de sr16_tx : « le ÷4 TX n'existe pas encore »). Même sort que le trou 1.
3. **Commandes du récepteur absentes** : term_en et hs_rx_en n'attaquent rien. La terminaison de 100 Ω reste branchée en LP, ce qui charge les niveaux LP-01 et LP-10 de l'émetteur externe. À soumettre à Lionel.
4. **PG de dphy_rx et dphy_tx** (grille des miroirs des tempo) : net de polarisation à nommer par Lionel (POLN_RX, VB, PBIAS, PS ou POLN).
5. **Liberty absentes** pour dphy_rx, dphy_tx, sr16_rx4, sr16_tx : STA du top aveugle sur ces macros.
6. **Routage interne des plots RX et TX** : les en-têtes de ring_RX.tcl et ring_TX.tcl disent « pas encore de routage » et « placement seul ». Le commit 7efada02e dit « RX/TX raccordés ». Vérifier sur le GDS avant le LVS.
7. **Netlist des plots absente** : les COLLATERALS de MIPI_ring (7efada02e) n'ont ni SPICE ni CDL. Le LVS du top ne peut pas matcher les plots sans elle. À demander à Lionel.
8. **Alimentation des macros du kit CML** : sr16_rx4, sr16_tx, cml_to_cmos et cmos_to_cml ont VDD et VSS en Metal1 seulement. Le PDN du top (TopMetal1, TopMetal2) ne les atteint pas sans une grille de macro dédiée.
9. **PG provisoire** : dans le top, PG de dphy_rx et dphy_tx est relié à POLN_RX en attendant la réponse au trou 4.
