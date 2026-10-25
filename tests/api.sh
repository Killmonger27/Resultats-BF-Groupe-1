#!/usr/bin/env bash
# Vérifie le contrat HTTP de l'application (codes et formats). À lancer sur l'hôte.
# Usage : ./tests/api.sh                                      (cible : la VIP)
#         BASE_URL=http://192.168.56.21:8080 ./tests/api.sh   (un serveur précis)
set -uo pipefail
cd "$(dirname "$0")/.."

VIP=$(awk '/^vip:/{print $2}' config/noeuds.yml)
BASE_URL="${BASE_URL:-http://$VIP}"
MATRICULE="${MATRICULE:-BF000001}"
KO=0

# verifier "<libellé>" <code attendu> <texte attendu dans le corps> <arguments curl...>
verifier() {
  local nom="$1" attendu="$2" motif="$3" sortie code corps
  shift 3
  sortie=$(curl -s -m 5 -w '\n%{http_code}' "$@") || true
  code=${sortie##*$'\n'}
  corps=${sortie%$'\n'*}
  if [ "$code" = "$attendu" ] && [[ "$corps" == *"$motif"* ]]; then
    printf 'OK  %-32s %s\n' "$nom" "$code"
  else
    printf 'KO  %-32s attendu %s, reçu %s : %s\n' "$nom" "$attendu" "$code" "$corps"
    KO=1
  fi
}

verifier "/info"                  200 '"hote"'            "$BASE_URL/info"
verifier "/sante"                 200 '"statut": "ok"'    "$BASE_URL/sante"
verifier "/resultat (existant)"   200 '"matricule"'       "$BASE_URL/resultat?matricule=$MATRICULE"
verifier "/resultat (inconnu)"    404 'matricule inconnu' "$BASE_URL/resultat?matricule=BF999999"
verifier "/resultat (absent)"     400 'invalide'          "$BASE_URL/resultat"
verifier "/resultat (a;b)"        400 'invalide'          -G --data-urlencode "matricule=a;b" "$BASE_URL/resultat"
verifier "route inconnue"         404 'route inconnue'    "$BASE_URL/nimporte"
exit "$KO"
