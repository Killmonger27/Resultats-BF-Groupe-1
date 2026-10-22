# Dossier d'architecture : partie données (ingénieur données)

## 1. Rôle et périmètre

Cette partie couvre la couche de données de la plateforme RÉSULTATS-BF : le serveur PostgreSQL primaire (`bdd1`), sa réplique en flux (`bdd2`), le jeu de données et la procédure de bascule. Elle répond aux exigences R5 (réplication), R6 (bascule), R7 (aucun secret dans Git) et participe à R1 et R2 (reconstruction et idempotence). Elle fournit au scénario V4 sa procédure chronométrée.

| Livrable | Fichier |
|---|---|
| Installation et configuration du primaire, jeu de données | `scripts/bdd.sh` |
| Réplique en flux | `scripts/replique.sh` |
| Fonctions communes (installation, configuration, démarrage) | `scripts/lib-pg.sh` |
| Procédure de bascule | `scripts/bascule.sh` |
| Modèle des secrets | `.env.exemple` |

## 2. Choix d'architecture et justifications

**PostgreSQL du paquet Ubuntu 24.04.** Le sujet impose la boîte `bento/ubuntu-24.04` et interdit toute image construite à la main. Le paquet de la distribution suffit, s'installe en une commande `apt-get` (connexion lente) et fournit la réplication native.

**Réplication physique en flux, asynchrone.** `bdd2` est une copie binaire de `bdd1` obtenue avec `pg_basebackup -X stream -R`, puis maintenue à jour par le flux WAL. Le mode asynchrone a été retenu pour que l'écriture sur `bdd1` n'attende pas la réplique : la latence reste faible et la panne de `bdd2` ne bloque pas `bdd1`. Le coût est une perte possible des dernières transactions en cas de bascule (voir §6).

**Slot de réplication `bdd2_slot`.** Il garantit que `bdd1` conserve les journaux WAL tant que `bdd2` ne les a pas reçus, même si `bdd2` est éteinte un moment. Le paramètre `wal_keep_size = 64MB` reste en complément.

**Moindre privilège.** L'application se connecte avec l'utilisateur `app`, qui n'a que le droit `SELECT` sur la table `resultats` : un défaut de l'application ne permet pas de modifier les résultats. La réplication utilise un rôle distinct, `replicateur`, avec le seul attribut `REPLICATION`.

**Accès réseau restreint.** PostgreSQL écoute sur `*` (condition pour être joignable depuis le réseau privé : un service sur `127.0.0.1` serait injoignable), mais `pg_hba.conf` n'autorise que le sous-réseau privé du groupe (`192.168.X.0/24`), en `scram-sha-256`, pour la base et l'utilisateur de l'application et pour la réplication. Rien n'est exposé à l'hôte (R8).

**Données dans la VM.** Le répertoire de données reste sur le disque de la machine virtuelle (`/var/lib/postgresql/...`), jamais dans le dossier synchronisé `/vagrant`, où les verrous et la durabilité ne fonctionnent pas.

## 3. Jeu de données

La base `resultats_bf` contient la table `resultats (matricule, nom, serie, moyenne, admis)` avec 50 000 lignes engendrées par `generate_series` : matricules `BF000001` à `BF050000`, séries A, C, D, E, moyennes de 0,00 à 20,00 calculées de façon déterministe (admis si moyenne ≥ 10). Le volume permet de donner un sens aux mesures de charge. L'insertion n'a lieu que si la table est vide.

## 4. Reproductibilité et idempotence (R1, R2, R7)

- **Aucun geste manuel :** `vagrant destroy -f` puis `vagrant up` reconstruit `bdd1`, charge les 50 000 lignes, reconstruit `bdd2` et relance la réplication.
- **Idempotence :**
  - les fichiers de configuration ne sont réécrits que s'ils diffèrent (`cmp`) ;
  - PostgreSQL n'est redémarré que si une configuration a changé ;
  - le bloc ajouté à `pg_hba.conf` est balisé, retiré puis réécrit, ce qui évite les doublons d'un ajout avec `>>` ;
  - les rôles, la base et le slot sont créés seulement s'ils n'existent pas ;
  - la copie `pg_basebackup` n'est refaite que si `bdd2` n'est pas déjà une réplique (présence de `standby.signal`).
