"""Service HTTP RESULTATS-BF : sans etat, toute la configuration vient de l'environnement."""
import json
import os
import re
import socket
from pathlib import Path
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, urlparse

import psycopg2
import yaml
from psycopg2 import sql

PORT = int(os.environ.get("APP_PORT", "8080"))
NOEUDS = os.environ.get("NOEUDS_FILE", "/vagrant/config/noeuds.yml")
TABLE = os.environ.get("DB_TABLE", "resultats")
CLE = os.environ.get("DB_CLE", "matricule")
PAGE = Path(__file__).with_name("index.html")
VERSION_FILE = Path(__file__).with_name("VERSION")
VERSION = VERSION_FILE.read_text().strip() if VERSION_FILE.exists() else "inconnue"
MATRICULE = re.compile(r"^[A-Za-z0-9-]{1,20}$")


def connexion():
    """Une connexion par requete (pas d'etat) ; libpq essaie bdd1 puis bdd2."""
    with open(NOEUDS) as f:
        noeuds = yaml.safe_load(f)["noeuds"]
    hotes = [n["ip"] for n in noeuds if n["role"] in ("bdd", "replique")]
    return psycopg2.connect(
        host=",".join(hotes), port=os.environ.get("DB_PORT", "5432"),
        dbname=os.environ["DB_NAME"], user=os.environ["DB_USER"],
        password=os.environ.get("DB_PASSWORD", ""), connect_timeout=2,
        # read-write : bdd2 (replique) accepte les lectures, mais /sante doit rester
        # en 503 tant qu'elle n'est pas promue (scenario V4).
        target_session_attrs="read-write")


def interroger(requete, params=()):
    """Execute une requete en lecture ; ferme toujours la connexion."""
    conn = connexion()
    try:
        with conn, conn.cursor() as cur:
            cur.execute(requete, params)
            return cur.fetchone()
    finally:
        conn.close()


class Handler(BaseHTTPRequestHandler):
    def repondre(self, code, corps, type_="application/json"):
        data = corps if isinstance(corps, bytes) else json.dumps(corps, default=str).encode()
        self.send_response(code)
        self.send_header("Content-Type", type_)
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def do_GET(self):
        url = urlparse(self.path)
        try:
            if url.path == "/":
                self.repondre(200, PAGE.read_bytes(), "text/html; charset=utf-8")
            elif url.path == "/info":
                self.repondre(200, {"hote": socket.gethostname(), "version": VERSION})
            elif url.path == "/sante":
                interroger("SELECT 1")
                self.repondre(200, {"statut": "ok"})
            elif url.path == "/resultat":
                self.resultat(parse_qs(url.query).get("matricule", [""])[0])
            else:
                self.repondre(404, {"erreur": "route inconnue"})
        except psycopg2.DataError:
            self.repondre(400, {"erreur": "matricule invalide"})
        except (psycopg2.Error, OSError, KeyError):
            self.repondre(503, {"erreur": "base indisponible"})
        except Exception:
            self.repondre(500, {"erreur": "erreur interne"})

    def resultat(self, matricule):
        if not MATRICULE.match(matricule):
            return self.repondre(400, {"erreur": "matricule manquant ou invalide"})
        # Parametre lie, aucun cast sur la colonne : l'index de CLE reste utilise.
        requete = sql.SQL("SELECT row_to_json(r) FROM {} r WHERE {} = %s").format(
            sql.Identifier(TABLE), sql.Identifier(CLE))
        ligne = interroger(requete, (matricule,))
        if ligne is None:
            self.repondre(404, {"erreur": "matricule inconnu"})
        else:
            self.repondre(200, ligne[0])


if __name__ == "__main__":
    # File d'ecoute : 5 par defaut, elle debordait sous charge (V3) et les clients retransmettaient leur SYN.
    ThreadingHTTPServer.request_queue_size = 128
    ThreadingHTTPServer(("0.0.0.0", PORT), Handler).serve_forever()
