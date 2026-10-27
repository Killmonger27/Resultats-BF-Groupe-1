#!/usr/bin/env bash
# Met à jour l'application sur CE serveur : copie le code et redémarre le service.
# Pas d'apt ni de configuration : mise à jour rapide utilisée par deploy.sh (E4).
# Usage (dans la VM) : sudo /vagrant/scripts/maj-app.sh
set -euo pipefail

DEST=/opt/resultats-bf
RACINE=/vagrant
PORT=$(sed -n 's/^APP_PORT=//p' /etc/resultats-bf/app.env)

for f in app.py index.html VERSION; do
  install -m 0644 "$RACINE/app/$f" "$DEST/$f"
done
systemctl restart resultats-bf.service

# Le service doit répondre avant de rendre la main.
for _ in $(seq 1 30); do
  curl -fs -o /dev/null "http://127.0.0.1:${PORT:-8080}/info" && exit 0
  sleep 1
done
echo "maj-app.sh : le service ne répond pas après la mise à jour" >&2
exit 1
