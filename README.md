# Vagrant Lab : infra haute disponibilité

Lab multi-VM reproductible avec Vagrant pour expérimenter une architecture
web haute disponibilité : load balancers actif/passif, serveurs web
et base de données avec réplication synchrone.

## Architecture

                        Clients
                           │
                           ▼
                   VIP 192.168.56.5
                           │
             ┌─────────────┴─────────────┐
             ▼                           ▼
     ┌───────────────┐           ┌───────────────┐
     │  lb1 (actif)  │◄─ VRRP ──►│ lb2 (passif)  │
     │ HAProxy +     │           │ HAProxy +     │
     │ Keepalived    │           │ Keepalived    │
     │ .11           │           │ .12           │
     └───────┬───────┘           └───────┬───────┘
             └─────────────┬─────────────┘
                           │  round-robin
          ┌────────────────┼────────────────┐
          ▼                ▼                ▼
     ┌─────────┐      ┌─────────┐      ┌─────────┐
     │  web1   │      │  web2   │      │  webN   │
     │  nginx  │      │  nginx  │      │  nginx  │
     │  .21    │      │  .22    │      │  .2N    │
     └────┬────┘      └────┬────┘      └────┬────┘
          └────────────────┼────────────────┘
                           │
                           ▼
             ┌───────────────────────────┐
             │   db1 (primaire)  .31     │
             │   PostgreSQL              │
             └─────────────┬─────────────┘
                           │ réplication synchrone
                           ▼
             ┌───────────────────────────┐
             │   db2 (réplica)   .32     │
             │   PostgreSQL              │
             └───────────────────────────┘

## Plan d'adressage

Réseau privé du lab : _192.168.56.0/24_ (réseau host-only VirtualBox).

| Plage / IP            | Usage                                        |
| --------------------- | -------------------------------------------- |
| 192.168.56.1          | Hôte (passerelle host-only VirtualBox)       |
| _192.168.56.5_        | _VIP_ (portée par le LB actif)               |
| 192.168.56.11         | lb1 (actif)                                  |
| 192.168.56.12         | lb2 (passif)                                 |
| 192.168.56.21 à .29   | web1 à web9                                  |
| 192.168.56.31         | db1 (primaire)                               |
| 192.168.56.32         | db2 (réplica synchrone)                      |
| 192.168.56.100 à .254 | Réservé au DHCP VirtualBox (ne pas utiliser) |

Chaque VM a aussi une interface NAT (10.0.2.15) gérée par Vagrant pour
l'accès SSH et Internet : elle n'intervient pas dans le plan du lab.

## Prérequis

- [Vagrant](https://developer.hashicorp.com/vagrant/downloads)
- [VirtualBox](https://www.virtualbox.org/)
- Environ 4 Go de RAM disponibles pour 2 serveurs web

## Utilisation

bash
vagrant up # démarre toute l'infra
vagrant status # état des VMs
vagrant ssh lb1 # connexion à une VM
vagrant destroy -f # supprime tout

## Avancement

- [ ] Vagrantfile (définition des VMs et du réseau)
- [ ] Serveurs web (nginx)
- [ ] Load balancers (HAProxy)
- [ ] Haute disponibilité des LB (Keepalived / VIP)
- [ ] Base de données primaire (PostgreSQL)
- [ ] Réplica avec réplication synchrone
- [ ] Documentation des tests (failover LB, réplication)
