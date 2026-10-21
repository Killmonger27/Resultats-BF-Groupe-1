#!/usr/bin/env bash
# Fonctions et constantes communes. Utilisation : . /vagrant/scripts/lib.sh
export DEBIAN_FRONTEND=noninteractive

CONFIG="${CONFIG:-/vagrant/config/noeuds.yml}"   
CONF_DIR="${CONF_DIR:-/vagrant/conf}"            
MON_NOM="${MON_NOM:-$(hostname)}"
APP_PORT=3000                                   

maj_apt()   { apt-get update -qq; }
installer() { apt-get install -y -qq "$@"; }

# cfg '<expression python>' : évalue l'expression avec d = contenu de noeuds.yml
cfg() {
  python3 - "$CONFIG" "$1" <<'PY'
import sys, yaml
d = yaml.safe_load(open(sys.argv[1]))
print(eval(sys.argv[2]))
PY
}

# mon_champ <champ> : valeur du champ pour ce noeud (vide si absent)
mon_champ() {
  cfg "next(n for n in d['noeuds'] if n['nom'] == '$MON_NOM').get('$1', '')"
}

# noeuds_role <role> : une ligne "nom ip" par noeud ayant ce rôle
noeuds_role() {
  cfg "'\n'.join(n['nom'] + ' ' + n['ip'] for n in d['noeuds'] if n['role'] == '$1')"
}

# rendre <template> <destination> '<${VAR1} ${VAR2}>' : génère une conf depuis conf/
rendre() {
  envsubst "$3" < "$CONF_DIR/$1" > "$2"
}

python3 -c 'import yaml' 2>/dev/null || { maj_apt; installer python3-yaml; }