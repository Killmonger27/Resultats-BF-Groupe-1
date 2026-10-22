#!/usr/bin/env bash
# Provisionnement d'un serveur applicatif (app1..appN). Idempotent : chaque
# fichier est réécrit en entier, jamais complété (pas de >>).
set -euo pipefail

DEST=/opt/resultats-bf
CONF=/etc/resultats-bf
RACINE=/vagrant

# Secrets : lus dans /vagrant/.env (non versionné, voir config/env.example).
if [ -f "$RACINE/.env" ]; then
  set -a; . "$RACINE/.env"; set +a
else
  echo "app.sh : $RACINE/.env absent, /sante renverra 503 tant qu'il manque" >&2
fi

export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq python3-psycopg2 python3-yaml

install -d "$DEST" "$CONF"
install -m 0644 "$RACINE/app/app.py" "$DEST/app.py"
install -m 0644 "$RACINE/app/index.html" "$DEST/index.html"
install -m 0644 "$RACINE/config/noeuds.yml" "$CONF/noeuds.yml"

cat > "$CONF/app.env" <<ENV
APP_PORT=${APP_PORT:-8080}
DB_PORT=${DB_PORT:-5432}
DB_NAME=${DB_NAME:-resultats_bf}
DB_USER=${DB_USER:-app}
DB_PASSWORD=${DB_PASSWORD:-}
NOEUDS_FILE=$CONF/noeuds.yml
ENV
chmod 0600 "$CONF/app.env"

cat > /etc/systemd/system/resultats-bf.service <<UNIT
[Unit]
Description=RESULTATS-BF application HTTP
After=network-online.target
Wants=network-online.target

[Service]
EnvironmentFile=$CONF/app.env
ExecStart=/usr/bin/python3 $DEST/app.py
DynamicUser=yes
Restart=always
RestartSec=1

[Install]
WantedBy=multi-user.target
UNIT

systemctl daemon-reload
systemctl enable resultats-bf.service
systemctl restart resultats-bf.service
