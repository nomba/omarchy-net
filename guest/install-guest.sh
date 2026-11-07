#!/usr/bin/env bash
# Идемпотентная установка в госте Try Omarchy (Arch):
#   sing-box с TUN перехватывает весь трафик -> SOCKS на хост (10.0.2.2)
#   nftables: разрешён ТОЛЬКО порт прокси хоста (kill switch при падении sing-box)
# Запуск из репозитория, проброшенного общей папкой:
#   cd /mnt/host/guest && bash install-guest.sh
set -euo pipefail
cd "$(dirname "$0")"

PORT=$(python3 -c "import json;print(json.load(open('../settings.json'))['socksPort'])")
echo ">> SOCKS-порт хоста: $PORT"

sudo pacman -Sy --needed --noconfirm sing-box nftables python

sudo install -D -m644 <(sed "s/__SOCKS_PORT__/$PORT/g" sing-box.json.tpl) /etc/sing-box/config.json
sudo install -D -m644 <(sed "s/__SOCKS_PORT__/$PORT/g" nftables.conf.tpl) /etc/nftables.conf

sudo nft flush ruleset
sudo nft -f /etc/nftables.conf
sudo systemctl enable --now sing-box nftables
sudo systemctl restart sing-box

echo
echo 'OK. Проверки:'
echo '  curl https://api.ipify.org        -> IP VDS'
echo '  curl -I https://www.ozon.ru       -> работает (direct делает хост)'
echo '  ping -c2 8.8.8.8                  -> 100% потерь (прямой выход закрыт)'
