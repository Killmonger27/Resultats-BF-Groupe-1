"""Analyse d'un journal de sonde : python3 analyse.py journal t_evenement_epoch"""
import sys
from collections import Counter

journal, t0 = sys.argv[1], float(sys.argv[2])
lignes = [(float(a), int(b)) for a, b in (l.split() for l in open(journal) if l.strip())]
codes = Counter(c for _, c in lignes)
erreurs = [(t, c) for t, c in lignes if c != 200]
print(f"requetes: {len(lignes)}  codes: {dict(codes)}  erreurs: {len(erreurs)}")
if not erreurs:
    print("aucune erreur")
    sys.exit(0)
premiere, derniere = erreurs[0][0], erreurs[-1][0]
print(f"premiere erreur: t+{premiere - t0:.1f} s   derniere erreur: t+{derniere - t0:.1f} s   "
      f"periode degradee (premiere -> derniere erreur): {derniere - premiere:.1f} s")
# plus longue serie continue d'erreurs
meilleure, courante, debut = 0.0, 0.0, None
for t, c in lignes:
    if c != 200:
        debut = t if debut is None else debut
        courante = t - debut
        meilleure = max(meilleure, courante)
    else:
        debut, courante = None, 0.0
print(f"plus longue serie ininterrompue d'erreurs: {meilleure:.1f} s")
# retour a 10 reponses 200 consecutives apres la derniere erreur
apres = [t for t, c in lignes if t > derniere]
if len(apres) >= 10 and all(c == 200 for t, c in lignes if t > derniere):
    print(f"stable (200 en continu) a partir de t+{apres[0] - t0:.1f} s ({len(apres)} reponses 200 apres la derniere erreur)")
