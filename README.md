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

## Test actuel : failover des load balancers

Avant d'ajouter HAProxy et PostgreSQL, le lab valide uniquement Keepalived et
la VIP. `lb1` démarre en `MASTER` et porte `192.168.56.5`; `lb2` démarre en
`BACKUP`.

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
| `GET /info` | `200` et le nom d'hôte du serveur : `{"hote": "app1"}` |
| `GET /sante` | `200` si un `SELECT 1` réussit, `503` si la base est injoignable |
| `GET /resultat?matricule=XXX` | `200` et la ligne en JSON ; `404` matricule inconnu ; `400` matricule absent ou invalide ; `503` base indisponible |

Un matricule valide contient 1 à 20 caractères : lettres, chiffres ou `-`.
Si la base tombe, le service reste vivant (réponses `503`) et reprend tout
seul quand elle revient. Les adresses des bases (`bdd1`, puis `bdd2` en secours)
sont lues dans `config/noeuds.yml`.

### Configuration

Aucun mot de passe n'est versionné. Avant `vagrant up`, créer à la racine du
dépôt un fichier `.env` (ignoré par Git) :

```bash
cat > .env <<'EOF'
DB_NAME=resultats_bf
DB_USER=app
DB_PASSWORD=<choisir un mot de passe>
EOF
```

Ces valeurs doivent être les mêmes que celles créées côté PostgreSQL. Variables
reconnues (toutes facultatives sauf `DB_PASSWORD`) :

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
vagrant ssh app1 -c 'curl -s localhost:8080/info'               # {"hote": "app1"}
curl -s http://192.168.56.21:8080/sante                         # 200 si la base répond
curl -s 'http://192.168.56.21:8080/resultat?matricule=<un matricule>'
vagrant ssh app1 -c 'journalctl -u resultats-bf -n 20'          # journal du service
```

Remplacer l'adresse par celle du répartiteur une fois HAProxy en place. La page
`http://<adresse>/` permet de faire ces appels depuis un navigateur.

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
