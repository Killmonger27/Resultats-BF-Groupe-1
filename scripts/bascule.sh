#!/usr/bin/env bash
# Bascule de la base : promeut bdd2 en primaire puis attend le retour du service.
# À lancer SUR L'HÔTE, depuis n'importe où : ./scripts/bascule.sh
# Ne dépend PAS de bdd1 (elle est supposée en panne).
#
# Aucune redirection des serveurs applicatifs n'est nécessaire : app/app.py lit les
# adresses des bases (bdd1 puis bdd2) dans config/noeuds.yml et se connecte à la
# première qui répond. Une fois bdd2 promue, l'application la trouve toute seule.
set -euo pipefail

cd "$(dirname "$0")/.."

NOEUDS=config/noeuds.yml
[ -f "$NOEUDS" ] || { echo "$NOEUDS introuvable : lancer vagrant up une fois d'abord" >&2; exit 1; }

# Où mesurer le retour du service : le répartiteur (VIP) par défaut, ou BASE_URL.
VIP=$(awk '/^vip:/{print $2}' "$NOEUDS")
BASE_URL="${BASE_URL:-http://$VIP}"

maintenant() { date +%s.%N; }
duree() { awk -v a="$1" -v b="$2" 'BEGIN{printf "%.1f", b-a}'; }

# Coût d'une connexion vagrant ssh : il est inclus dans la durée de promotion ci-dessous.
TS0=$(maintenant)
vagrant ssh bdd2 -c true >/dev/null 2>&1 || { echo "bdd2 injoignable (VM éteinte ?)" >&2; exit 1; }
TS1=$(maintenant)

T0=$(maintenant)

echo "[1/2] Promotion de bdd2"
# Une seule connexion : on promeut si bdd2 est encore en réplique, puis on relit son état.
ETAT=$(vagrant ssh bdd2 -c '
  psql_pg() { sudo -u postgres psql -X -t -A -c "$1"; }
  if [ "$(psql_pg "SELECT pg_is_in_recovery()")" = "t" ]; then
    psql_pg "SELECT pg_promote(true, 30)" >/dev/null
  fi
  psql_pg "SELECT pg_is_in_recovery()"' 2>/dev/null | tr -d '[:space:]' | tail -c 1)
[ "$ETAT" = "f" ] || { echo "bdd2 n'est pas promue" >&2; exit 1; }
T1=$(maintenant)

echo "[2/2] Attente du retour du service ($BASE_URL/sante)"
T2=$T1
if curl -s -o /dev/null --max-time 2 "$BASE_URL/info"; then
  for _ in $(seq 1 60); do
    [ "$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 "$BASE_URL/sante")" = "200" ] && break
    sleep 1
  done
  T2=$(maintenant)
else
  echo "  $BASE_URL injoignable : mesure limitée à la promotion (définir BASE_URL pour cibler un serveur)"
fi

echo
echo "Promotion de bdd2         : $(duree "$T0" "$T1") s (dont environ $(duree "$TS0" "$TS1") s de connexion vagrant ssh)"
echo "Service de nouveau en 200 : $(duree "$T0" "$T2") s (durée totale de la bascule)"
