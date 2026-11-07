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

tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT
sed "s/__SOCKS_PORT__/$PORT/g" sing-box.json.tpl > "$tmpdir/sing-box.json"
sed "s/__SOCKS_PORT__/$PORT/g" nftables.conf.tpl > "$tmpdir/nftables.conf"
sudo install -D -m644 "$tmpdir/sing-box.json" /etc/sing-box/config.json
sudo install -D -m644 "$tmpdir/nftables.conf" /etc/nftables.conf

# При повторном запуске файрвол уже активен: сначала загружаем новые правила
# и восстанавливаем прокси, чтобы pacman не требовал временный прямой доступ.
if command -v sing-box >/dev/null 2>&1 && command -v nft >/dev/null 2>&1; then
    sudo nft flush ruleset
    sudo nft -f /etc/nftables.conf
    sudo systemctl restart sing-box
fi
sudo pacman -Sy --needed --noconfirm sing-box nftables python openbsd-netcat

sudo nft flush ruleset
sudo nft -f /etc/nftables.conf
sudo systemctl enable --now sing-box nftables
sudo systemctl restart sing-box

echo
echo 'OK. Проверки:'
echo '  curl https://api.ipify.org        -> IP VDS'
echo '  curl -I https://www.ozon.ru       -> работает (direct делает хост)'
echo '  ping -c2 -I enp0s5 8.8.8.8        -> 100% потерь (прямой выход закрыт)'
