## Base de données (PostgreSQL, réplication, bascule)

Deux machines : `bdd1` (primaire, lecture/écriture) et `bdd2` (réplique en flux). La table `resultats` contient 50 000 lignes.

### Prérequis

- Vagrant 2.4.x et VirtualBox (testé avec Vagrant 2.4.9 et VirtualBox 7.2.6 sous Ubuntu).
- Environ 1,5 Go de mémoire libre pour les deux machines de base de données.
- Un réseau privé `192.168.X.0/24` avec `X = 55 + numéro de groupe` (défini dans le Vagrantfile, groupe 1 : `192.168.56.0/24`).

### Configuration des secrets

Les mots de passe ne sont jamais dans Git. Avant le premier démarrage :

```bash
cp .env.exemple .env
```

Puis éditer `.env` pour choisir les mots de passe (`DB_PASSWORD`, `REPL_PASSWORD`). Le fichier `.env` est ignoré par Git ; ne le commitez jamais.

### Démarrer la base

```bash
vagrant up bdd1 bdd2
```

`bdd1` doit se terminer par `bdd1 prête : 50000 lignes.` puis `bdd2` par `bdd2 en réplication : t`. Cette commande est rejouable : `vagrant provision bdd1` et `vagrant provision bdd2` ne modifient rien.

### Vérifier

```bash
# Nombre de lignes (50000 attendu sur les deux machines)
vagrant ssh bdd1 -c "sudo -u postgres psql -d resultats_bf -c 'SELECT count(*) FROM resultats'"
vagrant ssh bdd2 -c "sudo -u postgres psql -d resultats_bf -c 'SELECT count(*) FROM resultats'"

# Réplication : écrire sur bdd1, lire sur bdd2
vagrant ssh bdd1 -c "sudo -u postgres psql -d resultats_bf -c \"INSERT INTO resultats VALUES ('TEST1','Test','A',12,true)\""
vagrant ssh bdd2 -c "sudo -u postgres psql -d resultats_bf -c \"SELECT * FROM resultats WHERE matricule='TEST1'\""

# Nettoyage de la ligne de test
vagrant ssh bdd1 -c "sudo -u postgres psql -d resultats_bf -c \"DELETE FROM resultats WHERE matricule='TEST1'\""
```

`bdd2` est en lecture seule : toute écriture y est refusée tant qu'elle n'a pas été promue.

### Basculer sur la réplique (panne de bdd1)

```bash
vagrant halt bdd1            # simulation de la panne
./scripts/bascule.sh         # promeut bdd2, attend le retour du service, affiche la durée
```

Les serveurs applicatifs n'ont rien à changer : l'application essaie `bdd1` puis `bdd2` (adresses lues dans `config/noeuds.yml`) et retrouve donc la base promue toute seule. Pour mesurer le retour du service sur un serveur précis plutôt que sur le répartiteur :

```bash
BASE_URL=http://192.168.56.21:8080 ./scripts/bascule.sh
```

Retour à la normale après une bascule : `vagrant destroy -f` puis `vagrant up` (l'ancien primaire ne se réintègre pas automatiquement).

### Dépannage

- **« DB_PASSWORD manquant »** : le fichier `.env` n'existe pas ; faire `cp .env.exemple .env`.
- **`bdd2` ne se connecte pas à `bdd1`** : démarrer `bdd1` d'abord ; `replique.sh` attend jusqu'à 2 minutes sa disponibilité.
- **Scripts qui échouent avec `^M` ou `bad interpreter`** : fins de ligne CRLF ; vérifier que `.gitattributes` est bien présent (`* text=auto eol=lf`).
