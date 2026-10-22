#!/usr/bin/env bash
# bdd2 : réplique en flux de bdd1 (pg_basebackup). Rejouable sans effet de bord.
set -euo pipefail

. /vagrant/scripts/lib-pg.sh
charger_contexte

: "${DB_NAME:?DB_NAME manquant : créer le fichier .env (cp .env.exemple .env)}"
: "${DB_USER:?DB_USER manquant}"
: "${REPL_PASSWORD:?REPL_PASSWORD manquant}"
: "${NET_CIDR:?NET_CIDR introuvable dans config/noeuds.yml}"
: "${BDD1_IP:?adresse de bdd1 introuvable dans config/noeuds.yml}"

installer_postgres
configurer_postgres "$NET_CIDR"

# La base primaire doit être prête avant de copier.
for _ in $(seq 1 60); do
  sudo -u postgres pg_isready -q -h "$BDD1_IP" && break
  sleep 2
done
sudo -u postgres pg_isready -q -h "$BDD1_IP" || { echo "bdd1 ($BDD1_IP) injoignable" >&2; exit 1; }

if [ ! -f "${PG_DATA}/standby.signal" ]; then
  # Première fois : on remplace le cluster vide par une copie de bdd1.
  systemctl stop postgresql
  [ -n "$PG_DATA" ] && find "$PG_DATA" -mindepth 1 -delete
  sudo -u postgres env PGPASSWORD="$REPL_PASSWORD" \
    pg_basebackup -h "$BDD1_IP" -U replicateur -D "$PG_DATA" \
                  -X stream -R -S bdd2_slot
  PG_CHANGED=1
fi

demarrer_postgres
echo "bdd2 en réplication : $(sudo -u postgres psql -X -t -A -c 'SELECT pg_is_in_recovery()')"
