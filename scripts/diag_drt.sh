#!/bin/bash
# Diagnostic du routage detaille : rejoue OpenROAD.DetailedRouting sur l etat d entree d un run
# (pas 38), avec une seule iteration d optimisation, pour obtenir tout de suite le rapport des
# violations (<tag>/…-detailedrouting/drt-run-0/MSPHY5973.drc). Usage : scripts/diag_drt.sh <run source> <tag>
set -e
cd "$(dirname "$0")/.."
SRC=${1:-p063_coupe5}
TAG=${2:-p063_diag_drt}
ETAT=$(ls librelane/runs/$SRC/*-openroad-stamidpnr-3/state_out.json)
export PYTHONHASHSEED=13
exec nice -n 19 nix develop --accept-flake-config -c librelane librelane/config.yaml \
  --pdk ihp-sg13g2 --pdk-root /opt/nebula-eda/IHP-Open-PDK --manual-pdk \
  --run-tag "$TAG" --only OpenROAD.DetailedRouting -i "$ETAT" -c DRT_OPT_ITERS=1
