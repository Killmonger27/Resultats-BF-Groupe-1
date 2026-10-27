#!/usr/bin/env bash
# R2 : deux rejeux de vagrant provision par rôle (app1, lb1, bdd1, bdd2), empreintes avant / après 1 / après 2.
# Usage : ./tests/r2_idempotence.sh        (dure environ 10 minutes)
cd "$(dirname "$0")/.." || exit 1
OUT=${OUT:-/tmp/resultats-bf}; D=$OUT/r2; mkdir -p "$D"

snap_app() { vagrant ssh "$1" -c "sudo sh -c 'md5sum $2'" 2>/dev/null | tr -d '\r'; }
snap_pg() {
  vagrant ssh "$1" -c "sudo md5sum /etc/postgresql/*/main/conf.d/resultats-bf.conf /etc/postgresql/*/main/pg_hba.conf" 2>/dev/null | tr -d '\r'
  echo "blocs balises dans pg_hba.conf: $(vagrant ssh "$1" -c "sudo grep -c 'BEGIN resultats-bf' /etc/postgresql/*/main/pg_hba.conf" 2>/dev/null | tr -d '\r')"
  echo "recovery,lignes: $(vagrant ssh "$1" -c "sudo -u postgres psql -d resultats_bf -Atc 'select pg_is_in_recovery(), count(*) from resultats'" 2>/dev/null | tr -d '\r')"
  echo "service: $(vagrant ssh "$1" -c "systemctl show postgresql -p ActiveEnterTimestamp --value" 2>/dev/null | tr -d '\r')"
}

verifier() {   # verifier <vm> <fonction de relevé> [fichiers]
  local vm="$1" f="$2" fichiers="$3" rc1 rc2 n
  $f "$vm" "$fichiers" > "$D/${vm}_0.txt"
  vagrant provision "$vm" > "$D/${vm}_p1.log" 2>&1; rc1=$?
  $f "$vm" "$fichiers" > "$D/${vm}_1.txt"
  vagrant provision "$vm" > "$D/${vm}_p2.log" 2>&1; rc2=$?
  $f "$vm" "$fichiers" > "$D/${vm}_2.txt"
  n=$(wc -l < "$D/${vm}_0.txt" | tr -d ' ')
  if [ "$rc1" = 0 ] && [ "$rc2" = 0 ] && [ "$n" -ge 2 ] && diff -q "$D/${vm}_0.txt" "$D/${vm}_2.txt" >/dev/null && diff -q "$D/${vm}_1.txt" "$D/${vm}_2.txt" >/dev/null; then
    echo "OK  $vm : 2 rejeux sans erreur (codes $rc1/$rc2), $n lignes de relevé identiques avant et après"
  else
    echo "KO  $vm : codes $rc1/$rc2, $n lignes ; différences :"; diff "$D/${vm}_0.txt" "$D/${vm}_2.txt" | head -10
  fi
}

verifier app1 snap_app "/etc/resultats-bf/* /opt/resultats-bf/* /etc/systemd/system/resultats-bf.service"
verifier lb1  snap_app "/etc/haproxy/haproxy.cfg /etc/keepalived/keepalived.conf /etc/sysctl.d/99-haproxy-vip.conf"
verifier bdd1 snap_pg
verifier bdd2 snap_pg
echo "--- /sante après les rejeux : $(curl -s -m 6 -w ' [%{http_code}]' http://192.168.56.5/sante)"
