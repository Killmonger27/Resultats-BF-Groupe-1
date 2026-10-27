# Guide de vérification d'une branche avant fusion

Pour la personne qui fusionne : ce guide permet de vérifier la branche sans connaître son code. Chaque étape donne la commande, la durée, le résultat attendu et si un écart **bloque** la fusion. Tout se lance depuis la racine du dépôt.

## 1. Ce que la branche change

**Fichiers d'autres rôles, modifiés (à relire en priorité) :**

| Fichier | Rôle concerné | Changement | Où le vérifier |
|---|---|---|---|
| `conf/haproxy/haproxy.cfg.tpl` | architecte | sonde `GET /sante`, `inter 1s fall 2 rise 2`, `timeout check 4s` | étapes 6, 7 et 10 |
| `scripts/lb.sh` | architecte | installe `socat` (API d'administration de HAProxy) | étape 8 |
| `scripts/bascule.sh` | ingénieur données | n'annonce plus « Service de nouveau en 200 » si `/sante` ne revient pas ; code de sortie 1 | étape 14 |

**Travail de l'ingénieur applicatif :** `app/app.py` (503 sans primaire en écriture, erreurs en JSON, file d'écoute 128, version dans `/info`), `scripts/app.sh`, E4 (`scripts/deploy.sh`, `scripts/maj-app.sh`, `tests/e4_deploiement.sh`), les scénarios `tests/`, les mesures `resultats/`, le `Makefile`, les README d'index et `docs/dossier-partie-applicative.md`.

Le **Vagrantfile** ne change que d'une ligne : la version de la boîte, `202510.26.0` (voir §2).

## 2. Préparation (5 min)

Prérequis : VirtualBox 7, Vagrant 2.4, `curl`, `python3`, `ab` (ApacheBench), `make`, environ 4 Go de RAM libres (6 VM ; 8 VM avec `NB_APP=4`).

