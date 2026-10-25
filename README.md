# Vagrant Lab : infra haute disponibilité

Lab multi-VM reproductible avec Vagrant pour expérimenter une architecture
web haute disponibilité : load balancers actif/passif, serveurs web
et base de données avec réplication synchrone.

## Architecture

                        Clients
                           │
                           ▼
                   VIP 192.168.56.5
                           │
             ┌─────────────┴─────────────┐
             ▼                           ▼
     ┌───────────────┐           ┌───────────────┐
     │  lb1 (actif)  │◄─ VRRP ──►│ lb2 (passif)  │
     │ HAProxy +     │           │ HAProxy +     │
     │ Keepalived    │           │ Keepalived    │
     │ .11           │           │ .12           │
     └───────┬───────┘           └───────┬───────┘
             └─────────────┬─────────────┘
                           │  round-robin
          ┌────────────────┼────────────────┐
          ▼                ▼                ▼
     ┌─────────┐      ┌─────────┐      ┌─────────┐
     │  web1   │      │  web2   │      │  webN   │
     │  nginx  │      │  nginx  │      │  nginx  │
     │  .21    │      │  .22    │      │  .2N    │
     └────┬────┘      └────┬────┘      └────┬────┘
          └────────────────┼────────────────┘
                           │
                           ▼
             ┌───────────────────────────┐
             │   db1 (primaire)  .31     │
             │   PostgreSQL              │
             └─────────────┬─────────────┘
                           │ réplication synchrone
                           ▼
             ┌───────────────────────────┐
             │   db2 (réplica)   .32     │
             │   PostgreSQL              │
             └───────────────────────────┘

## Plan d'adressage

Réseau privé du lab : _192.168.56.0/24_ (réseau host-only VirtualBox).

| Plage / IP            | Usage                                        |
| --------------------- | -------------------------------------------- |
| 192.168.56.1          | Hôte (passerelle host-only VirtualBox)       |
| _192.168.56.5_        | _VIP_ (portée par le LB actif)               |
| 192.168.56.11         | lb1 (actif)                                  |
| 192.168.56.12         | lb2 (passif)                                 |
| 192.168.56.21 à .29   | web1 à web9                                  |
| 192.168.56.31         | db1 (primaire)                               |
| 192.168.56.32         | db2 (réplica synchrone)                      |
| 192.168.56.100 à .254 | Réservé au DHCP VirtualBox (ne pas utiliser) |

Chaque VM a aussi une interface NAT (10.0.2.15) gérée par Vagrant pour
l'accès SSH et Internet : elle n'intervient pas dans le plan du lab.

## Prérequis

