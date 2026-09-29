# HS_TX_PD -- pre-driver d'une paire HS-TX (29/09/2026)

- Netlist simulee : `hs_tx_pd.sp` ; meme chose en Verilog structurel sg13g2 pour le top : `hs_tx_pd.v`.
- Banc : `sh tb/bench.sh <corner> [ui]` -> pre-driver + HS_TX v6 (`hs_tx_v6_top`, plot esd), 100 ohm + 14 pF,
  D alterne a 1 UI, OE = 1. Corners disponibles : tt_typ_25, ss_wcs_125, ff_bcs_m40 (modeles de HS_TX/tb/run_v6_champion*).
- Resultats du 29/09 (UI 1 ns) :

| corner | V_OD +/- (mV) | tR / tF (UI) | fronts IN_HS 10-90 | t_pd D->HS (D monte / D descend) | I_VDD total |
|---|---|---|---|---|---|
| tt_typ_25 | 179 / 184 | 0,234 / 0,245 | 137 ps | 251/246 ps ; 225/285 ps | 5,6 mA |
| ss_wcs_125 | 178 / 182 | 0,251 / 0,270 | 169 ps | 312/305 ps ; 276/353 ps | 5,7 mA |
| ff_bcs_m40 | 189 / 194 | 0,222 / 0,227 | 115 ps | 212/199 ps ; 181/236 ps | 5,6 mA |

- Limite connue : sur D descendant, HSP monte ~60-77 ps apres la descente de HSN (dissymetrie montee/descente
  des nand2 + inv_16) -> ~3 % d'UI de distorsion de rapport cyclique au croisement. Non corrige (tapeout).
- A faire au top : une instance par lane + lane horloge, placee contre les deux plots TX, cellules en dont_touch.
