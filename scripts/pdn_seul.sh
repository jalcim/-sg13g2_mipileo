#!/bin/bash
# Flot de Leo jusqu a GeneratePDN seulement, pour essayer une variante de PDN. Usage : scripts/pdn_seul.sh <tag> [-c VAR=VAL]...
set -e
cd "$(dirname "$0")/.."
TAG=$1; shift
nix develop --accept-flake-config -c scripts/gds_uniques.sh
export PYTHONHASHSEED=13
unset PYTHONPATH
exec nice -n 19 nix develop --accept-flake-config -c librelane librelane/config.yaml \
  --pdk ihp-sg13g2 --pdk-root /opt/nebula-eda/IHP-Open-PDK --manual-pdk \
  --run-tag "$TAG" --to OpenROAD.GeneratePDN "$@"