- [Vagrant](https://developer.hashicorp.com/vagrant/downloads)
- [VirtualBox](https://www.virtualbox.org/)
- Environ 4 Go de RAM disponibles pour 2 serveurs web

## Utilisation

```bash
vagrant up # démarre toute l'infra
vagrant status # état des VMs
vagrant ssh lb1 # connexion à une VM
vagrant destroy -f # supprime tout
```

## Structure du dépôt

```text
Vagrantfile    définition des VM et du réseau (source unique : config/noeuds.yml)
Makefile       commandes courantes (make help)
.env.exemple   modèle des secrets (cp .env.exemple .env)
app/           service HTTP (app.py, index.html, VERSION)
conf/          modèles HAProxy et Keepalived
config/        noeuds.yml, engendré par le Vagrantfile
scripts/       provisionnement des VM et procédures d'exploitation (voir scripts/README.md)
tests/         scénarios de test et de mesure (voir tests/README.md)
resultats/     sorties brutes des mesures (voir resultats/README.md)
docs/          dossiers par rôle ; docs/references/ (hors Git) : sujet et captures
```

## Tests : application, HAProxy et failover

Après le démarrage, vérifier les services applicatifs :

```bash
vagrant ssh app1 -c 'systemctl is-active resultats-bf'
vagrant ssh app2 -c 'systemctl is-active resultats-bf'
vagrant ssh app1 -c 'curl -fsS http://127.0.0.1:8080/info'
vagrant ssh app2 -c 'curl -fsS http://127.0.0.1:8080/info'
```

HAProxy doit ensuite répartir les requêtes vers les applications sur le port
`8080`. La route `/info` ne dépend pas de PostgreSQL :

```bash
curl -fsS http://192.168.56.5/info
for i in 1 2 3 4; do curl -fsS http://192.168.56.5/info; done
```

HAProxy sonde `GET /sante` toutes les secondes et retire un serveur après deux
échecs (R4) : un serveur dont la base ne répond pas ne reçoit plus de trafic.
Depuis l'hôte, le répartiteur est joignable par la VIP `192.168.56.5` (réseau
privé) : aucun port n'est redirigé vers l'hôte (R8).

La route `/sante` nécessite PostgreSQL : elle renvoie `503` tant qu'aucune base
en lecture-écriture n'est joignable (voir `docs/README-partie-donnees.md`). Dans
ce cas, tous les serveurs étant retirés, c'est HAProxy qui répond lui-même `503`
au client.

## Test du failover des load balancers

`lb1` démarre en `MASTER` et porte `192.168.56.5`; `lb2` démarre en
`BACKUP`. Les tests `/sante` et `/resultat` nécessitent que les nœuds
PostgreSQL soient démarrés (`vagrant up bdd1 bdd2`).

```bash
# Vérifier que la VIP est sur lb1
vagrant ssh lb1 -c 'ip -4 addr show | grep -F 192.168.56.5'
vagrant ssh lb2 -c '! ip -4 addr show | grep -F 192.168.56.5'

# Simuler la panne du maître
vagrant ssh lb1 -c 'sudo systemctl stop keepalived'
vagrant ssh lb2 -c 'ip -4 addr show | grep -F 192.168.56.5'

# Rétablir lb1 et vérifier le retour de la VIP
vagrant ssh lb1 -c 'sudo systemctl start keepalived'
vagrant ssh lb1 -c 'ip -4 addr show | grep -F 192.168.56.5'
```

## Application (serveurs applicatifs `app1` à `appN`)

Chaque serveur applicatif exécute le même service HTTP (`app/app.py`, Python 3,
sans état : ni session, ni fichier local, ni compteur). Il lit les résultats
dans PostgreSQL et écoute sur `0.0.0.0:8080`.

| Route | Réponse |
| ----- | ------- |
| `GET /` | page de démonstration (boutons pour appeler les routes ci-dessous) |
| `GET /info` | `200` et le nom d'hôte du serveur et la version déployée : `{"hote": "app1", "version": "1.0"}` |
| `GET /sante` | `200` si un `SELECT 1` réussit, `503` si la base est injoignable |
| `GET /resultat?matricule=XXX` | `200` et la ligne en JSON ; `404` matricule inconnu ; `400` matricule absent ou invalide ; `503` base indisponible |

Un matricule valide contient 1 à 20 caractères : lettres, chiffres ou `-`.
Si la base tombe, le service reste vivant (réponses `503`) et reprend tout
seul quand elle revient. Les adresses des bases (`bdd1`, puis `bdd2` en secours)
sont lues dans `config/noeuds.yml`.

### Configuration

Aucun mot de passe n'est versionné. Avant `vagrant up`, copier le modèle
versionné `.env.exemple` en `.env` (ignoré par Git), puis choisir les mots de
passe :

```bash
cp .env.exemple .env
```

Le fichier ne contient que des lignes `CLE=valeur`, sans espace, ni `$`, ni
guillemets, ni accent grave (il est lu par le shell). `DB_NAME`, `DB_USER` et
`DB_PASSWORD` sont ceux que `scripts/bdd.sh` crée côté PostgreSQL ;
`REPL_PASSWORD` ne sert qu'à la réplication. Variables reconnues par
l'application (toutes facultatives sauf `DB_PASSWORD`) :

| Variable | Défaut | Rôle |
| -------- | ------ | ---- |
| `APP_PORT` | `8080` | port d'écoute (HAProxy doit viser le même) |
| `DB_NAME` | `resultats_bf` | nom de la base |
| `DB_USER` | `app` | utilisateur PostgreSQL |
| `DB_PASSWORD` | vide | mot de passe PostgreSQL |
| `DB_PORT` | `5432` | port PostgreSQL |
| `DB_TABLE` | `resultats` | table lue |
| `DB_CLE` | `matricule` | colonne de recherche (doit être indexée) |

Sans `.env`, `vagrant up` réussit mais `/sante` renvoie `503` : le script
affiche un avertissement.

### Installation et vérification

`scripts/app.sh` installe les paquets, copie l'application dans
`/opt/resultats-bf`, écrit la configuration dans `/etc/resultats-bf` et crée le
service systemd `resultats-bf` (redémarrage automatique, actif au démarrage). Il
réécrit tous ses fichiers : on peut le rejouer sans risque avec
`vagrant provision app1`.

```bash
vagrant ssh app1 -c 'systemctl is-active resultats-bf'          # active
vagrant ssh app1 -c 'curl -s localhost:8080/info'               # {"hote": "app1", "version": "1.0"}
curl -s http://192.168.56.21:8080/sante                         # 200 si la base répond
curl -s 'http://192.168.56.21:8080/resultat?matricule=<un matricule>'
vagrant ssh app1 -c 'journalctl -u resultats-bf -n 20'          # journal du service
```

Remplacer l'adresse par celle du répartiteur une fois HAProxy en place. La page
`http://<adresse>/` permet de faire ces appels depuis un navigateur.

### Vérification de l'API et mise à jour sans coupure (extension E4)

`tests/api.sh` vérifie les codes et les formats de chaque route
(7 contrôles, `OK` ou `KO`).

`scripts/deploy.sh` met à jour les serveurs applicatifs un par un : chaque
serveur est retiré du répartiteur (`drain`, via le socket d'administration de
HAProxy), mis à jour (`scripts/maj-app.sh` copie `app/` et redémarre le
service), puis remis en service dès que HAProxy le voit `UP`. Les noms des
serveurs et des répartiteurs viennent de `config/noeuds.yml`. Prérequis : au
moins 2 serveurs applicatifs, `socat` sur les répartiteurs (installé par
`scripts/lb.sh`) et une base saine.

```bash
./tests/api.sh                 # contrat de l'API
./scripts/deploy.sh            # mise à jour serveur par serveur
./tests/e4_deploiement.sh 2.0  # démonstration : passe en 2.0 sous charge et compte les erreurs
```

La version affichée par `/info` vient de `app/VERSION`. `e4_deploiement.sh` écrit la
sortie brute dans `resultats/e4/`.

### Scénarios de test et de mesure

Chaque scénario du sujet (R1, R2, R6, V2 à V6, E4) tient en une commande dans
`tests/`, avec le résultat attendu pour chacun : voir `tests/README.md`. Les
commandes courantes existent aussi avec `make` (`make help`). Les sorties brutes
des mesures sont rangées dans `resultats/`. Pour vérifier une branche avant de la
fusionner, suivre `docs/guide-verification.md`.

### Lancer l'application sans Vagrant (développement)

Il faut Python 3, `psycopg2` et `PyYAML`, et un PostgreSQL accessible :

```bash
export DB_NAME=resultats_bf DB_USER=app DB_PASSWORD=<mot de passe>
export NOEUDS_FILE=config/noeuds.yml   # adresses lues dans ce fichier
python3 app/app.py                     # puis ouvrir http://localhost:8080/
```

## Avancement

- [ ] Vagrantfile (définition des VMs et du réseau)
- [ ] Application HTTP (`app/`, `scripts/app.sh` : code écrit et testé en local, à valider sous Vagrant)
- [ ] Serveurs web (nginx)
- [ ] Load balancers (HAProxy)
- [ ] Haute disponibilité des LB (Keepalived / VIP) — test à exécuter
- [ ] Base de données primaire (PostgreSQL)
- [ ] Réplica avec réplication synchrone
- [ ] Documentation des tests (failover LB, réplication)
