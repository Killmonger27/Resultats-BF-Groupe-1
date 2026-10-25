"""Sonde : une requete toutes les ~0,1 s, journal 'horodatage_epoch code_http' (0 = pas de reponse)."""
import sys
import time
import urllib.error
import urllib.request

url, duree, sortie = sys.argv[1], float(sys.argv[2]), sys.argv[3]
ouvreur = urllib.request.build_opener(urllib.request.ProxyHandler({}))  # pas de proxy systeme
fin = time.time() + duree
with open(sortie, "w") as f:
    while time.time() < fin:
        t = time.time()
        try:
            code = ouvreur.open(url, timeout=1).status
        except urllib.error.HTTPError as e:
            code = e.code
        except Exception:
            code = 0
        f.write(f"{t:.3f} {code}\n")
        f.flush()
        time.sleep(max(0, 0.1 - (time.time() - t)))
