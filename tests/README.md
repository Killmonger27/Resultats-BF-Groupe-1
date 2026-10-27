# Tests et mesures

Chaque scénario du sujet tient en une commande, à lancer **depuis la racine du dépôt**, plateforme démarrée (`vagrant up`). Les noms des scripts reprennent les codes du sujet : `r` pour les exigences, `v` pour les scénarios de validation, `e` pour les extensions.

| Script | Exigence ou scénario | Durée | Résultat attendu (seuil du sujet) |
|---|---|---|---|
| `api.sh` | contrat de l'API | quelques secondes | 7 lignes `OK`, code de sortie 0 |
| `r1_reconstruction.sh` | R1 / V5 : `vagrant destroy -f` puis `vagrant up` | 8 à 10 min | code de sortie 0, `bdd1 prête : 50000 lignes.`, `bdd2 en réplication : t`, durée à noter. **Détruit tout.** `NB_APP=4` pour tester R3 |
| `r2_idempotence.sh` | R2 : deux rejeux de `vagrant provision` par rôle | 10 min | `OK` pour `app1`, `lb1`, `bdd1`, `bdd2` (fichiers identiques, aucune erreur) |
| `v2_v6_pannes.sh` | V2 (panne d'un serveur) et V6 / E1 (panne de `lb1`) | 3 à 4 min par essai | période dégradée **moins de 5 s**, serveur réintégré tout seul ; `REP=3` essais, `SEULEMENT=v2` ou `v6` |
| `v4_panne_bdd.sh` | V4 : panne de `bdd1` sans promotion | 4 min | 503 propre pendant la panne (jamais de page blanche), retour à 200 sans intervention, 7 `OK` ensuite |
| `r6_bascule.sh` | R6 : panne de `bdd1` puis `scripts/bascule.sh` | 5 min | `Service de nouveau en 200 : N s`, 100 lignes marqueurs sur 100 retrouvées, écriture acceptée sur `bdd2`. **`bdd2` devient primaire : reconstruire ensuite** |
| `v3_charge.sh n2` | V3 : `ab -n 2000 -c 50`, 1 passe de chauffe puis 5 passes | 2 min | `Failed requests: 0` ; le débit est à relever tel quel (médiane, min, max), sans seuil |
| `e4_deploiement.sh 2.0` | E4 : mise à jour sous charge | 2 min | `E4 : OK`, 0 requête en erreur ; remettre ensuite `echo 1.0 > app/VERSION && ./scripts/deploy.sh` |

## Prérequis

`curl`, `python3`, `ab` (ApacheBench), et la plateforme démarrée. Sur un portable, lancer les essais longs sous `caffeinate -dimsu` (macOS) : la mise en veille suspend les VM et fausse les mesures (voir `docs/dossier-partie-applicative.md`, §6). Les cibles `make` le font automatiquement.

## Sorties

Les sorties brutes de chaque essai vont dans `$OUT` (par défaut `/tmp/resultats-bf`, effacé au redémarrage). Pour conserver une campagne, la copier dans `resultats/` avec un fichier de contexte (voir `resultats/README.md`). `e4_deploiement.sh` écrit directement dans `resultats/e4/`.

## Outils (`lib/`)

| Fichier | Rôle |
|---|---|
| `lib/sonde.py` | envoie une requête toutes les 0,1 s et journalise `horodatage code` (0 = pas de réponse en 1 s) |
| `lib/analyse.py` | analyse un journal : erreurs, première et dernière erreur, période dégradée, retour à la normale |
