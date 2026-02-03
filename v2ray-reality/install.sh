#!/bin/bash

# ==========================================
# 终极版 Xray-Reality 安装脚本 (IPv4 优先 + 双订阅版)
# ==========================================

INSTALL_PATH="/usr/local/etc/xray"
BIN_PATH="/usr/local/bin/xray"
WEB_PATH="/var/www/html"
PORT=443
SUB_PORT=8080
SUB_PATH=$(openssl rand -hex 6)

# 1. 强制获取 IPv4
SERVER_IP=$(curl -s4 http://icanhazip.com || curl -s4 http://ifconfig.me)
UUID=$(cat /proc/sys/kernel/random/uuid)

# 颜色
green() { echo -e "\033[32m\033[01m$1\033[0m"; }
blue() { echo -e "\033[36m\033[01m$1\033[0m"; }
red() { echo -e "\033[31m\033[01m$1\033[0m"; }

# 准备环境
prepare() {
    apt update && apt install -y wget curl unzip jq openssl nginx
    systemctl enable nginx && systemctl start nginx
    mkdir -p $INSTALL_PATH $WEB_PATH
}

# 筛选 SNI
get_sni() {
    green "正在优选 SNI..."
    local domains="www.python.org www.microsoft.com itunes.apple.com github.io"
    SELECTED_SNI="www.microsoft.com"
    local best_time=9999
    for d in $domains; do
        t1=$(date +%s%3N)
        if timeout 1 openssl s_client -connect $d:443 -servername $d </dev/null &>/dev/null; then
            t2=$(date +%s%3N)
            time_taken=$((t2 - t1))
            if [[ $time_taken -lt $best_time ]]; then
                best_time=$time_taken
                SELECTED_SNI=$d
            fi
        fi
    done
}

# 安装 Xray 并【修复公钥获取逻辑】
setup_xray() {
    green "安装 Xray..."
    local XRAY_URL="https://github.com/XTLS/Xray-core/releases/latest/download/Xray-linux-64.zip"
    wget -N -O /tmp/xray.zip $XRAY_URL
    unzip -o /tmp/xray.zip -d /tmp/xray_bin
    mv /tmp/xray_bin/xray $BIN_PATH && chmod +x $BIN_PATH

    # 关键修复：稳健地获取密钥
    $BIN_PATH x25519 > $INSTALL_PATH/key.txt
    PK=$(grep "Private key:" $INSTALL_PATH/key.txt | awk '{print $3}')
    PUB=$(grep "Public key:" $INSTALL_PATH/key.txt | awk '{print $3}')
    SHORT_ID=$(openssl rand -hex 8)

    cat <<EOF > $INSTALL_PATH/config.json
{
  "log": { "loglevel": "warning" },
  "inbounds": [{
    "port": $PORT, "protocol": "vless",
    "settings": { "clients": [{ "id": "$UUID", "flow": "xtls-rprx-vision" }], "decryption": "none" },
    "streamSettings": {
      "network": "tcp", "security": "reality",
      "realitySettings": { "show": false, "dest": "${SELECTED_SNI}:443", "serverNames": ["${SELECTED_SNI}"], "privateKey": "$PK", "shortIds": ["$SHORT_ID"] }
    }
  }],
  "outbounds": [{ "protocol": "freedom" }]
}
EOF
}

# 配置订阅【修复 YAML 格式与 MIME】
setup_sub() {
    # 修复 Nginx 识别问题
    cat <<EOF > /etc/nginx/sites-available/default
server {
    listen $SUB_PORT;
    root $WEB_PATH;
    location / {
        add_header Content-Type 'text/yaml; charset=utf-8';
        try_files \$uri \$uri/ =404;
    }
}
EOF
    systemctl restart nginx

    local REMARK="Reality_$SERVER_IP"
    
    # 1. Base64 订阅
    VLESS="vless://${UUID}@${SERVER_IP}:${PORT}?security=reality&sni=${SELECTED_SNI}&fp=chrome&pbk=${PUB}&sid=${SHORT_ID}&type=tcp&flow=xtls-rprx-vision#${REMARK}"
    echo -n "$VLESS" | base64 -w 0 > "$WEB_PATH/$SUB_PATH"

    # 2. YAML 订阅 (修复格式)
    cat <<EOF > "$WEB_PATH/${SUB_PATH}.yaml"
port: 7890
socks-port: 7891
allow-lan: true
mode: rule
proxies:
  - name: "${REMARK}"
    type: vless
    server: ${SERVER_IP}
    port: ${PORT}
    uuid: ${UUID}
    network: tcp
    udp: true
    tls: true
    flow: xtls-rprx-vision
    servername: ${SELECTED_SNI}
    reality-opts:
      public-key: ${PUB}
      short-id: ${SHORT_ID}
    client-fingerprint: chrome
proxy-groups:
  - name: PROXY
    type: select
    proxies: ["${REMARK}", "DIRECT"]
rules:
  - MATCH,PROXY
EOF
}

main() {
    prepare
    get_sni
    setup_xray
    setup_sub
    cat <<EOF > /etc/systemd/system/xray.service
[Unit]
Description=Xray
After=network.target
[Service]
ExecStart=$BIN_PATH run -c $INSTALL_PATH/config.json
Restart=on-failure
[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload && systemctl restart xray && systemctl enable xray
    
    green "==========================================="
    green "   修复版安装完成，请使用以下链接导入   "
    green "==========================================="
    blue "Clash/FLClash 专用 (点此导入):"
    echo "http://${SERVER_IP}:${SUB_PORT}/${SUB_PATH}.yaml"
    echo "-------------------------------------------"
    blue "V2RayN/v2rayNG 订阅:"
    echo "http://${SERVER_IP}:${SUB_PORT}/${SUB_PATH}"
    green "==========================================="
}

main