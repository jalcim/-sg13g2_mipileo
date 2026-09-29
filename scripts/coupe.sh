#!/bin/bash
# MODE COUPE (Jeremy, 29/09 17:21) : flot de Leo jusqu au GDS avec seal ring, sans signoff
# (ni STA, ni DRC, ni LVS, ni antennes, ni remplissage, ni densite). Usage : scripts/coupe.sh <tag>
set -e
cd "$(dirname "$0")/.."
TAG=${1:-p063_coupe}
SAUTS="OpenROAD.STAPrePNR OpenROAD.STAMidPNR OpenROAD.STAPostPNR OpenROAD.ResizerTimingPostCTS OpenROAD.ResizerTimingPostGRT
 OpenROAD.RCX OpenROAD.IRDropReport Checker.PowerGridViolations Checker.DisconnectedPins Checker.WireLength
 KLayout.Render KLayout.XOR Checker.XOR KLayout.Antenna Checker.KLayoutAntenna"
ARGS=""
for s in $SAUTS; do ARGS="$ARGS --skip $s"; done
export PYTHONHASHSEED=13
exec nice -n 19 nix develop --accept-flake-config -c librelane librelane/config.yaml \
  --pdk ihp-sg13g2 --pdk-root /opt/nebula-eda/IHP-Open-PDK --manual-pdk \
  --run-tag "$TAG" --to KLayout.SealRing $ARGS
