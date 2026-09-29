#!/bin/bash
# GDS des macros et de l anneau avec des sous-cellules a noms uniques (scripts/uniq_gds.py), dans librelane/gen/
# (ignore par git) : c est eux que librelane/config.yaml donne au flot. Appele par complet.sh et coupe.sh.
set -e
cd "$(dirname "$0")/.."
mkdir -p librelane/gen
u() { env -u PYTHONPATH python3 scripts/uniq_gds.py "$@"; }
u ip/csi2_top/GDS/csi2_top.gds librelane/gen/csi2_top.gds csi2_top "csi2_top"
u ip/dphy_sm/GDS/dphy_rx.gds librelane/gen/dphy_rx.gds dphy_rx "dphy_rx"
u ip/dphy_sm/GDS/dphy_tx.gds librelane/gen/dphy_tx.gds dphy_tx "dphy_tx"
for m in sr16_rx4 sr16_tx cml_to_cmos cmos_to_cml cml_gate2; do
  u ip/$m/GDS/${m}_alim.gds librelane/gen/$m.gds $m "$m"
done
u ip/CSI2_DPHY_RING/GDS/MIPI_ring.gds librelane/gen/MIPI_ring.gds MIPI_ring "MIPI_.*"
# Controle : plus aucune sous-cellule homonyme au contenu different (cellules standard du PDK et bondpad compris).
SC=/opt/nebula-eda/IHP-Open-PDK/ihp-sg13g2/libs.ref/sg13g2_stdcell/gds/sg13g2_stdcell.gds
env -u PYTHONPATH python3 scripts/homonymes.py librelane/gen/*.gds $SC ip/sg13g2_bondpad_70x70_novias/gds/bondpad_70x70_novias.gds | tee librelane/gen/homonymes.txt
grep -q " 0 en conflit" librelane/gen/homonymes.txt
