# Macro csi2_top : vues d'intégration (livraison à Léo)

Livraison du prompt 060, écrite le 29/09/2026 à 19:45 UTC par exporte.py.

## Provenance

- Run : `tapeout_s3r_t4_R1_13_d60` (nebula:/home/jalcim/depots/p053_s3r_t4/3_digital/rtl/csi2_top/renvoi/runs/tapeout_s3r_t4_R1_13_d60).
- Montage : worktree p053_s3r_t4, commit 47cfb1acc751e7c911d4a523737d5a942e49d208 ; construit.py --llp-rx v2 --renvoi ; llp_trame t4 (md5 9cafb2e63530ee037724831e73336a20, commit f742941515f15f047c71eb8a2f83a778e3affb65).
- Vues prises dans : final/.
- Netlist : md5 5d483d58b352b075772b9933c5676069.
- Die : 1368.515 × 1387.235 µm (LEF).

## Contenu

- Lane Management (bloc v2 + SYNC3, ARM_N = 8), LLP (ECC, CRC, VC, DT, compteurs), pixel-byte RX et TX, contrôle de trame (llp_trame), renvoi RX → TX (renvoi_mode[1:0] : 00 application, 01 LM, 10 LLP, 11 pixel-byte ; statut en paquet générique).
- Horloges : `clk` = Clk Système, 125,125 MHz (période 7,992 ns) ; `clk_w` = horloge de mots du PHY RX, 125 MHz au plus. Passages entre les deux : FIFO asynchrone du LM et synchroniseurs à trois bascules.
- Reset : `rst_n` asynchrone actif bas, relâché de façon synchrone dans la macro.
- `renvoi_mode` est statique : il ne change que sous reset.

## Contraintes pour l'intégration

