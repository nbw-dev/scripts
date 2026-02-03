#!/bin/bash

# ==========================================
# 功能：Xray-Reality + 智能 SNI + 双格式订阅 + 单节点输出
# ==========================================

INSTALL_PATH="/usr/local/etc/xray"
BIN_PATH="/usr/local/bin/xray"
WEB_PATH="/var/www/html"
PORT=443
SUB_PORT=8080
SUB_PATH=$(openssl rand -hex 6)

SERVER_IP=$(curl -s4 http://icanhazip.com || curl -s4 http://ifconfig.me)
UUID=$(cat /proc/sys/kernel/random/uuid)

green() { echo -e "\033[32m\033[01m$1\033[0m"; }
blue() { echo -e "\033[36m\033[01m$1\033[0m"; }
yellow() { echo -e "\033[33m\033[01m$1\033[0m"; }
red() { echo -e "\033[31m\033[01m$1\033[0m"; }

prepare_env() {
    green "正在准备环境..."
    apt update && apt install -y wget curl unzip jq openssl nginx
    systemctl enable nginx && systemctl start nginx
    mkdir -p $INSTALL_PATH $WEB_PATH
}

get_best_sni() {
    SELECTED_SNI="www.microsoft.com"
}

setup_xray() {
    green "下载并安装 Xray..."
    local ARCH=$(uname -m)
    local V_URL="https://github.com/XTLS/Xray-core/releases/latest/download/Xray-linux-64.zip"
    [[ "$ARCH" == "aarch64" ]] && V_URL="https://github.com/XTLS/Xray-core/releases/latest/download/Xray-linux-arm64-v8a.zip"

    wget -N -O /tmp/xray.zip $V_URL
    unzip -o /tmp/xray.zip -d /tmp/xray_bin
    mv /tmp/xray_bin/xray $BIN_PATH && chmod +x $BIN_PATH

    # --- 核心提取逻辑：改用【行号提取】 ---
    # 强制将输出转为纯文本，去掉可能存在的干扰
    $BIN_PATH x25519 | tr -d '\r' > /tmp/xray_keys.txt 2>&1
    
    # 第 1 行去掉冒号前的部分，提取私钥
    PK=$(sed -n '1p' /tmp/xray_keys.txt | awk -F': ' '{print $2}' | tr -d '[:space:]')
    # 如果 awk 没拿到（因为没空格），就用最粗暴的 cut
    [[ -z "$PK" ]] && PK=$(sed -n '1p' /tmp/xray_keys.txt | cut -d':' -f2 | tr -d '[:space:]')

    # 第 2 行去掉冒号前的部分，提取公钥 (Password)
    PUB=$(sed -n '2p' /tmp/xray_keys.txt | awk -F': ' '{print $2}' | tr -d '[:space:]')
    [[ -z "$PUB" ]] && PUB=$(sed -n '2p' /tmp/xray_keys.txt | cut -d':' -f2 | tr -d '[:space:]')
    
    SHORT_ID=$(openssl rand -hex 8)

    if [ -z "$PK" ] || [ -z "$PUB" ]; then
        red "错误：行号提取法依然失败！"
        echo "当前文件内容：" && cat -A /tmp/xray_keys.txt
        exit 1
    fi
    # ------------------------------------

    cat <<EOF > $INSTALL_PATH/config.json
{
  "log": { "loglevel": "warning" },
  "inbounds": [{
    "port": $PORT, "protocol": "vless",
    "settings": { "clients": [{ "id": "$UUID", "flow": "xtls-rprx-vision" }], "decryption": "none" },
    "streamSettings": {
      "network": "tcp", "security": "reality",
      "realitySettings": {
        "show": false, "dest": "${SELECTED_SNI}:443", "serverNames": ["${SELECTED_SNI}"],
        "privateKey": "$PK", "shortIds": ["$SHORT_ID"]
      }
    }
  }],
  "outbounds": [{ "protocol": "freedom" }]
}
EOF
}

setup_sub() {
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
    VLESS_LINK="vless://${UUID}@${SERVER_IP}:${PORT}?security=reality&sni=${SELECTED_SNI}&fp=chrome&pbk=${PUB}&sid=${SHORT_ID}&type=tcp&flow=xtls-rprx-vision#${REMARK}"
    echo -n "$VLESS_LINK" | base64 -w 0 > "$WEB_PATH/$SUB_PATH"
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
    prepare_env
    get_best_sni
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
        echo -e "\n"
    green "==========================================="
    green "          Xray Reality 安装成功！          "
    green "==========================================="
    blue "1. Clash / FLClash 订阅 (推荐):"
    yellow "http://${SERVER_IP}:${SUB_PORT}/${SUB_PATH}.yaml"
    echo "-------------------------------------------"
    blue "2. V2RayN / v2rayNG 订阅:"
    yellow "http://${SERVER_IP}:${SUB_PORT}/${SUB_PATH}"
    echo "-------------------------------------------"
    blue "3. 独立 VLESS 节点 (直接导入):"
    magenta "${VLESS_LINK}"
    green "==========================================="
    red "提示：请务必确保云商后台已开启 TCP 443 和 8080 端口"
    echo -e "\n"
}

main