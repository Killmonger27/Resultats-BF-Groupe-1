# Dossier d'architecture : partie applicative (ingénieur applicatif)

## 1. Rôle et périmètre

Cette partie couvre le service HTTP de la plateforme RÉSULTATS-BF, son absence d'état, sa gestion des erreurs de base et l'extension E4 (déploiement sans coupure). Elle participe aux exigences R1 et R2 (reconstruction, idempotence), R3 (aucune adresse en dur), R7 (aucun secret dans Git) et R8 (aucun port exposé hors du répartiteur), et elle fournit au scénario V4 son comportement d'erreur.

| Livrable | Fichier |
|---|---|
| Service HTTP | `app/app.py` |
| Page de démonstration | `app/index.html` |
| Version déployée | `app/VERSION` |
| Provisionnement d'un serveur applicatif | `scripts/app.sh` |
| E4 : mise à jour d'un serveur | `scripts/maj-app.sh` |
| E4 : déploiement serveur par serveur | `scripts/deploy.sh` |
| Contrôle du contrat de l'API | `tests/api.sh` |
| E4 : démonstration sous charge | `tests/e4_deploiement.sh` |
| Scénarios de mesure (R1, V2, V3, V4, V6, R2, R6) | `tests/r1_reconstruction.sh`, `tests/v2_v6_pannes.sh`, `tests/v3_charge.sh`, `tests/v4_panne_bdd.sh`, `tests/r2_idempotence.sh`, `tests/r6_bascule.sh`, avec `tests/lib/sonde.py` et `tests/lib/analyse.py` |

## 2. Choix d'architecture et justifications

**Python standard et `psycopg2`, moins de 100 lignes.** Le sujet impose un service minimal (`app.py` : 95 lignes). `ThreadingHTTPServer` suffit et n'ajoute aucune dépendance au-delà de deux paquets `apt` (`python3-psycopg2`, `python3-yaml`), installés en une commande (connexion lente).

**Aucun état.** Une connexion à la base est ouverte et fermée à chaque requête ; il n'y a ni session, ni fichier d'état, ni compteur. Toute la configuration vient de l'environnement (`/etc/resultats-bf/app.env`). Le fichier `app/VERSION` est du code livré avec l'application, pas un état. C'est ce qui rend l'ajout et le retrait d'un serveur indolores.

**Écoute sur `0.0.0.0`, avec une file d'écoute de 128.** Un service sur `127.0.0.1` serait injoignable depuis le répartiteur. Aucun port des serveurs applicatifs n'est redirigé vers l'hôte (R8). La file d'écoute de `ThreadingHTTPServer` vaut 5 par défaut : sous charge (V3), elle débordait et les connexions refusées étaient retransmises une ou plusieurs secondes plus tard (voir §6, défaut 1). Elle est portée à 128.

**Adresses de la base lues dans `config/noeuds.yml`.** L'application déduit les adresses de `bdd1` et `bdd2` des rôles `bdd` et `replique` : aucune adresse en dur (R3). libpq essaie les hôtes dans l'ordre.

**`target_session_attrs=read-write`.** `bdd2` est une réplique en lecture avec `hot_standby = on` : sans cette option, l'application s'y connecterait dès que `bdd1` tombe, et `/sante` répondrait 200 alors que le scénario V4 attend un 503 jusqu'à la bascule. Avec l'option, l'application n'accepte qu'un serveur qui accepte les écritures : `/sante` reste en 503 tant que `bdd2` n'est pas promue, puis revient à 200 sans modification de configuration.

**Gestion des erreurs.**

| Situation | Réponse |
|---|---|
| Matricule absent ou invalide (1 à 20 caractères : lettres, chiffres, `-`) | 400 |
| Matricule inconnu | 404 |
| Route inconnue | 404 |
| Base injoignable ou sans primaire en écriture | 503 `{"erreur": "base indisponible"}` |
| Toute autre erreur imprévue | 500 `{"erreur": "erreur interne"}` |

Le client reçoit donc toujours une réponse JSON de l'application, ou la page 503 de HAProxy quand tous les serveurs sont retirés : jamais de page blanche ni d'erreur de connexion brute. Le matricule est un paramètre lié (pas de concaténation SQL) et la colonne n'est jamais convertie, ce qui laisse la clé primaire utilisable.

