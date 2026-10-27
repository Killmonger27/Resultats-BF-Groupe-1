#!/usr/bin/env bash
# R6 / V4 : panne de bdd1 puis bascule sur bdd2 (scripts/bascule.sh), vue du client (sonde sur /resultat).
# ATTENTION : bdd2 devient primaire. Pour revenir à la normale : vagrant destroy -f puis vagrant up.
# Usage : ./tests/r6_bascule.sh
cd "$(dirname "$0")/.." || exit 1
T=tests/lib; OUT=${OUT:-/tmp/resultats-bf}; D=$OUT/bascule; mkdir -p "$D"
epoch() { python3 -I -c 'import time;print(f"{time.time():.3f}")'; }
Q() { vagrant ssh "$1" -c "sudo -u postgres psql -d resultats_bf -Atc \"$2\"" 2>/dev/null | tr -d '\r'; }

echo "=== avant : /sante $(curl -s -m 6 -w '[%{http_code}]' http://192.168.56.5/sante) ; bdd1 recovery=$(Q bdd1 'select pg_is_in_recovery()') bdd2 recovery=$(Q bdd2 'select pg_is_in_recovery()')"
echo "=== 100 lignes marqueurs insérées sur bdd1 juste avant la panne"
vagrant ssh bdd1 -c "sudo -u postgres psql -d resultats_bf -qc \"INSERT INTO resultats SELECT 'LOSS'||lpad(g::text,4,'0'),'Marqueur '||g,'A',10,true FROM generate_series(1,100) g\"" 2>/dev/null
echo "marqueurs sur bdd1 : $(Q bdd1 "select count(*) from resultats where matricule like 'LOSS%'")"

python3 -I "$T/sonde.py" 'http://192.168.56.5/resultat?matricule=BF000001' 230 "$D/bascule.log" & PID=$!
sleep 6; T0=$(epoch)
echo "=== vagrant halt bdd1"; vagrant halt bdd1 2>&1 | tail -1; T1=$(epoch)
echo "halt : $(python3 -I -c "print(f'{$T1-$T0:.1f}')") s"
echo "=== ./scripts/bascule.sh"; ./scripts/bascule.sh 2>&1 | tee "$D/bascule.out"; T2=$(epoch)
echo "durée totale depuis le début du halt : $(python3 -I -c "print(f'{$T2-$T0:.1f}')") s ; bascule.sh seul : $(python3 -I -c "print(f'{$T2-$T1:.1f}')") s"
wait $PID
echo "=== vue du client (sonde sur /resultat, 0,1 s), t=0 au lancement de vagrant halt :"; python3 -I "$T/analyse.py" "$D/bascule.log" "$T0"
echo "=== après la bascule :"
echo "bdd2 recovery (f = primaire) : $(Q bdd2 'select pg_is_in_recovery()')"
echo "marqueurs retrouvés sur bdd2 : $(Q bdd2 "select count(*) from resultats where matricule like 'LOSS%'") / 100 ; lignes totales : $(Q bdd2 'select count(*) from resultats')"
echo "écriture acceptée sur bdd2 : $(vagrant ssh bdd2 -c "sudo -u postgres psql -d resultats_bf -c \"INSERT INTO resultats VALUES ('POST0001','Apres bascule','A',11,true)\"" 2>&1 | tr -d '\r' | tail -1)"
echo "/sante via la VIP : $(curl -s -m 6 -w ' [%{http_code}]' http://192.168.56.5/sante)"
./tests/api.sh | grep -c '^OK' | sed 's/$/ OK sur 7 (api.sh après bascule)/'
echo "sonde HAProxy : $(vagrant ssh lb1 -c "echo 'show stat' | sudo socat stdio /run/haproxy/admin.sock" 2>/dev/null | tr -d '\r' | awk -F, '$1=="web_servers" && $2!="BACKEND"{printf "%s=%s ", $2, $18}')"
