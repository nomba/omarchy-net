# omarchy-net

Воспроизводимый сетевой сетап для [Try Omarchy for Windows](https://github.com/omacom/try-omarchy-windows):
**весь** трафик гостя идёт через прокси на хосте, ozon/wb — напрямую, Windows-приложения (HAPP) не затрагиваются.

## Архитектура

```
Windows-приложения → HAPP (независимо, этот репозиторий их не трогает)

Omarchy (гость)
  └─ sing-box TUN (tun0, auto_route)  — перехватывает ВЕСЬ трафик, включая DNS и SSH
       └─ SOCKS → 10.0.2.2:<socksPort>  (единственное разрешение в nftables!)
            └─ sing-box на хосте
                 ├─ ruDomains (ozon/wb…) → direct с IP вашего ПК
                 └─ остальное → 127.0.0.1:<tunnelPort> → SSH-туннель → HTTP-прокси на VDS

Супервизор omarchy-proxy.ps1 держит ssh-туннель и sing-box хоста запущенными
(перезапуск при падении, единый лог host/proxy.log).
```

**Главное условие:** файрвол гостя (`guest/nftables.conf.tpl`) разрешает только исходящие
пакеты на порт прокси хоста. Нет исключений по UID, нет прямого DNS, нет direct.
При падении sing-box интернет в госте исчезает полностью (kill switch), а не «утекает напрямую».

## Требования

- Windows 10/11 x64, включённая аппаратная виртуализация, установленная Try Omarchy.
- Встроенный OpenSSH-клиент (`C:\Windows\System32\OpenSSH\ssh.exe`).
- SSH-доступ к VDS **по ключу без пароля** (`ssh root@<vds>` должен заходить молча).
  Ключ хранится в `~/.ssh` конкретной машины и **не входит** в репозиторий.
- На VDS на `127.0.0.1:<vdsProxyPort>` работает HTTP CONNECT-прокси.
- PowerShell 5.1+, права администратора для установки на хосте.

## Установка на новой машине

```powershell
git clone <url-репозитория> omarchy-net
cd omarchy-net
Copy-Item settings.json settings.local.json
notepad settings.local.json   # обязательно: vdsHost; при необходимости порты и домены
powershell -ExecutionPolicy Bypass -File host\install-host.ps1   # от администратора
```

`settings.json` — версионируемый шаблон без реального адреса VDS. Персональные параметры
хранятся в `settings.local.json`, который добавлен в `.gitignore`. Все скрипты используют
локальный файл, если он существует, иначе — шаблон. Поэтому `git diff` не покажет ваш VDS.

Проверка хоста:

```powershell
curl.exe --socks5 127.0.0.1:10809 https://api.ipify.org   # ожидается IP VDS
```

Затем гость. Пробросьте репозиторий общей папкой и запустите инсталлятор:

```powershell
TryOmarchy.exe -share "C:\path\to\omarchy-net"
```

```bash
# внутри Omarchy:
cd /mnt/host/guest
bash install-guest.sh
```

## Время и геолокация по VDS

Гостевой установщик получает через `https://ipinfo.io/json` внешний IP, город, координаты и
часовой пояс. Ответ принимается только если внешний IP совпадает с `vdsHost` из активного файла настроек.
Затем `configure-location.sh`:

- устанавливает часовой пояс через `timedatectl`;
- сохраняет город и координаты через `omarchy-weather-location --set`.

Меняется часовой пояс, а не абсолютное системное время. NTP использует UDP/123 и через
HTTP CONNECT-туннель не проходит; ради него нельзя добавлять direct-исключение в kill switch.

Явные координаты важны: без них Omarchy спрашивает город у `wttr.in`, чья GeoIP-база может
ошибочно показывать российский город для VDS. После настройки виджет использует сохранённое
местоположение, а не автоопределение `wttr.in`.

После смены VDS или для повторной настройки выполните в госте:

```bash
cd /mnt/host/guest
bash configure-location.sh
```

Команда запрашивает sudo для системного часового пояса и перезаписывает ручной город погоды.
Для диагностики: `timedatectl`, `omarchy-weather-location` и `omarchy-weather-status`.

## Проверка после установки

| Проверка (в госте) | Ожидание |
|---|---|
| `curl https://api.ipify.org` | IP VDS |
| `timedatectl` | часовой пояс из GeoIP VDS |
| `omarchy-weather-location` / `omarchy-weather-status` | город VDS, без ошибочного RU-города от `wttr.in` |
| `curl -I https://www.ozon.ru` / `wildberries.ru` | есть HTTP-ответ, выход с домашнего IP (сейчас сайты могут отвечать 307/498) |
| `ssh -T git@github.com` | `Hi <user>! ...` |
| `ping -c2 -I enp0s5 8.8.8.8` | 100% потерь при принудительном прямом выходе |
| `sudo nc -zv -w3 1.1.1.1 443` | соединение успешно через `outbound/socks[proxy]` |
| TCP с `SO_BINDTODEVICE=enp0s5` к `1.1.1.1:443` | таймаут, включая запуск под sudo |
| `sudo systemctl stop sing-box && curl -m 5 https://api.ipify.org` | таймаут = kill switch работает |

Обычные `ping` и `nc` не проверяют прямой выход: они перехватываются TUN. Для проверки
утечки нужно явно привязать сокет к физическому `enp0s5`; при этом файрвол обязан её закрыть.

Per-app настройки не нужны: `HTTP_PROXY`, `git config http.proxy`, `ProxyCommand` в ssh,
`XferCommand` в pacman.conf — всё это удалите, если настраивали раньше.

## Управление с Windows

Один раз установите пользовательскую команду (администратор не нужен):

```powershell
powershell -ExecutionPolicy Bypass -File host\install-command.ps1
```

После этого из любого терминала:

```powershell
omarchy-net status                 # задача, порты и реальный внешний IP
omarchy-net off                    # остановить туннель и sing-box хоста
omarchy-net on                     # запустить и дождаться готовности
omarchy-net ru list                # показать ruDomains
omarchy-net ru add ngenix.net      # добавить домен или несколько через пробел
omarchy-net ru remove ngenix.net   # удалить домен или несколько через пробел
```

`off` останавливает только процессы этого сетапа: интернет в госте исчезает из-за kill switch,
а Windows-приложения и HAPP не затрагиваются. Это выключение до `on` или следующего входа
в Windows; автозапуск не удаляется. `status` возвращает 0 для `OK` и 1 для
`OFF`/`DEGRADED`, поэтому его можно использовать в скриптах.

Добавление и удаление доменов обновляет активный `settings.local.json` (либо `settings.json`,
если локального файла нет) и перезапускает прокси через `install-host.ps1`; Windows запросит UAC. Повторное добавление или удаление
отсутствующего домена ничего не меняет и не перезапускает прокси.

Команда создаётся как `%LOCALAPPDATA%\Microsoft\WindowsApps\omarchy-net.cmd` и указывает на
`host\manage.ps1` в репозитории. Не перемещайте репозиторий без повторного запуска установщика команды.

## Эксплуатация

- **Добавить российский сервис:** допишите домен в `ruDomains` в `settings.local.json`,
  повторно запустите `host\install-host.ps1` (идемпотентно, конфиг перегенерируется, сервисы перезапустятся).
- **Лог и статус:** `Get-Content host\proxy.log -Wait -Tail 20`.
- **Перечитать конфиг sing-box вручную:** `Get-Process sing-box | Stop-Process -Force` —
  супервизор поднимет его с новым конфигом через 5 секунд.
- **Обновление sing-box:** поднимите `singBoxVersion` и `singBoxSha256` в `settings.local.json`
  (хеш zip-файла релиза), повторите `install-host.ps1`.
- **Откат:** `host\uninstall-host.ps1` на хосте и `guest\uninstall-guest.sh` в госте.

## Troubleshooting

| Симптом | Причина / действие |
|---|---|
| В госте нет интернета вообще | Проверить цепочку: `proxy.log` на хосте → слушается ли 8080 (туннель) и 10809 (sing-box) → `systemctl status sing-box` в госте |
| ozon/wb частично глючат | Не хватает CDN-домена в `ruDomains` (например `ngenix.net`) |
| sing-box в госте не стартует после `pacman -Syu` | `journalctl -u sing-box -n 50` — вероятно, изменился формат конфига; файрвол при этом продолжает блокировать прямой выход |
| Туннель постоянно перезапускается | VDS недоступен или ключ не принимается: проверить `ssh root@<vds>` вручную; не должно быть второго процесса на порту 8080 |
| Задача `Queued`, прокси мёртв, в `proxy.log` нет новых строк | Ноутбук перешёл на батарею: в задаче должно быть разрешён старт от батареи (`AllowStartIfOnBatteries`, `DontStopIfGoingOnBatteries`) — переустановите `install-host.ps1` |

## Skill для агентов

`skills/omarchy-net-deploy/SKILL.md` — инструкция для AI-агентов: полностью развернуть,
проверить или откатить этот сетап на новой машине. Установка в OpenCode:
скопируйте папку в `~/.config/opencode/skills/`.
