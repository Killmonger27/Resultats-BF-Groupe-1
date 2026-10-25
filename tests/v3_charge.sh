#!/usr/bin/env bash
# V3 : charge. 1 passe de chauffe non comptée puis 5 passes de ab -n 2000 -c 50 sur /resultat.
# Usage : ./tests/v3_charge.sh n2        (étiquette libre : n2, n4... ; sorties brutes dans $OUT/v3_<étiquette>)
cd "$(dirname "$0")/.." || exit 1
L=${1:-n2}; OUT=${OUT:-/tmp/resultats-bf}; D=$OUT/v3_$L; mkdir -p "$D"
URL='http://192.168.56.5/resultat?matricule=BF000001'
echo "V3 ($L) : chauffe non comptée :"; ab -q -n 2000 -c 50 "$URL" 2>&1 | grep -E "Requests per second|Failed requests" | tr -s ' '
echo "passe | req/s | latence moy (ms) | p99 (ms) | échecs | non-2xx | CPU hôte (user+sys %)"
for p in 1 2 3 4 5; do
  top -l 3 -s 2 -n 0 2>/dev/null | grep "CPU usage" | tail -1 > "$D/cpu_$p.txt" &
  ab -q -n 2000 -c 50 "$URL" > "$D/ab_$p.txt" 2>&1; wait
  rps=$(awk '/Requests per second/{print $4}' "$D/ab_$p.txt"); lat=$(awk '/Time per request.*\(mean\)$/{print $4; exit}' "$D/ab_$p.txt")
  p99=$(awk '$1=="99%"{print $2}' "$D/ab_$p.txt"); fail=$(awk '/Failed requests/{print $3}' "$D/ab_$p.txt")
  nx=$(awk '/Non-2xx/{print $3}' "$D/ab_$p.txt"); cpu=$(awk '{gsub("%","");print $3+$5}' "$D/cpu_$p.txt")
  echo "  $p   | $rps | $lat | $p99 | $fail | ${nx:-0} | $cpu"
done
for p in 1 2 3 4 5; do awk '/Requests per second/{print $4}' "$D/ab_$p.txt"; done | sort -n | awk '{a[NR]=$1} END{printf "médiane/min/max req/s : %.1f / %.1f / %.1f\n", a[int((NR+1)/2)], a[1], a[NR]}'
