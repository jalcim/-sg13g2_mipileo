#!/bin/bash
# Precheck de REJET d'IHP avec les options de la CI officielle (veille Open-Silicon-MPW, TPU9012), comme
# msphy4263-precheck de la livraison 1. Usage : scripts/precheck.sh <gds> <dossier de sortie>
set -e
cd "$(dirname "$0")/.."
GDS=$(realpath "$1")
SORTIE=$(realpath -m "$2")
mkdir -p "$SORTIE"
nice -n 19 nix develop --accept-flake-config -c env -u PYTHONPATH python3 \
  /opt/nebula-eda/IHP-Open-PDK/ihp-sg13g2/libs.tech/klayout/tech/drc/run_drc.py --path="$GDS" \
  --topcell=MSPHY5973 --precheck_drc --no_offgrid --no_recommended --density_thr=8 --no_angle \
  --disable_extra_rules --run_dir="$SORTIE" > "$SORTIE/precheck.log" 2>&1 && rc=0 || rc=$?
grep -aE "Violated rules|Check Passed|Check Failed" "$SORTIE/precheck.log" || true
exit $rc
