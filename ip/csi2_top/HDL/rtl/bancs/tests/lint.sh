#!/usr/bin/env bash
# Lint du csi2_top (29/09/2026) : Verilator -Wall et Icarus -Wall, sources de construit.py (SHA figés), defines du
# montage figé, llp_pix_regles.vh inclus depuis sources/llp. Dérogations : sources/lm/lint.vlt, sources/llp/lint.vlt,
# tests/lint.vlt.   bash 3_digital/rtl/csi2_top/tests/lint.sh   (après construit.py)
# PARAMS="DEBUG=0" : paramètres passés à Verilator (-G) et à Icarus (-P).
set -u
ICI="$(cd "$(dirname "$0")" && pwd)"
TOPD="$(dirname "$ICI")"
F="$TOPD/sources/fichiers.f"
[ -f "$F" ] || { echo "sources absentes : lancer construit.py"; exit 2; }
D="-DLM_FIFO_ASYNC_P_REMPLACE -DLM_FIFO_SYNC_P_REMPLACE"
SORTIE="${SORTIE:-$TOPD/build/lint}"
mkdir -p "$SORTIE"
G=""; P=""
for x in ${PARAMS:-}; do G="$G -G$x"; P="$P -Pcsi2_top.$x"; done
echo "== verilator --lint-only -Wall"
verilator --lint-only -Wall $D $G -I"$TOPD/sources/llp" --top-module csi2_top "$TOPD/sources/lm/lint.vlt" \
    "$TOPD/sources/llp/lint.vlt" "$ICI/lint.vlt" $(cat "$F") > "$SORTIE/verilator.txt" 2>&1
v=$?
cat "$SORTIE/verilator.txt"
echo "verilator : code $v, $(grep -c '^%Warning' "$SORTIE/verilator.txt") avertissements, $(grep -c '^%Error' "$SORTIE/verilator.txt") erreurs"
echo "== iverilog -Wall"
iverilog -Wall -g2012 $D $P -I"$TOPD/sources/llp" -s csi2_top -o "$SORTIE/top.vvp" $(cat "$F") > "$SORTIE/iverilog.txt" 2>&1
i=$?
cat "$SORTIE/iverilog.txt"
echo "iverilog : code $i, $(grep -c -i 'warning' "$SORTIE/iverilog.txt") avertissements"
n=$(grep -c '^%' "$SORTIE/verilator.txt")
if [ $v -eq 0 ] && [ $i -eq 0 ] && [ "$n" -eq 0 ]; then echo "lint : aucun avertissement de Verilator"; exit 0; fi
exit 1