**Base absente au démarrage.** L'application ne se connecte pas au lancement et le service systemd redémarre tout seul (`Restart=always`) : l'ordre de démarrage base puis applications n'est pas critique.

**Sonde du répartiteur (R4), en collaboration avec l'architecte.** HAProxy interroge `GET /sante` (`inter 1s fall 2 rise 2`) et laisse 4 s de réponse à chaque sonde (`timeout check 4s`). Ce délai est nécessaire : quand `bdd1` est éteinte, `/sante` met jusqu'à 2 s à répondre (voir §6, défaut 2).

## 3. Reproductibilité et idempotence (R1, R2, R7)

- `scripts/app.sh` réécrit tous ses fichiers en entier (jamais de `>>`) : le rejouer ne change rien.
- Les secrets viennent de `.env` (non versionné, modèle `.env.exemple`) et sont écrits dans `/etc/resultats-bf/app.env` en mode `0600`. Aucun secret dans un script.
- Le nombre de serveurs est un paramètre (`NB_APP`) ; les scripts de déploiement lisent la liste dans `config/noeuds.yml`.

## 4. Extension E4 : déploiement sans coupure

`scripts/deploy.sh` traite les serveurs applicatifs un par un :

1. retrait du serveur du répartiteur (`set server ... state drain`, sur chaque répartiteur en marche) ;
2. attente que ses sessions actives tombent à zéro ;
3. mise à jour (`scripts/maj-app.sh` : copie de `app/` et redémarrage, attente de `/info`) ;
4. remise en service (`state ready`) et attente que HAProxy voie le serveur `UP` avant de passer au suivant.

Si une étape échoue, le déploiement s'arrête : un serveur dont la mise à jour a échoué reste retiré du répartiteur, la mauvaise version n'est donc jamais exposée. Prérequis : au moins 2 serveurs applicatifs, `socat` sur les répartiteurs, base saine.

Démonstration : `./tests/e4_deploiement.sh 2.0` lance des clients en parallèle sur l'adresse virtuelle, déploie la version 2.0, puis compte les réponses non 200 et affiche la répartition par serveur et par version.

## 5. Mesures

**Conditions.** Mesures du 25/10/2026, Apple M1 Pro (10 cœurs, 16 Go), VirtualBox 7.2.22, Vagrant 2.4.9, boîte `bento/ubuntu-24.04` 202510.26.0, `NB_APP=2` sauf mention. `ab` et la sonde tournent sur l'hôte : ils partagent le processeur avec les VM. Contexte complet (commit, versions, incidents de mesure) : `resultats/campagne2/contexte.txt`. Sorties brutes : `resultats/campagne2/` (campagne principale), `resultats/campagne1/` (première campagne) et `resultats/e4/`. Les relevés faits à l'écran (compteurs du noyau, délais de sonde HAProxy, latences après bascule, journaux de veille) sont transcrits dans `resultats/campagne2/observations.txt`, et les résultats des essais de V2 et V6 faits avant le redémarrage du Mac dans `resultats/campagne1/observations.txt` : **leurs journaux bruts sont perdus** (le dossier temporaire a été effacé au démarrage de macOS), seuls les résultats de l'analyse sont conservés.

**Protocole.** Les pannes sont mesurées avec une sonde qui interroge la VIP toutes les 0,1 s (`tests/lib/sonde.py`, abandon à 1 s) et un script d'analyse (`tests/lib/analyse.py`) ; `t = 0` est le lancement de la commande de panne. La charge est mesurée avec `ab -q -n 2000 -c 50` après une passe de chauffe non comptée, puis 5 passes. Les essais de la campagne finale tournent sous `caffeinate` (voir §6, défaut 4).

