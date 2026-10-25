global
    log /dev/log local0
    log /dev/log local1 notice
    daemon
    stats socket /run/haproxy/admin.sock mode 660 level admin

defaults
    log global
    mode http
    option httplog
    option dontlognull
    timeout connect 5s
    timeout client 30s
    timeout server 30s

frontend http_in
    bind ${VIP}:80
    default_backend web_servers

backend web_servers
    balance roundrobin
    # R4 : sonde /sante (200 si la base répond, 503 sinon) ; un serveur est retiré
    # après 2 échecs espacés d'1 s et réintégré après 2 succès.
    option httpchk GET /sante
    default-server inter 1s fall 2 rise 2
    # /sante met jusqu'a 2 s a repondre quand bdd1 est eteinte (delai de connexion avant de
    # passer a bdd2) : sans ce delai de reponse, la sonde (1 s) rejette des serveurs sains.
    timeout check 4s
${BACKENDS}
