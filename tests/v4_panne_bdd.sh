#!/usr/bin/env bash
# V4 (sans promotion) : vagrant halt bdd1 puis vagrant up bdd1, vu du client.
# Usage : ./tests/v4_panne_bdd.sh
cd "$(dirname "$0")/.." || exit 1
T=tests/lib; OUT=${OUT:-/tmp/resultats-bf}; D=$OUT/v4; mkdir -p "$D"
epoch() { python3 -I -c 'import time;print(f"{time.time():.3f}")'; }
python3 -I "$T/sonde.py" 'http://192.168.56.5/resultat?matricule=BF000001' 190 "$D/v4.log" & PID=$!
sleep 6; T0=$(epoch); echo "=== vagrant halt bdd1"; vagrant halt bdd1 2>&1 | tail -1; T1=$(epoch)
echo "halt : $(python3 -I -c "print(f'{$T1-$T0:.1f}')") s"
echo "--- pendant la panne (client) :"; curl -s -m 6 -D - -o "$D/corps_503.txt" 'http://192.168.56.5/resultat?matricule=BF000001' | head -2 | tr -d '\r'; echo "corps: $(head -c 140 "$D/corps_503.txt")"
echo "/sante: $(curl -s -m 6 -w ' [%{http_code}]' http://192.168.56.5/sante | head -c 160)"
echo "--- apps vues par HAProxy : $(vagrant ssh lb1 -c "echo 'show stat' | sudo socat stdio /run/haproxy/admin.sock" 2>/dev/null | tr -d '\r' | awk -F, '$1=="web_servers" && $2!="BACKEND"{printf "%s=%s ", $2, $18}')"
echo "=== vagrant up bdd1"; T2=$(epoch); vagrant up bdd1 2>&1 | tail -1; T3=$(epoch)
for i in $(seq 1 60); do c=$(curl -s -m 3 -o /dev/null -w '%{http_code}' 'http://192.168.56.5/resultat?matricule=BF000001'); [ "$c" = 200 ] && break; sleep 1; done
T4=$(epoch)
echo "vagrant up bdd1 : $(python3 -I -c "print(f'{$T3-$T2:.1f}')") s ; service de nouveau en 200 : $(python3 -I -c "print(f'{$T4-$T2:.1f}')") s après le début de 'vagrant up'"
wait $PID
echo "=== vue du client sur toute la séquence (t=0 : lancement de vagrant halt) :"; python3 -I "$T/analyse.py" "$D/v4.log" "$T0"
echo "bdd2 : $(vagrant ssh bdd2 -c "sudo -u postgres psql -d resultats_bf -Atc 'select pg_is_in_recovery(), count(*) from resultats'" 2>/dev/null | tr -d '\r') (t|50000 attendu)"
./tests/api.sh | grep -c '^OK' | sed 's/$/ OK sur 7 (api.sh après retour)/'
