#!/usr/bin/env bash
# V2 (panne d'app1) et V6 (panne de lb1 puis retour), sous sonde de 0,1 s sur la VIP.
# Si un essai de V6 dépasse 5 s, le diagnostic (ARP de l'hôte, journal keepalived de lb2) est capturé.
# Usage : ./tests/v2_v6_pannes.sh            (REP=3 par défaut ; SEULEMENT=v2 ou v6 pour n'en faire qu'un)
cd "$(dirname "$0")/.." || exit 1
T=tests/lib; OUT=${OUT:-/tmp/resultats-bf}; R=$OUT/pannes; mkdir -p "$R"
epoch() { python3 -I -c 'import time;print(f"{time.time():.3f}")'; }
st() { vagrant ssh lb1 -c "echo 'show stat' | sudo socat stdio /run/haproxy/admin.sock" 2>/dev/null | tr -d '\r' | awk -F, -v s="$1" '$1=="web_servers" && $2==s {print $18}'; }
attendre_up() { for _ in $(seq 1 90); do [ "$(st "$1")" = "UP" ] && return 0; sleep 1; done; return 1; }
vip_sur() { for _ in $(seq 1 60); do [ "$(vagrant ssh "$1" -c 'ip -4 addr show eth1 | grep -c 192.168.56.5' 2>/dev/null | tr -d '\r')" = "1" ] && return 0; sleep 1; done; return 1; }
degrade() { sed -n 's/.*degradee (premiere -> derniere erreur): \([0-9.]*\) s.*/\1/p' | head -1; }

if [ "${SEULEMENT:-}" != "v6" ]; then
for i in $(seq 1 "${REP:-3}"); do
  echo "=== V2 essai $i : vagrant halt app1 sous sonde"
  python3 -I "$T/sonde.py" http://192.168.56.5/info 90 "$R/v2_$i.log" & PID=$!
  sleep 6; T0=$(epoch); vagrant halt app1 >/dev/null 2>&1; wait $PID
  python3 -I "$T/analyse.py" "$R/v2_$i.log" "$T0" | sed 's/^/   /'
  vagrant up app1 >/dev/null 2>&1; attendre_up app1 && echo "   app1 reintegre (UP)" || echo "   app1 NON reintegre apres 90 s"
  sleep 10
done
fi

if [ "${SEULEMENT:-}" != "v2" ]; then
for i in $(seq 1 "${REP:-3}"); do
  echo "=== V6 essai $i : vagrant halt lb1 sous sonde"
  python3 -I "$T/sonde.py" http://192.168.56.5/info 90 "$R/v6_$i.log" & PID=$!
  sleep 6; T0=$(epoch); vagrant halt lb1 >/dev/null 2>&1; TH=$(epoch)
  VIP_APRES=$(vagrant ssh lb2 -c 'ip -4 addr show eth1 | grep -c 192.168.56.5' 2>/dev/null | tr -d '\r')
  JOURNAL=$(vagrant ssh lb2 -c "sudo journalctl -u keepalived --since '-3 min' --no-pager" 2>/dev/null | tr -d '\r')
  ARP=$(arp -an | grep 192.168.56.5)
  wait $PID
  RES=$(python3 -I "$T/analyse.py" "$R/v6_$i.log" "$T0"); echo "$RES" | sed 's/^/   /'
  echo "   VIP sur lb2 apres le halt : $VIP_APRES ; halt de lb1 : $(python3 -I -c "print(f'{$TH-$T0:.0f}')") s"
  DEG=$(echo "$RES" | degrade)
  if [ -n "$DEG" ] && python3 -I -c "import sys; sys.exit(0 if float('$DEG')>=5 else 1)"; then
    echo "   !! ESSAI NON CONFORME (>= 5 s) : diagnostic"
    echo "   -- ARP de l'hote : $ARP"
    echo "   -- journal keepalived de lb2 (3 dernieres minutes) :"
    echo "$JOURNAL" | grep -iE "MASTER|BACKUP|FAULT|Transition|gratuitous|VRRP|Sending" | sed 's/^/      /' | tail -15
  fi
  echo "   -- retour de lb1 (vagrant up lb1) sous sonde"
  python3 -I "$T/sonde.py" http://192.168.56.5/info 75 "$R/v6b_$i.log" & PID=$!
  sleep 2; T0=$(epoch); vagrant up lb1 >/dev/null 2>&1; vip_sur lb1 && echo "   VIP revenue sur lb1" || echo "   VIP NON revenue sur lb1"; wait $PID
  python3 -I "$T/analyse.py" "$R/v6b_$i.log" "$T0" | sed 's/^/   /'
  sleep 10
done
fi
echo "=== fin : $(vagrant status 2>&1 | sed -n 3,8p | awk '{printf "%s=%s ", $1, $2}')"
