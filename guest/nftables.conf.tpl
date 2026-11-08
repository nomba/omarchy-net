# ГЛАВНОЕ УСЛОВИЕ: из физического интерфейса гостя разрешён только SOCKS-порт хоста.
# tun0 — внутренний интерфейс sing-box, а не прямой выход; без него output policy drop
# отбрасывает трафик до обработки TUN. После остановки sing-box tun0 исчезает.
# Никаких DNS-исключений, никаких исключений по UID, никакого direct.
# Даже root в госте не может уйти мимо прокси, не меняя этих правил.

table inet filter {
    chain output {
        type filter hook output priority filter; policy drop;
        oifname "lo" accept
        ct state established,related accept
        udp sport 68 udp dport 67 accept
        oifname "tun0" accept
        ip daddr 10.0.2.2 tcp dport __SOCKS_PORT__ accept
        # Try Omarchy: каналы управления лаунчера на хосте (10.0.2.2 = loopback
        # хоста через slirp; трафик за пределы хоста не уходит, инвариант прокси
        # не нарушается). 4451 - guest agent, 4448/4449 - буфер обмена.
        ip daddr 10.0.2.2 tcp dport { 4448, 4449, 4451 } accept
    }
}
