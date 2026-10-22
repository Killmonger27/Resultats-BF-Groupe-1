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
    option httpchk GET /
${BACKENDS}