```bash
git fetch origin && git switch <branche>
cp .env.exemple .env          # puis choisir DB_PASSWORD et REPL_PASSWORD (sans espace ni $ " ' `)
cut -d= -f1 .env              # attendu : DB_NAME DB_USER DB_PASSWORD REPL_PASSWORD
make help                     # liste les commandes de ce guide
```

- **Boîte Vagrant.** Le Vagrantfile épingle `bento/ubuntu-24.04` `202510.26.0` (amd64 et arm64, la même pour tous les postes). L'ancienne `202404.26.0` n'existait en VirtualBox que pour amd64 : si elle réapparaît, la remplacer.
- Les messages `Fixed port collision for 22 => 2222` de Vagrant sont sans gravité.
- **Une seule commande Vagrant à la fois**, et empêcher la veille de l'ordinateur : sur macOS les cibles `make` utilisent `caffeinate` ; ailleurs, désactiver la veille. Une veille suspend les VM et fausse les mesures.

## 3. Contrôles sans VM (2 min)

```bash
git diff origin/main..HEAD --stat | tail -1
git diff origin/main..HEAD -- Vagrantfile | grep -E '^[+-][^+-]'   # attendu : seulement la ligne VERSION
for f in scripts/*.sh tests/*.sh; do bash -n "$f" || echo "ERREUR $f"; done; echo "syntaxe bash vérifiée"
python3 -c "import ast; [ast.parse(open(f).read()) for f in ('app/app.py','tests/lib/sonde.py','tests/lib/analyse.py')]; print('python OK')"
wc -l < app/app.py            # attendu : moins de 100 (limite du sujet)
git log -p origin/main..HEAD | grep -i -E "password[a-z_]*=[^<\$ ]" | grep -v changeme || echo "aucun mot de passe en clair : OK"
```

Attendu : seule la ligne `VERSION` du Vagrantfile diffère, aucune erreur de syntaxe, `app.py` sous 100 lignes, aucun mot de passe. **Bloquant** en cas d'écart.

## 4. Parcours rapide (environ 25 min) : les étapes 5 à 8

Il couvre le cœur : reconstruction, API, répartition, sonde de santé, mise à jour sans coupure. Le parcours complet (étapes 5 à 14, environ 1 h 15) ajoute la panne du répartiteur, la panne de la base, l'idempotence, la charge, le paramètre N et la bascule.

## 5. Reconstruction complète (R1) : 8 à 10 min, bloquant

```bash
make rebuild
```

Attendu : `vagrant up : code de sortie 0`, puis les lignes `bdd1 prête : 50000 lignes.`, `bdd2 en réplication : t`, `[lb1] MASTER prêt`, `[lb2] BACKUP prêt`, et 6 VM `running`. Aucune commande manuelle ne doit être nécessaire après. Mesuré : 7 min 28 s à 9 min 8 s.

## 6. Contrat de l'API, base et répartition : 2 min, bloquant

```bash
make api                                                            # 7 lignes OK
curl -s 'http://192.168.56.5/resultat?matricule=BF000001'           # {"matricule": "BF000001", "nom": "Candidat 1", "serie": "C", "moyenne": 0.37, "admis": false}
for i in $(seq 20); do curl -s http://192.168.56.5/info; echo; done | sort | uniq -c    # 10 app1 / 10 app2
vagrant ssh bdd1 -c "sudo -u postgres psql -d resultats_bf -Atc 'select pg_is_in_recovery(), count(*) from resultats'"   # f|50000
vagrant ssh bdd2 -c "sudo -u postgres psql -d resultats_bf -Atc 'select pg_is_in_recovery(), count(*) from resultats'"   # t|50000
vagrant ssh lb1 -c "grep -E 'httpchk|default-server|timeout check' /etc/haproxy/haproxy.cfg"   # option httpchk GET /sante ; default-server inter 1s fall 2 rise 2 ; timeout check 4s
```

## 7. Panne d'un serveur applicatif (V2 / R4) : environ 10 min, bloquant

```bash
SEULEMENT=v2 REP=3 make pannes
```

Attendu, pour chaque essai : `periode degradee` **moins de 5 s** (seuil du sujet), puis plus aucune erreur, et `app1 reintegre (UP)`. Mesuré : 0,2 à 2,2 s.

## 8. Mise à jour sans coupure (E4) : 2 min, bloquant

```bash
vagrant ssh lb1 -c 'command -v socat'        # /usr/bin/socat (changement de scripts/lb.sh)
make e4
git checkout -- app/VERSION && make deploy   # remet la version 1.0 sur les serveurs
```

Attendu : `E4 : OK`, `en erreur : 0`, tous les codes à 200, `app1` et `app2` vus en 1.0 puis 2.0 ; à la fin `Déploiement terminé : version 1.0`. Mesuré : 5 247 à 5 521 requêtes, 0 erreur. La démonstration écrit un fichier dans `resultats/e4/` : ne pas le committer.

## 9. Panne du répartiteur (V6 / E1) : environ 8 min, bloquant

```bash
SEULEMENT=v6 REP=2 make pannes
```

Attendu : environ **1 erreur** par essai (de t+2 à t+3 s), période dégradée **moins de 5 s**, `VIP revenue sur lb1`. Un essai isolé à plus de 5 s a été observé une fois sur 9, lors d'une session où le Mac se mettait en veille : le refaire ; s'il se reproduit sans veille, le signaler (le script affiche alors un diagnostic).

## 10. Panne de la base (V4) : 4 min, bloquant

```bash
make panne-bdd
```

Attendu : pendant la panne, un `503` (corps JSON de l'application ou page « 503 Service Unavailable » de HAProxy), jamais de page blanche ; `service de nouveau en 200` environ 22 s après le début de `vagrant up bdd1` ; `bdd2 : t|50000` ; `7 OK sur 7`.

## 11. Idempotence (R2) : 10 min, bloquant

```bash
make idempotence
```

Attendu : `OK` pour `app1`, `lb1`, `bdd1`, `bdd2` (deux rejeux sans erreur, fichiers identiques) et `/sante` à 200.

## 12. Charge (V3) : 2 min, informatif

```bash
make charge
```

Attendu : `Failed requests: 0` à chaque passe. Le débit est à relever tel quel (mesuré : médiane de 180 à 196 req/s). **Il n'y a pas de seuil** : le débit n'augmente pas avec le nombre de serveurs, la base unique à un processeur étant le goulot (expliqué dans `docs/dossier-partie-applicative.md`). Une passe sur cinq peut chuter : c'est connu et non expliqué. La colonne « CPU hôte » n'est renseignée que sous macOS.

## 13. Paramètre N (R3) : environ 10 min, bloquant

```bash
NB_APP=4 make rebuild
vagrant ssh lb1 -c "grep '^    server ' /etc/haproxy/haproxy.cfg"                    # 4 lignes server (app1 à app4), jamais éditées à la main
for i in $(seq 20); do curl -s http://192.168.56.5/info; echo; done | sort | uniq -c  # 5 par serveur
```

Pour les commandes `vagrant` suivantes avec 4 serveurs, garder `NB_APP=4` devant. L'étape 14 reconstruit ensuite à 2 serveurs.

## 14. Bascule de la base (R6) : 5 min, bloquant. **Destructif**

```bash
make bascule
```

Attendu : `bdd2` promue en moins de 3 s ; `Service de nouveau en 200 : N s` (mesuré : 3,7 s) et code de sortie 0 ; `marqueurs retrouvés sur bdd2 : 100 / 100` ; `écriture acceptée sur bdd2 : INSERT 0 1` ; `/sante` à 200 ; `7 OK sur 7`. Le changement de `scripts/bascule.sh` se vérifie ici : le script ne doit plus afficher de succès si `/sante` ne revient pas (relire le bloc `case "$RETABLI"` pour le chemin d'échec).

`bdd2` est ensuite primaire : **remettre la plateforme à neuf** avec `make rebuild` (sans `NB_APP`, retour à 2 serveurs).

## 15. Remise en état et critères de fusion

```bash
git status --short            # attendu : rien à committer (sauf éventuellement resultats/e4/e4_*.txt)
make destroy                  # facultatif : libère la mémoire
```

**Fusionner si :** les contrôles du §3 sont OK et toutes les étapes marquées « bloquant » donnent le résultat attendu. Les valeurs absolues (durées, req/s) dépendent de la machine : seuls les seuils du sujet comptent (moins de 5 s pour V2 et V6, 0 erreur pour E4, reconstruction sans intervention).

## En cas d'écart

| Symptôme | Cause probable | Que faire |
|---|---|---|
| `vagrant up` échoue : boîte introuvable pour l'architecture | ancienne boîte `202404.26.0` (amd64 seulement) | vérifier que le Vagrantfile épingle `202510.26.0` (§2) |
| `DB_PASSWORD manquant` ou `REPL_PASSWORD manquant` | `.env` incomplet | refaire `cp .env.exemple .env` et renseigner les 4 clés |
| `command not found` pendant le provisionnement | caractère spécial dans `.env` (`EOF`, `$`, espace) | corriger la ligne fautive |
| `/sante` reste en 503 après une bascule | sonde trop courte (`timeout check` absent) | vérifier que le template HAProxy de la branche est bien déployé (`vagrant provision lb1 lb2`) |
| `vagrant up` dure plus de 10 minutes sans raison | veille de l'ordinateur ou VirtualBox bloqué | relancer sans veille, voir §2 |
| mesures V3 en dents de scie | passes d'`ab` irrégulières (connu) | relever min, médiane, max et continuer |
| `deploy.sh` : « Socket HAProxy inaccessible » | `socat` absent des répartiteurs | `vagrant provision lb1 lb2` |
