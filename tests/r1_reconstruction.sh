#!/usr/bin/env bash
# R1 / V5 : reconstruction intégrale (destroy puis up), sans aucune commande manuelle ensuite.
# Usage : ./tests/r1_reconstruction.sh            (NB_APP=4 ./tests/r1_reconstruction.sh : 4 serveurs, test de R3)
# ATTENTION : détruit toutes les VM, base de données comprise.
cd "$(dirname "$0")/.." || exit 1
OUT=${OUT:-/tmp/resultats-bf}; mkdir -p "$OUT"

echo "début : $(date '+%Y-%m-%d %H:%M:%S') (NB_APP=${NB_APP:-2})"
T0=$(date +%s)
vagrant destroy -f > "$OUT/r1_destroy.log" 2>&1
echo "destroy terminé en $(( $(date +%s) - T0 )) s"
T1=$(date +%s)
vagrant up > "$OUT/r1_up.log" 2>&1; RC=$?
T2=$(date +%s)
echo "vagrant up : code de sortie $RC, durée $(( T2 - T1 )) s"
echo "DURÉE TOTALE destroy + up : $(( T2 - T0 )) s ($(( (T2 - T0) / 60 )) min $(( (T2 - T0) % 60 )) s)"
echo "--- lignes clés de vagrant up :"
grep -E "prête|en réplication|prêt \(|Error|error:|failed|FAILED|Vagrant cannot" "$OUT/r1_up.log" | cut -c1-150
echo "--- états :"; vagrant status 2>&1 | sed -n 3,10p
exit "$RC"
