vrrp_instance VI_1 {
    state ${ETAT}
    interface ${IFACE}
    virtual_router_id 51
    priority ${PRIO}
    advert_int 1
    unicast_src_ip ${MY_IP}
    unicast_peer {
        ${PEER_IP}
    }
    virtual_ipaddress {
        ${VIP}/24
    }
}