| Exigence ou scénario | Mesure | Résultat |
|---|---|---|
| **R1 / V5** reconstruction | `vagrant destroy -f` puis `vagrant up`, sans aucune commande ensuite | 3 reconstructions complètes, toutes en code de sortie 0 : **7 min 28 s** (N=2), **9 min 8 s** (N=4), **7 min 32 s** (N=2 finale). Test de fumée à chaque fois : `/sante` 200, 7 contrôles d'API OK, 50 000 lignes sur les deux bases. |
| **V1** répartition | 20 appels à `/info` | N=2 : 10/10 ; N=4 : 5/5/5/5. Écart (max − min) / total = 0 % (seuil : moins de 20 %). |
| **V2 / R4** panne d'un serveur applicatif | `vagrant halt app1` à t+6 s, 3 essais sur chaque plateforme | Période dégradée de première à dernière erreur : 2,2 / 0,2 / 1,3 s (1re plateforme) et 2,2 / 1,3 / 0,2 s (code final), pour 2 à 3 erreurs isolées sur environ 850 requêtes ; stable dès t+3,5 à 5,9 s. Seuil : moins de 5 s. `app1` est réintégré tout seul environ 25 s après son redémarrage. |
| **V6 / E1** panne du répartiteur | `vagrant halt lb1` à t+6 s | 8 essais sur 9 : **1 erreur** unique, à t+2,1 à 2,6 s, la VIP passe sur `lb2`. Au retour de `lb1` (`vagrant up`) : 0 ou 1 erreur. Seuil : moins de 5 s. 1 essai sur 9 non conforme (136 erreurs, 81,5 s), lors d'une session antérieure à un redémarrage du Mac ; non reproduit, cause non établie (voir §7). |
| **V4** panne de la base, sans promotion | `vagrant halt bdd1` puis `vagrant up bdd1` | Pendant la panne, `503` à chaque appel : d'abord le JSON de l'application (`{"erreur": "base indisponible"}`), puis, une fois les serveurs retirés (`app1` et `app2` `DOWN`), la page de HAProxy (107 octets). Retour à 200 en **22,5 s** après le début de `vagrant up bdd1`, sans intervention ; `bdd2` reste réplique, 50 000 lignes ; 7 contrôles OK. |
| **R6** bascule, avant correctifs (plateforme N=2) | `vagrant halt bdd1` puis `./scripts/bascule.sh` | `bdd2` promue en 1,5 s, 100/100 lignes marqueurs retrouvées, écriture acceptée. **Mais le service n'est pas revenu** : `/sante` 503, serveurs `DOWN`, 0 contrôle OK sur 7, alors que `bascule.sh` annonçait « Service de nouveau en 200 : 63,8 s ». Deux défauts (§6, défauts 2 et 3). |
| **R6** bascule, avec correctifs (plateforme N=4) | idem | `bdd2` promue en 1,6 s ; **service de nouveau en 200 en 3,7 s** (9,9 s depuis le début de l'arrêt de `bdd1`) ; 100/100 marqueurs retrouvés (aucune perte) ; écriture acceptée sur `bdd2` ; 7 contrôles OK ; les 4 serveurs `UP`. Côté client : 8 vraies réponses 503 ; ensuite le service répond 200 en 0,6 à 2,0 s par requête tant que `bdd1` est éteinte (§7). |
| **E4** mise à jour sous charge | `./tests/e4_deploiement.sh 2.0`, 8 clients | 4 essais : 5 521, 5 247, 5 306 et 5 377 requêtes, **0 erreur** à chaque fois, tous les codes 200 ; chaque serveur passe de la version 1.0 à 2.0 pendant la charge ; `E4 : OK`. |
| **R2** idempotence | deux `vagrant provision` successifs sur `app1`, `lb1`, `bdd1`, `bdd2`, empreintes avant et après | 2 campagnes (plateforme 1 et plateforme finale) : OK pour les quatre rôles, codes 0/0, fichiers identiques ; un seul bloc balisé dans `pg_hba.conf`, 50 000 lignes, heure de démarrage de PostgreSQL inchangée. |
| **R3** paramètre N | `NB_APP=4 vagrant destroy -f && vagrant up`, une seule commande | 4 lignes `server` engendrées dans `haproxy.cfg` sans édition, 4 serveurs `UP`, répartition 5/5/5/5, file d'écoute à 128 sur les 4. |
| **R5** réplication | `INSERT` sur `bdd1`, `SELECT` sur `bdd2` | ligne visible sur `bdd2` ; `DELETE` sur `bdd2` refusé (`read-only transaction`) avant la promotion. |
| **R7** secrets | recherche des valeurs réelles de `DB_PASSWORD` et `REPL_PASSWORD` dans `git log --all -S` et dans les fichiers suivis | 0 commit et 0 fichier ; aucune fuite dans `resultats/`, `tests/` ni `docs/` ; `.env` ignoré par la règle `*.env` |
| **R8** réseau | `grep forwarded_port Vagrantfile` et redirections des VM en marche | aucune redirection de port, sauf le SSH de Vagrant lié à `127.0.0.1`. Les adresses `192.168.56.x` restent joignables depuis l'hôte par construction du réseau privé : un `curl` n'est pas un test de R8. |

**V3 : montée en charge** (`ab -q -n 2000 -c 50 'http://192.168.56.5/resultat?matricule=BF000001'`, 5 passes, req/s ; 0 requête échouée dans toutes les passes) :

| Campagne | Passes | Médiane | Min | Max |
|---|---|---|---|---|
| N=2, plateforme reconstruite | 195,6 / 194,5 / 198,4 / 196,3 / 140,6 | **195,6** | 140,6 | 198,4 |
| N=2, après correction de la file d'écoute | 194,9 / 196,0 / 194,1 / 195,8 / 133,4 | **194,9** | 133,4 | 196,0 |
| N=2, sous `caffeinate`, code final | 181,0 / 181,1 / 180,4 / 180,1 / 143,6 | **180,4** | 143,6 | 181,1 |
| N=4, reconstruction à 4 serveurs | 184,2 / 183,9 / 181,5 / 180,4 / 135,0 | **181,5** | 135,0 | 184,2 |

Le débit **n'augmente pas** avec les serveurs applicatifs (le sujet l'attendait, mais le signale comme un résultat possible). Le goulot est mesuré : pendant 9 000 requêtes à N=4, `bdd1` est quasi saturée (36 % utilisateur + 39 % système, 10 % inactif ; 0 % lors d'une première mesure) alors que les serveurs applicatifs sont à 63 % d'inactivité et `lb1` à 87 %. La base unique, avec un seul processeur, limite le débit. La clé primaire sur `matricule` existe déjà : ce n'est pas un défaut d'index. Le CPU de l'hôte reste sous 70 % (20 à 41 % dans la campagne principale, jusqu'à 68 % dans la première) : il n'est pas saturé. Le même `matricule` est interrogé à chaque requête, ce qui avantage la mesure ; un tirage aléatoire donnerait un chiffre plus bas. Le débit médian varie de 180 à 196 req/s d'une campagne à l'autre avec le même code : l'écart entre deux campagnes est du bruit de la machine, pas un effet des serveurs.

