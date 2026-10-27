# Scripts

Deux familles de scripts. Ils s'exécutent tous depuis `/vagrant` (dossier du dépôt synchronisé) ou depuis la racine du dépôt sur l'hôte.

## Provisionnement des VM (lancés par Vagrant)

Le Vagrantfile exécute `scripts/<rôle>.sh` sur chaque VM : ces noms ne doivent pas changer. Tous sont rejouables sans effet de bord (R2).

| Script | Rôle de la VM | Contenu |
|---|---|---|
| `app.sh` | `app` (`app1` à `appN`) | installe l'application Python, écrit `/etc/resultats-bf/app.env` depuis `.env`, crée le service systemd |
| `lb.sh` | `lb` (`lb1`, `lb2`) | HAProxy (configuration engendrée depuis `config/noeuds.yml` et `conf/haproxy/`) et Keepalived (VIP) |
| `bdd.sh` | `bdd` (`bdd1`) | PostgreSQL primaire, base, utilisateurs, table `resultats` (50 000 lignes) |
| `replique.sh` | `replique` (`bdd2`) | réplique en flux de `bdd1` |
| `lib.sh` | | fonctions partagées (lecture de `noeuds.yml`, installation de paquets, rendu des modèles) |
| `lib-pg.sh` | | fonctions partagées de `bdd.sh` et `replique.sh` |

## Procédures d'exploitation

| Script | S'exécute | Rôle |
|---|---|---|
| `bascule.sh` | hôte | promeut `bdd2` quand `bdd1` est en panne et attend le retour du service (R6) |
| `deploy.sh` | hôte | E4 : met à jour les serveurs applicatifs un par un, sans coupure |
| `maj-app.sh` | VM `app` | copie `app/` et redémarre le service ; appelé par `deploy.sh` |

Les scripts de test et de mesure sont dans `tests/`.
