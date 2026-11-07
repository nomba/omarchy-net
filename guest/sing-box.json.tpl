{
  "dns": {
    "servers": [
      { "type": "tcp", "server": "1.1.1.1", "tag": "remote", "detour": "proxy" }
    ]
  },
  "inbounds": [
    {
      "type": "tun",
      "interface_name": "tun0",
      "stack": "system",
      "address": ["172.19.0.1/30"],
      "auto_route": true,
      "strict_route": true
    }
  ],
  "outbounds": [
    { "type": "socks", "tag": "proxy", "server": "10.0.2.2", "server_port": __SOCKS_PORT__, "version": "5" }
  ],
  "route": {
    "rules": [
      { "action": "sniff" },
      { "protocol": "dns", "action": "hijack-dns" }
    ],
    "final": "proxy",
    "auto_detect_interface": true
  }
}
