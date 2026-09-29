#!/bin/bash
# Flot de Leo complet (prompt 066, mode coupe leve) : seal ring, remplissage, densite, DRC KLayout, antennes,
# LVS netgen en cellules abstraites, STA. Seul le DRC Magic est saute : le critere est le DRC KLayout et le precheck
# officiel IHP (scripts/precheck.sh), lance a part sur le GDS final. Usage : scripts/complet.sh <tag>
# PYTHONPATH de nebula (/opt/nebula-eda/python) retire : son module klayout ne se charge pas dans le shell Nix.
set -e
cd "$(dirname "$0")/.."
TAG=${1:-p063_complet}
python3 scripts/coquilles_lvs.py librelane/coquilles_lvs.spice
export PYTHONHASHSEED=13
unset PYTHONPATH
exec nice -n 19 nix develop --accept-flake-config -c librelane librelane/config.yaml \
  --pdk ihp-sg13g2 --pdk-root /opt/nebula-eda/IHP-Open-PDK --manual-pdk \
  --run-tag "$TAG" --save-views-to "runs_vues/$TAG" --skip Magic.DRC --skip Checker.MagicDRC --skip KLayout.Render
