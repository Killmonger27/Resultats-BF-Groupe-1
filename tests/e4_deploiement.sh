#!/usr/bin/env bash
# Démonstration E4 : mise à jour complète pendant une charge, sans requête en erreur.
# Usage : ./tests/e4_deploiement.sh [nouvelle_version]     (ex. ./tests/e4_deploiement.sh 2.0)
# Cible : la VIP (BASE_URL=... pour changer). Sortie brute : resultats/e4/e4_<date>.txt
set -uo pipefail
cd "$(dirname "$0")/.."

VIP=$(awk '/^vip:/{print $2}' config/noeuds.yml)
BASE_URL="${BASE_URL:-http://$VIP}"
CLIENTS="${CLIENTS:-8}"          # clients parallèles
PAUSE="${PAUSE:-0.05}"           # pause entre deux appels d'un client
[ -n "${1:-}" ] && echo "$1" > app/VERSION
mkdir -p resultats/e4
SORTIE="resultats/e4/e4_$(date +%Y%m%d-%H%M%S).txt"
TMP=$(mktemp -d)
trap 'kill $(jobs -p) 2>/dev/null; rm -rf "$TMP"' EXIT

client() {   # une ligne "<corps> <code http>" par appel
  while :; do
    curl -s -m 2 -w ' %{http_code}\n' "$BASE_URL/info"
    sleep "$PAUSE"
  done
}

echo "Contexte : $(date '+%Y-%m-%dT%H:%M:%S%z'), commit $(git rev-parse --short HEAD), cible $BASE_URL, $CLIENTS clients, version $(cat app/VERSION)" | tee "$SORTIE"
for i in $(seq "$CLIENTS"); do client > "$TMP/c$i.log" & done
sleep 5                                           # référence avant la mise à jour
echo "--- déploiement ---" | tee -a "$SORTIE"
./scripts/deploy.sh 2>&1 | tee -a "$SORTIE"
CODE=${PIPESTATUS[0]}
sleep 5                                           # référence après la mise à jour
kill $(jobs -p) 2>/dev/null; wait 2>/dev/null; sleep 2
cat "$TMP"/c*.log > "$TMP/tout.log"

TOTAL=$(wc -l < "$TMP/tout.log" | tr -d ' ')
ERREURS=$(grep -vc ' 200$' "$TMP/tout.log" || true)
if [ "$ERREURS" = 0 ] && [ "$CODE" = 0 ] && [ "$TOTAL" -gt 0 ]; then VERDICT="E4 : OK"; RC=0; else VERDICT="E4 : KO"; RC=1; fi
{
  echo "--- résultat ---"
  echo "requêtes : $TOTAL, en erreur : $ERREURS, code de sortie du déploiement : $CODE"
  echo "répartition (appels, serveur, version) :"
  grep -o '"hote": "[^"]*", "version": "[^"]*"' "$TMP/tout.log" | sort | uniq -c
  echo "codes HTTP :"
  awk '{print $NF}' "$TMP/tout.log" | sort | uniq -c
  echo "premières lignes en erreur :"
  grep -v ' 200$' "$TMP/tout.log" | head -10
  echo "$VERDICT"
} | tee -a "$SORTIE"
exit "$RC"
