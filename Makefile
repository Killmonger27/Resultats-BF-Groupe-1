# Commandes courantes. 'make' ou 'make help' liste les cibles.
# Les essais longs passent par caffeinate (macOS) : la mise en veille suspendrait les VM.
CAFF  := $(shell command -v caffeinate >/dev/null 2>&1 && echo "caffeinate -dimsu")
LABEL ?= n2

.DEFAULT_GOAL := help
.PHONY: help up status destroy rebuild api pannes panne-bdd charge idempotence bascule e4 deploy

help: ## Liste des commandes
	@grep -E '^[a-z0-9-]+:.*## ' $(MAKEFILE_LIST) | awk -F':.*## ' '{printf "  make %-12s %s\n", $$1, $$2}'

up: ## Démarre la plateforme (NB_APP=4 make up : 4 serveurs applicatifs)
	vagrant up

status: ## État des VM
	vagrant status

destroy: ## Détruit toutes les VM
	vagrant destroy -f

rebuild: ## R1 : détruit puis reconstruit tout, chronométré
	$(CAFF) ./tests/r1_reconstruction.sh

api: ## Contrat de l'API (7 contrôles)
	./tests/api.sh

pannes: ## V2 et V6 : panne d'un serveur et du répartiteur (3 essais chacun)
	$(CAFF) ./tests/v2_v6_pannes.sh

panne-bdd: ## V4 : panne de la base (sans promotion)
	$(CAFF) ./tests/v4_panne_bdd.sh

charge: ## V3 : charge ab (LABEL=n4 pour 4 serveurs)
	$(CAFF) ./tests/v3_charge.sh $(LABEL)

idempotence: ## R2 : deux rejeux du provisionnement par rôle
	$(CAFF) ./tests/r2_idempotence.sh

bascule: ## R6 : bascule de la base (bdd2 devient primaire, reconstruire ensuite)
	$(CAFF) ./tests/r6_bascule.sh

e4: ## E4 : mise à jour sous charge (version 2.0)
	$(CAFF) ./tests/e4_deploiement.sh 2.0

deploy: ## E4 : déploiement serveur par serveur de app/
	./scripts/deploy.sh
