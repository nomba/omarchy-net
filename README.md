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
notepad settings.json    # при необходимости: другой VDS, порты, домены
powershell -ExecutionPolicy Bypass -File host\install-host.ps1   # от администратора
```

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

## Проверка после установки

| Проверка (в госте) | Ожидание |
|---|---|
| `curl https://api.ipify.org` | IP VDS |
| `curl -I https://www.ozon.ru` / `wildberries.ru` | работает, выход с домашнего IP |
| `ssh -T git@github.com` | `Hi <user>! ...` |
| `ping -c2 8.8.8.8` | 100% потерь |
| `sudo nc -zv -w3 1.1.1.1 443` | нет соединения (даже под sudo) |
| `sudo systemctl stop sing-box && curl -m 5 https://api.ipify.org` | таймаут = kill switch работает |

Per-app настройки не нужны: `HTTP_PROXY`, `git config http.proxy`, `ProxyCommand` в ssh,
`XferCommand` в pacman.conf — всё это удалите, если настраивали раньше.

## Эксплуатация

- **Добавить российский сервис:** допишите домен в `ruDomains` в `settings.json`,
  повторно запустите `host\install-host.ps1` (идемпотентно, конфиг перегенерируется, сервисы перезапустятся).
- **Лог и статус:** `Get-Content host\proxy.log -Wait -Tail 20`.
- **Перечитать конфиг sing-box вручную:** `Get-Process sing-box | Stop-Process -Force` —
  супервизор поднимет его с новым конфигом через 5 секунд.
- **Обновление sing-box:** поднимите `singBoxVersion` и `singBoxSha256` в `settings.json`
  (хеш zip-файла релиза), повторите `install-host.ps1`.
- **Откат:** `host\uninstall-host.ps1` на хосте и `guest\uninstall-guest.sh` в госте.

## Troubleshooting

| Симптом | Причина / действие |
|---|---|
| В госте нет интернета вообще | Проверить цепочку: `proxy.log` на хосте → слушается ли 8080 (туннель) и 10809 (sing-box) → `systemctl status sing-box` в госте |
| ozon/wb частично глючат | Не хватает CDN-домена в `ruDomains` (например `ngenix.net`) |
| sing-box в госте не стартует после `pacman -Syu` | `journalctl -u sing-box -n 50` — вероятно, изменился формат конфига; файрвол при этом продолжает блокировать прямой выход |
| Туннель постоянно перезапускается | VDS недоступен или ключ не принимается: проверить `ssh root@<vds>` вручную; не должно быть второго процесса на порту 8080 |

## Skill для агентов

`skills/omarchy-net-deploy/SKILL.md` — инструкция для AI-агентов: полностью развернуть,
проверить или откатить этот сетап на новой машине. Установка в OpenCode:
скопируйте папку в `~/.config/opencode/skills/`.