## 6. Défauts révélés par la campagne de tests, et corrections

| # | Défaut | Comment il a été trouvé | Correction |
|---|---|---|---|
| 1 | **File d'écoute de l'application à 5** (valeur par défaut de `ThreadingHTTPServer`). Sous charge, des connexions étaient refusées puis retransmises 1 à 3 s plus tard : p99 de 1,2 s et creux de débit. | V3 : compteurs du noyau `TcpExtListenOverflows` à +57 (`app1`) et +61 (`app2`) en 3 passes ; `Send-Q 5` sur le port 8080 ; 327 retransmissions de SYN sur `lb1`. | `request_queue_size = 128` dans `app.py`, déployé sans coupure avec `deploy.sh`. Ensuite, 0 débordement sur 13 passes ; les p99 de 1,2 s ont disparu de la série de 5 passes. |
| 2 | **Sonde HAProxy trop courte** : `inter 1s` sans `timeout check` donne 1 s de délai de réponse à la sonde. Quand `bdd1` est éteinte, `/sante` met 1,6 à 2,05 s à répondre (délai de connexion vers `bdd1` avant `bdd2`) : HAProxy rejetait des serveurs sains (`L7TOUT`) et la bascule de la base n'aboutissait jamais au niveau du répartiteur. | R6 : après la promotion de `bdd2`, `/sante` direct sur `app1` répond 200 en 1,6 s ; HAProxy note `L7TOUT` après 1003 ms ; 221 s d'erreurs côté client. | `timeout check 4s` dans `conf/haproxy/haproxy.cfg.tpl`. Après correction, les serveurs repassent `UP` immédiatement, le service est rétabli en 3,7 s. |
| 3 | **`scripts/bascule.sh` annonçait un succès à tort** : après 60 s sans réponse 200, il affichait quand même « Service de nouveau en 200 ». | R6 : message « 63,8 s » alors que `/sante` n'a jamais répondu 200. | Le script distingue maintenant « non mesuré », « rétabli » et « échec » (code de sortie 1 et message d'erreur). |
| 4 | **Mise en veille du Mac** (réglage à 1 minute) pendant des essais non surveillés : VirtualBox suspend les VM (`SUSPENDING`/`SUSPENDED` dans `VBox.log` ; journal `pmset`). Un essai de V4 a duré 852 s au lieu de 22 s. | Anomalie de V4 : `systemd-analyze` donne 7 s de démarrage dans la VM, mais le journal VirtualBox montre 76 s de suspension. | Les essais finaux sont lancés sous `caffeinate -dimsu`. Les essais invalidés sont refaits. |