- **Secrets :** les mots de passe viennent du fichier `.env`, non versionné ; seul `.env.exemple` (valeurs `changeme`) est dans Git. Les scripts s'arrêtent avec un message explicite si une variable manque. Aucun secret n'est écrit dans un script.
- **Pas d'adresse en dur :** le sous-réseau, l'adresse de `bdd1` et la liste des serveurs applicatifs (lue par `bascule.sh`) viennent de `config/noeuds.yml`, engendré par le Vagrantfile : une source de vérité unique (R3).
- **Ordre de démarrage :** `replique.sh` attend que `bdd1` réponde (jusqu'à 2 minutes) avant de copier.

## 5. Procédure de bascule (R6)

À exécuter sur l'hôte depuis la racine du dépôt, quand `bdd1` est en panne :

```bash
vagrant halt bdd1          # simulation de la panne (scénario V4)
./scripts/bascule.sh
```

Étapes de `bascule.sh` (il ne dépend jamais de `bdd1`) :

1. **Promotion de `bdd2`** : vérification que `bdd2` est en réplique, puis `pg_promote` ; attente que `pg_is_in_recovery()` vaille `false`. Si `bdd2` est déjà promue, rien n'est refait.
2. **Retour du service** : le script interroge `/sante` via le répartiteur jusqu'à obtenir 200, puis affiche deux durées : la promotion seule et la bascule complète.

Aucune redirection des serveurs applicatifs n'est nécessaire : l'application (`app/app.py`) lit les adresses des bases (`bdd1` puis `bdd2`) dans `config/noeuds.yml` et se connecte à la première qui répond. Une fois `bdd2` promue, elle la trouve d'elle-même, sans modification de configuration ni redémarrage.

**Mesures (à compléter après exécution réelle)**

| Mesure | Commande | Résultat brut | Commentaire |
|---|---|---|---|
| Durée de promotion de `bdd2` | `vagrant halt bdd1` puis `BASE_URL=http://192.168.56.21:8080 ./scripts/bascule.sh` | 22,5 s | Mesurée avec une première version du script, qui ouvrait trois connexions `vagrant ssh` successives : l'essentiel de cette durée est le coût de ces connexions, pas la promotion de PostgreSQL elle-même. Le script actuel n'en ouvre qu'une et affiche le coût d'une connexion. [À REMESURER avec la version actuelle] |
| Durée totale de bascule (apps incluses) | idem | 24,7 s | Peu significative : `/sante` répondait déjà 200 pendant la panne de `bdd1`, car l'application se rabat sur `bdd2` en lecture. Le service n'a donc pas été interrompu ; la bascule rétablit surtout la possibilité d'écrire. |
| Écriture acceptée sur `bdd2` après bascule | `INSERT` sur `bdd2` | Acceptée | Avant la promotion, la même écriture est refusée (`read-only transaction`). |
| Réponse de `/sante` après `halt bdd1`, avant bascule | `curl -i http://192.168.56.21:8080/sante` | 200 | Écart avec le scénario V4, qui attend un 503 : l'application essaie `bdd1` puis `bdd2` et lit sur la réplique. Voir §7. |
| Reconstruction `vagrant up bdd1 bdd2` | `vagrant destroy -f` puis `time vagrant up bdd1 bdd2` | real 11 min 32 s (user 0 min 40 s, sys 0 min 26 s) | Mesure sur un PC portable avec 7 Go de RAM, connexion Internet à débit non mesuré (un avertissement apt sur `noble-updates` est apparu). Mesure « à froid » : la boîte `bento/ubuntu-24.04` (version épinglée `202404.26.0`) a été téléchargée pendant la mesure ; une reconstruction avec la boîte en cache est donc plus courte. Mesure « à chaud » (boîte en cache, même poste, second `destroy -f` puis `time vagrant up bdd1 bdd2`) : real 8 min 44 s (user 0 min 26 s, sys 0 min 20 s). Le téléchargement de la boîte représente donc environ 3 min sur cette connexion ; les quelque 8 min restantes correspondent au démarrage des VM, à l'installation des paquets et à la copie `pg_basebackup`. |

## 6. Vérifications effectuées

| Exigence | Test | Résultat |
|---|---|---|
| R5 | `INSERT` sur `bdd1`, `SELECT` sur `bdd2` | Ligne visible sur `bdd2` |
| R5 | `DELETE` sur `bdd2` | Refusé : `cannot execute DELETE in a read-only transaction` |
| R2 | `vagrant provision bdd1` deux fois | Aucune erreur, 50 000 lignes (pas de doublon) |
| R2 | `vagrant provision bdd2` deux fois | Aucune erreur, aucune nouvelle copie, `bdd2` reste en réplique |
| R1 | `vagrant destroy -f` puis `vagrant up bdd1 bdd2` | Reconstruction sans intervention, 50 000 lignes sur les deux, réplication fonctionnelle |

## 7. Limites connues et ce que nous ferions autrement

- **Perte possible de données à la bascule.** La réplication est asynchrone : les transactions validées sur `bdd1` mais pas encore reçues par `bdd2` sont perdues si `bdd1` tombe. Sur ce projet en lecture quasi seule, le risque est faible ; en production, on passerait en synchrone en acceptant la latence ajoutée.
- **Bascule manuelle.** Il faut lancer le script ; un outil comme Patroni détecterait la panne et basculerait seul, mais ajoute des machines et un magasin de consensus que le budget mémoire de 3 Go ne permet pas.
- **Pas de retour automatique.** Une fois `bdd2` promue, l'ancien primaire ne peut pas redevenir réplique sans `pg_rewind` ou reconstruction. Notre procédure de retour à la normale est `vagrant destroy -f` puis `vagrant up`.
- **Risque de « split-brain ».** Si `bdd1` redémarre après la bascule, deux primaires coexistent. L'application essaie les bases dans l'ordre `bdd1`, puis `bdd2` : elle retournerait donc vers l'ancien primaire, dont les données ne contiennent pas les écritures faites sur `bdd2`. La procédure de retour à la normale (reconstruction) évite ce cas ; il faudrait sinon éteindre `bdd1` définitivement ou réordonner les adresses.
- **Écart avec le scénario V4.** Tant que `bdd1` est éteinte et `bdd2` encore en réplique, `/sante` répond 200 : l'application lit sur la réplique. Le scénario attend un 503 jusqu'à la bascule. Une correction d'une ligne côté application (`target_session_attrs=read-write` dans la connexion PostgreSQL) donnerait ce comportement ; elle est à décider avec l'ingénieur applicatif. [À METTRE À JOUR après décision et nouvelle mesure]
- **Délai de connexion de l'application.** Elle essaie `bdd1` en premier avec un délai de 2 s ; tant que `bdd1` est éteinte, chaque requête peut perdre ce délai avant de se rabattre sur `bdd2`. Non mesuré pour l'instant. [À VÉRIFIER]
- **Une seule réplique.** La perte simultanée de `bdd1` et `bdd2` interrompt le service.
- **Cache non réalisé.** Nous n'avons pas implémenté l'extension E3 (Redis) ; les consultations répétées sont donc servies par la base. [À ADAPTER selon la décision du groupe]
