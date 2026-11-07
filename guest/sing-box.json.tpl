{
  "dns": {
    "servers": [
      { "type": "tcp", "server": "1.1.1.1", "tag": "remote" }
    ]
  },
  "inbounds": [
    {
      "type": "tun",
      "interface_name": "tun0",
      "address": ["172.19.0.1/30"],
      "auto_route": true,
      "strict_route": true,
      "sniff": true
    }
  ],
  "outbounds": [
    { "type": "socks", "tag": "proxy", "server": "10.0.2.2", "server_port": __SOCKS_PORT__, "version": "5" }
  ],
  "route": {
    "rules": [
      { "protocol": "dns", "action": "hijack-dns" }
    ],
    "final": "proxy",
    "auto_detect_interface": true
  }
}
