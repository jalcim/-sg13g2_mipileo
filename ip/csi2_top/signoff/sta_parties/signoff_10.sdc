# csi2_top --renvoi (prompt 056) : csi2_top.sdc, renvoi_mode ajouté comme enable (construit_renvoi.py)
# Contraintes du csi2_top (29/09/2026) : SDC du bloc v2 (rtl/integration/lm_llp_top.sdc) étendu aux ports du top
# complet, mêmes règles. Changements, et seulement eux :
# - llp_rx_*, llp_tx_* ne sont plus des ports (reliés dans le top à llp_pix_rx, llp_trame et llp_pix_tx : chemins
#   internes à Clk Système) ;
# - entrées en plus (domaine clk, 20 %) : tx_req_*, tx_pix_* (application TX, llp_pix_tx) ; cnt_gel remplace
#   llp_cnt_gel (asynchrone, synchronisé dans llp_top et dans le top : chemin ignoré comme rst_n) ;
# - sorties en plus (domaine clk, 20 %) : rx_* (pixels), trame_* (trame, compteurs compris), tx_req_ready,
#   tx_pix_ready, tx_evt_*, tx_init_done, dbg_*, llp_cnt_* ; statut, etat, err_sync, erreur_fifo, rx_erreur_config et
#   tx_erreur ne sont plus des ports (repris dans dbg_erreur, registré) ; verrou devient dbg_verrou.
# Règles reprises telles quelles : E/S à 20 % de la période de leur horloge, cellule d'attaque sg13g2_buf_4/X, charge
# 6 fF, incertitude 0,25 ns en setup et 0,05 ns en hold, transition 0,15 ns, dérive ±5 %. Les deux horloges prennent la
# même période. Aucun passage d'horloge ajouté (pixel-byte et trame sur Clk Système).

# période du tapeout, 7,992 ns (choix 24 et 28) ; les scripts de mesure la remplacent par celle de leurs runs
set periode 7.992
create_clock [get_ports clk]   -name clk   -period $periode
create_clock [get_ports clk_w] -name clk_w -period $periode
# Passages entre W et Clk Système : comme lm_llp_top.sdc (chaque chemin borné à une période de l'horloge d'arrivée,
# sans le retard des arbres d'horloge ; pas de contrainte de hold entre domaines asynchrones).
set_max_delay $periode -ignore_clock_latency -from [get_clocks clk_w] -to [get_clocks clk]
set_max_delay $periode -ignore_clock_latency -from [get_clocks clk]   -to [get_clocks clk_w]
set_false_path -hold -from [get_clocks clk_w] -to [get_clocks clk]
set_false_path -hold -from [get_clocks clk]   -to [get_clocks clk_w]

# ports de chaque domaine, nommés
set entrees   [get_ports {enable[*] renvoi_mode[*] fifo_tx_full statut_phy[*] tx_req_valid tx_req_vc[*] tx_req_dt[*] tx_req_width[*] tx_pix_valid tx_pix_data[*] tx_pix_nb[*]}]
set sorties   [get_ports {fifo_tx_wr fifo_tx_wdata[*] fifo_tx_wlanes[*] fifo_tx_fin tx_init rx_* rx_*[*] trame_* trame_*[*] tx_req_ready tx_pix_ready tx_evt_width tx_evt_nb tx_init_done dbg_verrou[*] dbg_erreur dbg_evt llp_cnt_*[*]}]
set entrees_w [get_ports {mots[*]}]
set_input_delay  [expr $periode * 0.20] -clock [get_clocks clk]   $entrees
set_output_delay [expr $periode * 0.20] -clock [get_clocks clk]   $sorties
set_input_delay  [expr $periode * 0.20] -clock [get_clocks clk_w] $entrees_w

set_max_fanout 10 [current_design]
set_driving_cell -lib_cell sg13g2_buf_4 -pin X $entrees
set_driving_cell -lib_cell sg13g2_buf_4 -pin X $entrees_w
set_driving_cell -lib_cell sg13g2_buf_4 -pin X [get_ports {hspr[*]}]
set_driving_cell -lib_cell sg13g2_buf_4 -pin X [get_ports {clk clk_w}]
set_driving_cell -lib_cell sg13g2_buf_4 -pin X [get_ports cnt_gel]
set_load 0.006 [all_outputs]

set_clock_uncertainty -setup 0.25 [all_clocks]
set_clock_uncertainty -hold 0.05 [all_clocks]
set_clock_transition 0.15 [all_clocks]
set_timing_derate -early 0.90
set_timing_derate -late 1.10

# Chemins ignorés, mêmes règles que lm_llp_top.sdc ; cnt_gel asynchrone, pris par deux bascules de synchronisation
# dans llp_top et dans le top
set_false_path -from [get_ports rst_n]
set_false_path -from [get_ports cnt_gel]
set_false_path -from [get_ports {enable[*]}]
# renvoi RX -> TX (prompt 056) : broches statiques, changées sous reset, comme enable
set_false_path -from [get_ports {renvoi_mode[*]}]
set_false_path -from [get_ports {statut_phy[*]}]
set_false_path -from [get_ports {hspr[*]}]

set_propagated_clock [all_clocks]
