#!/usr/bin/env bash
# E4 : déploiement sans coupure. Met à jour les serveurs applicatifs UN PAR UN :
# retrait du répartiteur (drain), mise à jour, remise en service quand HAProxy
# voit le serveur UP. Les noms viennent de config/noeuds.yml (rien en dur).
# Prérequis : au moins 2 serveurs applicatifs, socat sur les répartiteurs, base saine.
# Usage (sur l'hôte) : ./scripts/deploy.sh
set -euo pipefail
cd "$(dirname "$0")/.."

NOEUDS=config/noeuds.yml
BACKEND="${BACKEND:-web_servers}"      # nom du backend dans conf/haproxy/haproxy.cfg.tpl
SOCKET=/run/haproxy/admin.sock

noeuds_role() { awk -v r="$1" '/^- nom:/{n=$3} /^  role:/{if ($2==r) print n}' "$NOEUDS"; }
en_marche() { local s; s=$(vagrant status "$1" --machine-readable 2>/dev/null || true); [[ "$s" == *",state,running"* ]]; }

# hap <lb> '<commande>' : envoie une commande au socket d'administration de HAProxy
hap() { vagrant ssh "$1" -c "echo '$2' | sudo socat stdio $SOCKET" </dev/null 2>/dev/null | tr -d '\r'; }
# champ <lb> <serveur> <n° de colonne de 'show stat'> (5 = sessions actives, 18 = état)
champ() { hap "$1" 'show stat' | awk -F, -v b="$BACKEND" -v s="$2" -v c="$3" '$1==b && $2==s {print $c}'; }
# attendre <secondes> <commande...> : réessaie chaque seconde
attendre() { local max="$1"; shift; for _ in $(seq 1 "$max"); do "$@" && return 0; sleep 1; done; return 1; }
vide()  { local l; for l in $LBS; do [ "$(champ "$l" "$1" 5)" = "0" ] || return 1; done; }
actif() { local l; for l in $LBS; do [ "$(champ "$l" "$1" 18)" = "UP" ] || return 1; done; }

APPS=$(noeuds_role app)
set -- $APPS
[ "$#" -ge 2 ] || { echo "Il faut au moins 2 serveurs applicatifs." >&2; exit 1; }

LBS=""
for lb in $(noeuds_role lb); do
  if en_marche "$lb"; then LBS="$LBS $lb"; fi
done
[ -n "$LBS" ] || { echo "Aucun répartiteur en marche." >&2; exit 1; }

# Contrôle préalable : le socket répond-il sur chaque répartiteur ?
for lb in $LBS; do
  info=$(hap "$lb" 'show info' || true)
  case "$info" in
    *Version:*) ;;
    *) echo "Socket HAProxy inaccessible sur $lb (socat installé ? vagrant provision $lb)" >&2; exit 1 ;;
  esac
done

for app in $APPS; do
  echo "== $app"
  for lb in $LBS; do hap "$lb" "set server $BACKEND/$app state drain" >/dev/null; done
  if ! attendre 30 vide "$app"; then
    for lb in $LBS; do hap "$lb" "set server $BACKEND/$app state ready" >/dev/null; done
    echo "ÉCHEC : $app a encore des sessions actives après 30 s. Annulé, $app remis en service." >&2
    exit 1
  fi
  if ! vagrant ssh "$app" -c 'sudo /vagrant/scripts/maj-app.sh' </dev/null; then
    echo "ÉCHEC : la mise à jour de $app a échoué. $app reste retiré du répartiteur (drain)." >&2
    exit 1
  fi
  for lb in $LBS; do hap "$lb" "set server $BACKEND/$app state ready" >/dev/null; done
  if ! attendre 60 actif "$app"; then
    echo "ÉCHEC : HAProxy ne voit pas $app UP après 60 s. Déploiement interrompu." >&2
    exit 1
  fi
  echo "   $app à jour et UP"
done
echo "Déploiement terminé : version $(cat app/VERSION)"
