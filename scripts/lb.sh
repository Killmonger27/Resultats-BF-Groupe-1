#!/usr/bin/env bash
# Load balancer (rôle "lb") : HAProxy, Keepalived et VIP.
set -euo pipefail
. /vagrant/scripts/lib.sh

maj_apt
installer keepalived haproxy gettext-base socat

# HAProxy doit pouvoir démarrer sur le LB passif avant qu'il ne possède la VIP.
sysctl -w net.ipv4.ip_nonlocal_bind=1 >/dev/null
printf 'net.ipv4.ip_nonlocal_bind=1\n' > /etc/sysctl.d/99-haproxy-vip.conf

# --- Paramètres lus dans noeuds.yml ---
VIP=$(cfg "d['vip']")
MY_IP=$(mon_champ ip)
ETAT=$(mon_champ etat)                     # MASTER ou BACKUP
PEER_IP=$(cfg "next(n['ip'] for n in d['noeuds'] if n['role'] == 'lb' and n['nom'] != '$MON_NOM')")
IFACE=$(ip -o -4 addr show | awk -v ip="$MY_IP" '$4 ~ "^"ip"/" {print $2}')
case "$ETAT" in MASTER) PRIO=101 ;; *) PRIO=100 ;; esac
export VIP MY_IP ETAT PEER_IP IFACE PRIO

# --- HAProxy ---
BACKENDS=$(cfg "'\n'.join('    server %s %s:%s check' % (n['nom'], n['ip'], n.get('port', 8080)) for n in d['noeuds'] if n['role'] == 'app')")
if [ -z "$BACKENDS" ]; then
  echo "Aucun backend applicatif n'est défini dans $CONFIG" >&2
  exit 1
fi
export BACKENDS
rendre haproxy/haproxy.cfg.tpl /etc/haproxy/haproxy.cfg '${VIP} ${BACKENDS}'
haproxy -c -f /etc/haproxy/haproxy.cfg
systemctl enable haproxy
systemctl restart haproxy

# --- Keepalived ---
rendre keepalived/keepalived.conf.tpl /etc/keepalived/keepalived.conf \
  '${ETAT} ${PRIO} ${IFACE} ${MY_IP} ${PEER_IP} ${VIP}'
systemctl enable keepalived
systemctl restart keepalived

echo "[$MON_NOM] $ETAT prêt (HAProxy, VIP $VIP, interface $IFACE, pair $PEER_IP)"