#!/usr/bin/env bash
# Load balancer (rôle "lb") : Keepalived et VIP.
set -euo pipefail
. /vagrant/scripts/lib.sh

maj_apt
installer keepalived gettext-base

# --- Paramètres lus dans noeuds.yml ---
VIP=$(cfg "d['vip']")
MY_IP=$(mon_champ ip)
ETAT=$(mon_champ etat)                     # MASTER ou BACKUP
PEER_IP=$(cfg "next(n['ip'] for n in d['noeuds'] if n['role'] == 'lb' and n['nom'] != '$MON_NOM')")
IFACE=$(ip -o -4 addr show | awk -v ip="$MY_IP" '$4 ~ "^"ip"/" {print $2}')
case "$ETAT" in MASTER) PRIO=101 ;; *) PRIO=100 ;; esac
export VIP MY_IP ETAT PEER_IP IFACE PRIO

# --- Keepalived ---
rendre keepalived/keepalived.conf.tpl /etc/keepalived/keepalived.conf \
  '${ETAT} ${PRIO} ${IFACE} ${MY_IP} ${PEER_IP} ${VIP}'
systemctl enable keepalived
systemctl restart keepalived

echo "[$MON_NOM] $ETAT prêt (VIP $VIP, interface $IFACE, pair $PEER_IP)"