- `clk_w` : 125 MHz au plus, et jamais d'horloge hors HS. Dette D28 : le /4 de sr16_rx oscille à ~1 GHz hors HS, à portillonner côté PHY.
- SDC de la macro : `DOC/csi2_top.sdc` (E/S à 20 % de la période, cellule d'attaque sg13g2_buf_4, charge 6 fF, incertitude 0,25 ns).
- Rails de la macro : `VGND` (ground), `VPWR` (power). À relier à VDD et VSS du cœur.
- SPEF et SDF sont compressés (gzip) : plus de 100 Mo en clair.

## Ports

### Broches de la puce (statiques ou horloges) : à relier aux broches

| Port | Sens | Largeur | Bord |
|---|---|---|---|
| `clk` | input | 1 | nord |
| `rst_n` | input | 1 | nord |
| `enable` | input | 4 | nord |
| `renvoi_mode` | input | 2 | nord |

### Depuis le RX de Lionel (SR16_RX4 et machine d'états) : à relier au PHY RX

| Port | Sens | Largeur | Bord |
|---|---|---|---|
| `clk_w` | input | 1 | ouest |
| `hspr` | input | 4 | ouest |
| `mots` | input | 32 | ouest |
| `statut_phy` | input | 12 | ouest |

### Vers le TX de Lionel : à relier au PHY TX

| Port | Sens | Largeur | Bord |
|---|---|---|---|
| `fifo_tx_fin` | output | 1 | ouest |
| `fifo_tx_full` | input | 1 | ouest |
| `fifo_tx_wr` | output | 1 | ouest |
| `tx_init` | output | 1 | ouest |
| `fifo_tx_wdata` | output | 32 | ouest |
| `fifo_tx_wlanes` | output | 4 | ouest |

### Application, entrées sans broche dans ce tapeout : **à tenir à 0 par des cellules tie**

| Port | Sens | Largeur | Bord |
|---|---|---|---|
| `cnt_gel` | input | 1 | nord |
| `tx_pix_valid` | input | 1 | sud |
| `tx_req_valid` | input | 1 | sud |
| `tx_pix_data` | input | 112 | sud |
| `tx_pix_nb` | input | 4 | sud |
| `tx_req_dt` | input | 6 | sud |
| `tx_req_vc` | input | 2 | sud |
| `tx_req_width` | input | 16 | sud |

### Application, sorties sans broche dans ce tapeout : **à laisser libres**

| Port | Sens | Largeur | Bord |
|---|---|---|---|
| `dbg_erreur` | output | 1 | nord |
| `dbg_evt` | output | 1 | nord |
| `rx_eol` | output | 1 | est |
| `rx_pix_valid` | output | 1 | est |
| `rx_short_ecc_corrected` | output | 1 | est |
| `rx_short_sot_err` | output | 1 | est |
| `rx_short_valid` | output | 1 | est |
| `rx_sol` | output | 1 | est |
| `rx_sol_ecc_corrected` | output | 1 | est |
| `rx_sol_sot_err` | output | 1 | est |
| `trame_fe` | output | 1 | ouest |
| `trame_fe_ok` | output | 1 | ouest |
| `trame_fs` | output | 1 | ouest |
| `trame_late` | output | 1 | ouest |
| `trame_slots_pleins` | output | 1 | ouest |
| `tx_evt_nb` | output | 1 | sud |
| `tx_evt_width` | output | 1 | sud |
| `tx_init_done` | output | 1 | sud |
| `tx_pix_ready` | output | 1 | sud |
| `tx_req_ready` | output | 1 | sud |
| `dbg_verrou` | output | 4 | nord |
| `llp_cnt_burst` | output | 16 | nord |
| `llp_cnt_crc` | output | 16 | nord |
| `llp_cnt_dt` | output | 16 | nord |
| `llp_cnt_ecc_corrected` | output | 16 | nord |
| `llp_cnt_ecc_double` | output | 16 | nord |
| `llp_cnt_ok` | output | 16 | nord |
| `llp_cnt_sot_err` | output | 16 | nord |
| `llp_cnt_trunc` | output | 16 | nord |
| `rx_eol_status` | output | 3 | est |
| `rx_pix_data` | output | 84 | est |
| `rx_pix_nb` | output | 3 | est |
| `rx_short_data` | output | 16 | est |
| `rx_short_dt` | output | 6 | est |
| `rx_short_vc` | output | 2 | est |
| `rx_sol_dt` | output | 6 | est |
| `rx_sol_fmt` | output | 3 | est |
| `rx_sol_vc` | output | 2 | est |
| `rx_sol_wc` | output | 16 | est |
| `trame_cnt_err` | output | 16 | nord |
| `trame_cnt_ligne` | output | 16 | nord |
| `trame_cnt_ok` | output | 16 | nord |
| `trame_err_end` | output | 3 | ouest |
| `trame_err_end_vc` | output | 2 | ouest |
| `trame_err_hdr` | output | 7 | ouest |
| `trame_err_hdr_vc` | output | 2 | ouest |
| `trame_late_mask` | output | 4 | ouest |
| `trame_loss` | output | 3 | ouest |
| `trame_loss_mask` | output | 4 | ouest |
| `trame_numero` | output | 16 | ouest |
| `trame_vc` | output | 2 | ouest |

### Alimentation : rails de la macro

| Port | Sens | Largeur | Bord |
|---|---|---|---|
| `VGND` | inout | 1 | ? |
| `VPWR` | inout | 1 | ? |

## Signoff

- DRC Magic : 0 violation(s).
- DRC KLayout : 0 violation(s).
- LVS : Circuits match uniquely.
- antennes : 0 net(s) en violation, 0 broche(s).
- setup au pire (ns) : ss −3,215, tt +0,803, ff +3,129 ; hold au pire : ss +0,162, tt +0,185, ff +0,097.

## Timing par mode du renvoi (STA de signoff, OCV ±5 %, set_case_analysis sur renvoi_mode)

| Mode | Coin | Setup (ns) | Hold (ns) | Fréquence max de clk | Pire chemin |
|---|---|---|---|---|---|
| 00 | lent (1,08 V, 125 °C) | −1,615 | +0,171 | 104,1 MHz | `trame.e_vc[1]` → `_000943_` |
| 01 | lent (1,08 V, 125 °C) | −1,615 | +0,329 | 104,1 MHz | `trame.e_vc[1]` → `_000943_` |
| 10 | lent (1,08 V, 125 °C) | −1,615 | +0,329 | 104,1 MHz | `trame.e_vc[1]` → `_000943_` |
| 11 | lent (1,08 V, 125 °C) | −3,215 | +0,329 | 89,2 MHz | `rx_sol_wc[4]` → `u_renvoi.g_n3.u_n3.r_entrer[15]` |
| 00 | typique (1,20 V, 25 °C) | +1,858 | +0,185 | ≥ 125,125 MHz | `u_renvoi.g_n3.u_n3.r_sortir[4]` → `u_renvoi.g_n3.u_n3.r_file[17]` |
| 01 | typique (1,20 V, 25 °C) | +1,858 | +0,185 | ≥ 125,125 MHz | `u_renvoi.g_n3.u_n3.r_sortir[4]` → `u_renvoi.g_n3.u_n3.r_file[17]` |
| 10 | typique (1,20 V, 25 °C) | +1,858 | +0,185 | ≥ 125,125 MHz | `u_renvoi.g_n3.u_n3.r_sortir[4]` → `u_renvoi.g_n3.u_n3.r_file[17]` |
| 11 | typique (1,20 V, 25 °C) | +0,803 | +0,185 | ≥ 125,125 MHz | `rx_sol_wc[4]` → `u_renvoi.g_n3.u_n3.r_entrer[15]` |
| 00 | rapide (1,32 V, −40 °C) | +3,859 | +0,097 | ≥ 125,125 MHz | `trame.e_vc[1]` → `_000943_` |
| 01 | rapide (1,32 V, −40 °C) | +3,859 | +0,097 | ≥ 125,125 MHz | `trame.e_vc[1]` → `_000943_` |
| 10 | rapide (1,32 V, −40 °C) | +3,859 | +0,097 | ≥ 125,125 MHz | `trame.e_vc[1]` → `_000943_` |
| 11 | rapide (1,32 V, −40 °C) | +3,129 | +0,097 | ≥ 125,125 MHz | `rx_sol_wc[4]` → `u_renvoi.g_n3.u_n3.r_entrer[15]` |

## Limitations connues

- Au coin lent (1,08 V, 125 °C), la macro ne tient pas 125,125 MHz : setup −1,615 ns en modes 00, 01 et 10 (104,1 MHz au plus), −3,215 ns en mode 11, renvoi N3 (89,2 MHz au plus). Au coin typique elle tient : +1,858 ns en modes 00 à 10, +0,803 ns en mode 11. Livrée ainsi par dérogation de Jérémy (29/09/2026 16:34 UTC, choix 58).
- La marge de 20 % (1,598 ns au coin lent) n'est pas tenue (dette D26).
- Renvoi, statut au niveau N2 : 36 cas sur 720 des bancs du renvoi échouent avec erreurs injectées (statut relu 3 fois pour 2 justes), défaut du renvoi antérieur à cette macro (dette D33).
- llp_trame (variante t4) : les sorties trame_* et les compteurs de trame sortent un cycle plus tard que dans l'origine (accord de la session principale, 29/09/2026 14:02 UTC).

## Manques

- Aucun.
