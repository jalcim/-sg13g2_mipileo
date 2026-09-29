#!/bin/bash
# Lance une commande hors de la session ssh (systemd-run --user, Linger actif) : elle survit a la fermeture de ssh.
# Le 29/09 a 21:10, la fin des sessions ssh a tue tous les runs lances par nohup. Usage : scripts/lancer.sh <unite> <journal> <commande...>
set -e
UNITE=$1; JOURNAL=$2; shift 2
exec systemd-run --user --collect --unit="$UNITE" -p WorkingDirectory="$PWD" bash -lc "$* > $JOURNAL 2>&1"
