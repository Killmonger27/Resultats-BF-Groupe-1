#!/usr/bin/env bash
# Fonctions communes à bdd.sh et replique.sh (source avec : . /vagrant/scripts/lib-pg.sh)
# Principe d'idempotence : on ne réécrit un fichier que s'il diffère, et on ne
# redémarre PostgreSQL que si quelque chose a changé. Jamais de >> sur un fichier existant.

PG_CHANGED=0
NOEUDS_YML=/vagrant/config/noeuds.yml

# Lit les secrets dans /vagrant/.env (non versionné) et déduit le réseau et l'adresse
# de bdd1 de config/noeuds.yml, la source de vérité unique : aucune adresse en dur.
# Les variables déjà présentes dans l'environnement ne sont pas écrasées par le défaut.
charger_contexte() {
  if [ -f /vagrant/.env ]; then
    set -a
    . <(tr -d '\r' < /vagrant/.env)
    set +a
  fi
  : "${NET_CIDR:=$(awk '/^reseau:/{print $2}' "$NOEUDS_YML")}"
  : "${BDD1_IP:=$(awk '$1 == "ip:" {gsub(/\r$/, "", $2); ip=$2} $1 == "role:" {gsub(/\r$/, "", $2); if ($2 == "bdd") print ip}' "$NOEUDS_YML")}"
  export NET_CIDR BDD1_IP
}

installer_postgres() {
  export DEBIAN_FRONTEND=noninteractive
  if ! dpkg -s postgresql >/dev/null 2>&1; then
    apt-get update -qq
    apt-get install -y -qq postgresql
  fi
  PG_VER=$(ls /usr/lib/postgresql | sort -n | tail -1)
  PG_ETC="/etc/postgresql/${PG_VER}/main"
  PG_DATA="/var/lib/postgresql/${PG_VER}/main"   # disque de la VM, jamais dans /vagrant
}

# remplacer_si_different SOURCE DESTINATION MODE
remplacer_si_different() {
  if ! cmp -s "$1" "$2" 2>/dev/null; then
    install -o postgres -g postgres -m "$3" "$1" "$2"
    PG_CHANGED=1
  fi
  rm -f "$1"
}

# configurer_postgres CIDR_DU_RESEAU_PRIVE
configurer_postgres() {
  local cidr="$1" tmp

  tmp=$(mktemp)
  cat > "$tmp" <<'EOF'
listen_addresses = '*'
wal_level = replica
max_wal_senders = 10
max_replication_slots = 10
hot_standby = on
wal_keep_size = 64MB
EOF
  remplacer_si_different "$tmp" "${PG_ETC}/conf.d/resultats-bf.conf" 644

  # pg_hba.conf : on retire notre bloc balisé puis on le réécrit (idempotent).
  tmp=$(mktemp)
  sed '/# BEGIN resultats-bf/,/# END resultats-bf/d' "${PG_ETC}/pg_hba.conf" > "$tmp"
  cat >> "$tmp" <<EOF
# BEGIN resultats-bf
host  ${DB_NAME}     ${DB_USER}     ${cidr}  scram-sha-256
host  replication    replicateur    ${cidr}  scram-sha-256
# END resultats-bf
EOF
  remplacer_si_different "$tmp" "${PG_ETC}/pg_hba.conf" 640
}

demarrer_postgres() {
  systemctl enable postgresql >/dev/null 2>&1
  if [ "$PG_CHANGED" = 1 ]; then
    systemctl restart postgresql
  else
    systemctl start postgresql
  fi
  for _ in $(seq 1 30); do
    sudo -u postgres pg_isready -q && return 0
    sleep 1
  done
  echo "PostgreSQL ne répond pas après 30 s" >&2
  return 1
}
