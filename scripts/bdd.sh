#!/usr/bin/env bash
# bdd1 : PostgreSQL primaire (lecture/écriture). Rejouable sans effet de bord.
set -euo pipefail

. /vagrant/scripts/lib-pg.sh
charger_contexte

: "${DB_NAME:?DB_NAME manquant : créer le fichier .env (cp .env.exemple .env)}"
: "${DB_USER:?DB_USER manquant}"
: "${DB_PASSWORD:?DB_PASSWORD manquant}"
: "${REPL_PASSWORD:?REPL_PASSWORD manquant}"
: "${NET_CIDR:?NET_CIDR introuvable dans config/noeuds.yml}"

installer_postgres
configurer_postgres "$NET_CIDR"
demarrer_postgres

psql_pg() { sudo -u postgres psql -X -q -v ON_ERROR_STOP=1 "$@"; }

# Rôles, base et slot de réplication : créés seulement s'ils n'existent pas.
psql_pg -v u="$DB_USER" -v pw="$DB_PASSWORD" -v rpw="$REPL_PASSWORD" -v db="$DB_NAME" <<'SQL'
SELECT format('CREATE ROLE %I LOGIN PASSWORD %L', :'u', :'pw')
 WHERE NOT EXISTS (SELECT FROM pg_roles WHERE rolname = :'u') \gexec
SELECT format('CREATE ROLE replicateur REPLICATION LOGIN PASSWORD %L', :'rpw')
 WHERE NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'replicateur') \gexec
SELECT format('CREATE DATABASE %I OWNER %I', :'db', :'u')
 WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = :'db') \gexec
SELECT pg_create_physical_replication_slot('bdd2_slot')
 WHERE NOT EXISTS (SELECT FROM pg_replication_slots WHERE slot_name = 'bdd2_slot');
SQL

# Table et jeu de données : 50 000 lignes, insérées seulement si la table est vide.
psql_pg -d "$DB_NAME" -v u="$DB_USER" <<'SQL'
CREATE TABLE IF NOT EXISTS resultats (
  matricule text PRIMARY KEY,
  nom       text NOT NULL,
  serie     text NOT NULL,
  moyenne   numeric(4,2) NOT NULL,
  admis     boolean NOT NULL
);
INSERT INTO resultats (matricule, nom, serie, moyenne, admis)
SELECT 'BF' || lpad(t.g::text, 6, '0'),
       'Candidat ' || t.g,
       (ARRAY['A','C','D','E'])[1 + t.g % 4],
       t.m,
       t.m >= 10
  FROM (SELECT g, round((((g * 37) % 2001) / 100.0)::numeric, 2) AS m
          FROM generate_series(1, 50000) AS g) t
 WHERE NOT EXISTS (SELECT 1 FROM resultats);
GRANT SELECT ON resultats TO :"u";
SQL

echo "bdd1 prête : $(sudo -u postgres psql -X -t -A -d "$DB_NAME" -c 'SELECT count(*) FROM resultats') lignes."
