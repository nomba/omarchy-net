#!/usr/bin/env bash
# Настраивает часовой пояс и погоду Omarchy по GeoIP текущего выхода через VDS.
# Запускать от обычного пользователя гостя: bash configure-location.sh
set -euo pipefail
cd "$(dirname "$0")"

VDS_HOST=$(python3 -c "import json; print(json.load(open('../settings.json'))['vdsHost'])")
GEO_JSON=$(curl -fsS --connect-timeout 5 --max-time 20 --retry 2 --retry-all-errors 'https://ipinfo.io/json')

# ipinfo должен увидеть именно VDS, иначе нельзя случайно применить GeoIP хоста
# (например, если кто-то добавил ipinfo.io в ruDomains).
GEO_FIELDS=$(VDS_HOST="$VDS_HOST" python3 -c '
import ipaddress
import json
import math
import os
import socket
import sys
from zoneinfo import ZoneInfo

data = json.load(sys.stdin)
missing = [key for key in ("ip", "city", "loc", "timezone") if not data.get(key)]
if missing:
    raise SystemExit("ipinfo: отсутствуют поля: " + ", ".join(missing))

try:
    actual_ip = ipaddress.ip_address(str(data["ip"]))
except ValueError:
    raise SystemExit("ipinfo: некорректный внешний IP")

expected_host = os.environ["VDS_HOST"].strip().rsplit("@", 1)[-1]
try:
    expected_ip = ipaddress.ip_address(expected_host)
except ValueError:
    try:
        expected_ip = ipaddress.ip_address(socket.gethostbyname(expected_host))
    except (OSError, ValueError) as exc:
        raise SystemExit(f"Не удалось определить IP vdsHost={expected_host}: {exc}")

if actual_ip != expected_ip:
    raise SystemExit(
        f"Внешний IP {actual_ip} не совпадает с VDS {expected_ip}; "
        "геолокация не изменена"
    )

city = str(data["city"]).strip()
timezone = str(data["timezone"]).strip()
if not city or any(char in city for char in "\r\n\t"):
    raise SystemExit("ipinfo: некорректное название города")
try:
    ZoneInfo(timezone)
except Exception as exc:
    raise SystemExit(f"ipinfo: неизвестный часовой пояс {timezone}: {exc}")

try:
    latitude_text, longitude_text = str(data["loc"]).split(",", 1)
    latitude = float(latitude_text)
    longitude = float(longitude_text)
except ValueError:
    raise SystemExit("ipinfo: некорректные координаты")
if not (math.isfinite(latitude) and math.isfinite(longitude)):
    raise SystemExit("ipinfo: некорректные координаты")
if not (-90 <= latitude <= 90 and -180 <= longitude <= 180):
    raise SystemExit("ipinfo: координаты вне допустимого диапазона")

print(actual_ip)
print(city)
print(f"{latitude:.6f}")
print(f"{longitude:.6f}")
print(timezone)
' <<<"$GEO_JSON")

mapfile -t GEO <<<"$GEO_FIELDS"
if ((${#GEO[@]} != 5)); then
    echo 'Не удалось разобрать ответ ipinfo; настройки не изменены.' >&2
    exit 1
fi

IP=${GEO[0]}
CITY=${GEO[1]}
LATITUDE=${GEO[2]}
LONGITUDE=${GEO[3]}
TIMEZONE=${GEO[4]}

if ! command -v omarchy-weather-location >/dev/null 2>&1; then
    echo 'Команда omarchy-weather-location не найдена; настройки не изменены.' >&2
    exit 1
fi

echo ">> VDS GeoIP: $CITY, $TIMEZONE ($LATITUDE,$LONGITUDE), IP $IP"
sudo timedatectl set-timezone "$TIMEZONE"
omarchy-weather-location --set "$CITY" "$LATITUDE,$LONGITUDE"

echo ">> Часовой пояс: $(timedatectl show --property=Timezone --value)"
echo ">> Погода: $(omarchy-weather-location) ($LATITUDE,$LONGITUDE)"
echo 'OK. Часовой пояс и геолокация гостя настроены по VDS.'
