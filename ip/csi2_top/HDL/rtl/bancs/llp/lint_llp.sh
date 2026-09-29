#!/bin/bash
# Garde de lint du RTL du LLP : Verilator -Wall sur chaque top, avec les dérogations justifiées de llp/lint.vlt,
# puis iverilog -Wall. Sort en erreur au premier avertissement, et si un des deux outils manque ou échoue.
# Depuis la racine du dépôt : bash 3_digital/rtl/tests/llp/lint_llp.sh (run_llp.py l'appelle aussi).
cd "$(dirname "$0")/../../llp" || exit 1
for outil in verilator iverilog; do
    command -v "$outil" > /dev/null || { echo "lint : $outil introuvable"; exit 2; }
done
TOPS="llp_ecc_gen llp_ecc_correct llp_ecc_check llp_crc_step llp_rx llp_tx llp_top llp_pix_rx llp_pix_tx llp_trame"
SOURCES="llp_*.v ../lm_cdc.v"      # lm_cdc.v : lm_sync_reset, instancié par llp_top
statut=0
for top in $TOPS; do
    sortie=$(verilator --lint-only -Wall --top-module "$top" lint.vlt $SOURCES 2>&1)
    rc=$?
    avert=$(echo "$sortie" | grep '^%')
    if [ $rc -ne 0 ] || [ -n "$avert" ]; then
        echo "== verilator $top (code $rc)"
        echo "${avert:-$sortie}"
        statut=1
    fi
done
sortie=$(iverilog -Wall -g2012 -o /dev/null $(for top in $TOPS; do echo "-s $top"; done) $SOURCES 2>&1)
rc=$?
if [ $rc -ne 0 ] || [ -n "$sortie" ]; then
    echo "== iverilog (code $rc)"
    echo "$sortie"
    statut=1
fi
[ $statut -eq 0 ] && echo "lint : aucun avertissement"
exit $statut
