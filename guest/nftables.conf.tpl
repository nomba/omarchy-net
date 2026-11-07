# ГЛАВНОЕ УСЛОВИЕ: гость может отправлять пакеты только на SOCKS-порт хоста.
# Никаких DNS-исключений, никаких исключений по UID, никакого direct.
# Даже root в госте не может уйти мимо прокси, не меняя этих правил.

table inet filter {
    chain output {
        type filter hook output priority filter; policy drop;
        oifname "lo" accept
        ct state established,related accept
        udp sport 68 udp dport 67 accept
        ip daddr 10.0.2.2 tcp dport __SOCKS_PORT__ accept
    }
}
