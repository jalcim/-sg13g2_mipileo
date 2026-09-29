#!/bin/bash
# Regenerate netlists + decks, run every ESD deck, collect RES lines.
# Usage: run_all.sh [logdir]   (default /tmp/esd_logs)
set -e
HERE=$(cd "$(dirname "$0")" && pwd)
PDKD=${PDK_ROOT:-/home/lsaintecluque/IHP-Open-PDK}/${PDK:-ihp-sg13g2}
NGSPICE=${NGSPICE:-/home/lsaintecluque/local/bin/ngspice}
LOG=${1:-/tmp/esd_logs}; mkdir -p "$LOG"
python3 "$HERE/derive_netlists.py" "$PDKD/libs.ref/sg13g2_io/spice/sg13g2_io.spice" "$HERE"
python3 "$HERE/gen_decks.py" "$PDKD" "$HERE"
export OMP_NUM_THREADS=1
cat "$HERE/decks/LIST" "$HERE/decks/LIST_extra" | xargs -P ${JOBS:-8} -I{} sh -c \
  "timeout 1800 $NGSPICE -b '$HERE/decks/{}.spice' 2>&1 | tr '\r' '\n' | grep -v 'Reference value' > '$LOG/{}.log'"
grep -H '^RES' "$LOG"/*.log | sed 's|^.*/||' | sort > "$HERE/results_raw.txt"
echo "$(wc -l < "$HERE/results_raw.txt") result lines -> $HERE/results_raw.txt"
for f in $(cat "$HERE/decks/LIST" "$HERE/decks/LIST_extra"); do grep -q '^RES' "$LOG/$f.log" || echo "NO RESULT: $f"; done
grep -c "tran simulation(s) aborted" "$LOG"/*.log | grep -v ":0$" | sed "s/^/ABORTED RUNS (count per deck): /" || true
