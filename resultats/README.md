# Résultats

Sorties brutes des scénarios de `tests/`. Chaque chiffre du dossier (`docs/`) doit pouvoir être retrouvé ici. Aucune valeur n'est retouchée.

| Dossier | Contenu |
|---|---|
| `campagne1/` | première campagne (plateforme d'origine) : charge `ab` (N=2 et N=4), pannes V2 et V6, idempotence R2, observations transcrites, contexte |
| `campagne2/` | campagne principale, sur plateforme reconstruite : reconstructions, V2, V3 (plusieurs séries), V4, V6, R2, R6 ; `avant_correctifs/` garde les essais antérieurs aux trois corrections ; `contexte.txt` donne le commit, la machine, les versions et les incidents de mesure |
| `e4/` | sorties de `tests/e4_deploiement.sh` (mise à jour sous charge) |

Chaque campagne contient un `observations.txt` : transcription des relevés faits à l'écran (compteurs du noyau, délais de sonde, journaux de veille) qui n'ont pas de fichier brut. Quand un journal brut a été perdu, le fichier le dit.

Les journaux de sonde (`*.log`) sont des lignes `horodatage_epoch code_http` (code 0 : pas de réponse en 1 s). Pour les relire : `python3 tests/lib/analyse.py <journal> <horodatage de la panne>`.

Pour ajouter une campagne : copier le contenu de `$OUT` (par défaut `/tmp/resultats-bf`) dans un nouveau dossier et y écrire un `contexte.txt` (date, commit, machine, versions de VirtualBox, Vagrant et de la boîte, valeur de `NB_APP`).