## 7. Limites connues et ce que nous ferions autrement

- **Après une bascule, chaque requête est ralentie tant que `bdd1` est injoignable.** `connect_timeout=2` s'applique à chaque hôte, et libpq essaie `bdd1` avant `bdd2` : mesuré, le service répond 200 en 0,6 à 2,0 s par requête (au lieu d'environ 30 ms). Le service reste correct mais lent jusqu'au retour à la normale (`vagrant destroy -f` puis `vagrant up`). Pistes, non réalisées : retirer `bdd1` de la configuration après la bascule, ou réduire `connect_timeout` (risque de faux échecs sous charge). Garder l'ordre des hôtes en mémoire serait un état, contraire à la consigne.
- **Plus de lecture sur la réplique.** Avec `target_session_attrs=read-write`, l'application ne lit plus sur `bdd2` tant qu'elle n'est pas promue : le service est interrompu entre la panne de `bdd1` et la bascule. C'est le comportement attendu par V4 ; en production, on accepterait de lire sur la réplique pour rester disponible.
- **Une connexion par requête.** C'est le prix de l'absence d'état : sous charge (V3), `bdd1` est la ressource saturée (voir §5). Un pool de connexions réduirait vraisemblablement ce coût, mais cela n'a pas été testé et demande de concilier le pool avec la consigne « aucun état » ; un second processeur pour la base serait l'autre levier.
- **Le débit n'augmente pas avec N**, et une passe sur cinq chute (133 à 144 req/s, p99 de 3 à 5 s, toujours la 5e passe d'une série d'environ une minute de charge). **Cause non expliquée.** Pistes testées et écartées : file d'écoute de l'application (corrigée, 0 débordement), mise en veille du Mac (le creux persiste sous `caffeinate`), connexions en `TIME_WAIT` du client (aucune). Piste non vérifiée : `app1` retransmet beaucoup de segments TCP (14 500 cumulés, +1 400 sur 3 passes de 2 000 requêtes), ce qui évoque des pertes dans le réseau virtuel VirtualBox.
- **Un essai de V6 sur 9 est non conforme** (136 erreurs, 81,5 s), observé lors de la session précédant un redémarrage du Mac, avec des VM instables. Il ne s'est pas reproduit en 8 essais ensuite. Une mise en veille du Mac est une hypothèse plausible (voir §6, défaut 4), mais ce n'est pas démontré : aucun journal de veille n'a été conservé pour cet essai.
- **Panne de la base : c'est souvent HAProxy qui répond.** Quand tous les serveurs applicatifs ont échoué la sonde, le client reçoit la page `503 Service Unavailable` de HAProxy (107 octets) plutôt que le JSON de l'application. C'est bien un 503 propre.
- **Les 4 s de `timeout check`** font qu'un serveur qui accepte la connexion mais ne répond plus est détecté après jusqu'à 4 s par sonde, contre 1 s pour un serveur arrêté. Mesuré pour un serveur arrêté (V2) : 0,2 à 2,2 s.
- **E4 dépend du socket d'administration de HAProxy.** `deploy.sh` suppose `socat` sur les répartiteurs et une base saine : si `/sante` est utilisée comme sonde, un déploiement pendant une panne de base échoue.
- **`vagrant provision` redémarre le service.** `app.sh` relance toujours le service, contrairement à `deploy.sh` qui le fait sans coupure ; pour une mise à jour de production, on utilise `deploy.sh`.
- **Mesures à répéter pour les chiffres officiels** : une campagne par scénario ; les variations observées entre campagnes (V3 : 180 à 196 req/s) rappellent qu'il faut plusieurs campagnes sur la machine de référence.
