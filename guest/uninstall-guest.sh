#!/usr/bin/env bash
# Откат настроек в госте: остановить TUN и файрвол, вернуть обычную сеть.
# Пакеты не удаляются; пользовательские данные не затрагиваются.
set -euo pipefail
sudo systemctl disable --now sing-box nftables 2>/dev/null || true
sudo nft flush ruleset
sudo rm -f /etc/sing-box/config.json /etc/nftables.conf
echo 'OK. sing-box и nftables остановлены, правила сброшены, обычная сеть восстановлена.'
