#!/bin/bash

VALID_ARGS=$(getopt -o '' --long sslisten:,ssport:,sspass:,ssmode:,ssmethod:,ddnstoken:,ddnsdomain:,ddnsnetinf:,ddnsipv4:,ddnsipv6:,gituser:,gitpass:,giturl: -- "$@")
if [[ $? -ne 0 ]]; then
    exit 1;
fi
eval set -- "$VALID_ARGS"

SSSERVER_LISTEN="${SS_LISTEN:-0.0.0.0}"
SSSERVER_PORT="${SS_PORT:-443}"
SSSERVER_PASSWORD="${SS_PASS:-yourpassword}"
SSSERVER_MODE="${SS_MODE:-tcp_only}"
SSSERVER_METHOD="${SS_METHOD:-chacha20-ietf-poly1305}"

DDNS_API_TOKEN="${DDNS_API_TOKEN:-yourtoken}"
DDNS_DOMAIN="${DDNS_DOMAIN:-yoursubdomain}"
DDNS_NETINTERFACE="${DDNS_NETINTERFACE:-ens4}"
DDNS_IPV4="${DDNS_IPV4:-true}"
DDNS_IPV6="${DDNS_IPV6:-true}"

GIT_USER="${GIT_USER:-yourgituser}"
GIT_PASS="${GIT_PASS:-yourgitpass}"
GIT_URL="${GIT_URL:-yourgiturl}" # github.com/user/repo.git

while true; do
  case "$1" in
    --sslisten)
        SSSERVER_LISTEN="$2"
        shift 2
        ;;
    --ssport)
        SSSERVER_PORT="$2"
        shift 2
        ;;
    --sspass)
        SSSERVER_PASSWORD="$2"
        shift 2
        ;;
    --ssmode)
        SSSERVER_MODE="$2"
        shift 2
        ;;
    --ssmethod)
        SSSERVER_METHOD="$2"
        shift 2
        ;;
    --ddnstoken)
        DDNS_API_TOKEN="$2"
        shift 2
        ;;
    --ddnsdomain)
        DDNS_DOMAIN="$2"
        shift 2
        ;;
    --ddnsnetinf)
        DDNS_NETINTERFACE="$2"
        shift 2
        ;;
    --ddnsipv4)
        DDNS_IPV4="$2"
        shift 2
        ;;
    --ddnsipv6)
        DDNS_IPV6="$2"
        shift 2
        ;;
    --gituser)
        GIT_USER="$2"
        shift 2
        ;;
    --gitpass)
        GIT_PASS="$2"
        shift 2
        ;;
    --giturl)
        GIT_URL="$2"
        shift 2
        ;;
    -- ) shift; break ;;
    * ) break ;;
  esac
done

echo """
SSSERVER_LISTEN is ${SSSERVER_LISTEN}
SSSERVER_PORT is ${SSSERVER_PORT}
SSSERVER_PASSWORD is ${SSSERVER_PASSWORD}
SSSERVER_MODE is ${SSSERVER_MODE}
SSSERVER_METHOD is ${SSSERVER_METHOD}

DDNS_API_TOKEN is ${DDNS_API_TOKEN}
DDNS_DOMAIN is ${DDNS_DOMAIN}
DDNS_NETINTERFACE is ${DDNS_NETINTERFACE}
DDNS_IPV4 is ${DDNS_IPV4}
DDNS_IPV6 is ${DDNS_IPV6}

GIT_USER is ${GIT_USER}
GIT_PASS is ${GIT_PASS}
GIT_URL is ${GIT_URL}
"""

curl -fsSL https://get.docker.com |bash

if ! lsmod | grep bbr;then
    echo "net.core.default_qdisc=fq" |sudo tee -a /etc/sysctl.conf
    echo "net.ipv4.tcp_congestion_control=bbr" |sudo tee -a /etc/sysctl.conf
    sudo sysctl -p
fi

sudo mkdir -p /etc/docker

cat <<EOF |sudo tee /etc/docker/daemon.json
{
  "exec-opts": ["native.cgroupdriver=systemd"],
  "live-restore": true,
  "max-concurrent-downloads": 10,
  "default-ulimit": ["nofile=1048576:1048576"],
  "selinux-enabled": false,
  "log-driver": "json-file",
  "log-level": "warn",
  "log-opts": {
    "max-size": "30m",
    "max-file": "3"
  }
}
EOF

sudo systemctl enable docker
sudo systemctl restart docker

cat <<EOF |tee ~/docker-compose.yml
version: "3.8"
services:
  ssserver:
    container_name: ssserver
    image: "ghcr.io/shadowsocks/ssserver-rust:latest"
    restart: always
    network_mode: "host"
    volumes:
      - ./ss-server.json:/etc/shadowsocks-rust/config.json
  ddns-go:
    image: jeessy/ddns-go
    container_name: ddns-go
    restart: always
    network_mode: host
    command: -c /app/ddns-config.yml -f 864000 -noweb
    volumes:
      - ./ddns-config.yml:/app/ddns-config.yml
EOF

cat <<EOF |tee ~/ss-server.json
{
  "server": "${SSSERVER_LISTEN}",
  "server_port": ${SSSERVER_PORT},
  "password": "${SSSERVER_PASSWORD}",
  "timeout": 5000,
  "mode": "${SSSERVER_MODE}",
  "method": "${SSSERVER_METHOD}",
  "fast_open": false,
  "workers": 100,
  "prefer_ipv6": true,
  "ipv6_first": true,
  "nameserver": "8.8.8.8,1.1.1.1"
}
EOF

format_domains() {
    # 将输入的逗号分隔的域名转换为YAML格式
    echo "$1" | tr ',' '\n' | sed 's/^/            - /'
}

cat <<EOF |tee ~/ddns-config.yml
---
dnsconf:
    - ipv4:
        enable: ${DDNS_IPV4}
        gettype: url
        url: https://myip4.ipip.net,https://ddns.oray.com/checkip,https://ip.3322.net,https://4.ipw.cn
        netinterface: ${DDNS_NETINTERFACE}
        cmd: ""
        domains:
$(format_domains "${DDNS_DOMAIN}")
      ipv6:
        enable: ${DDNS_IPV4}
        gettype: netInterface
        url: https://speed.neu6.edu.cn/getIP.php,https://v6.ident.me,https://6.ipw.cn
        netinterface: ${DDNS_NETINTERFACE}
        cmd: ""
        ipv6reg: ""
        domains:
$(format_domains "${DDNS_DOMAIN}")
      dns:
        name: cloudflare
        id: ""
        secret: ${DDNS_API_TOKEN}
      ttl: "1"
user:
    username: ""
    password: ""
webhook:
    webhookurl: ""
    webhookrequestbody: ""
    webhookheaders: ""
notallowwanaccess: true
EOF

if [[ "X$GIT_USER" != "Xyourgituser" ]] && [[ "X$GIT_PASS" != "Xyourgitpass" ]] && [[ "X$GIT_URL" != "Xyourgiturl" ]]; then
    git config --global url."https://api:$GIT_PASS@github.com/".insteadOf "https://github.com/"
    git config --global url."https://ssh:$GIT_PASS@github.com/".insteadOf "ssh://git@github.com/"
    git config --global url."https://git:$GIT_PASS@github.com/".insteadOf "git@github.com:"
    git clone ${GIT_URL} && \
    cd $(basename ${GIT_URL} .git) && \
    bash init.sh
fi

sudo usermod -a -G docker $USER && newgrp docker && exit
docker compose up -d
