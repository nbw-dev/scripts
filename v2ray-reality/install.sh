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
    green "正在准备系统环境..."
    apt update && apt install -y wget curl unzip jq openssl nginx
    systemctl enable nginx && systemctl start nginx
    mkdir -p $INSTALL_PATH $WEB_PATH
}

get_best_sni() {
    green "正在筛选最佳 SNI..."
    local domains="www.microsoft.com www.python.org itunes.apple.com github.io www.amd.com"
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
    green "--> 选定 SNI: ${SELECTED_SNI}"
}

setup_xray() {
    green "检测架构并安装 Xray..."
    local ARCH=$(uname -m)
    local V_URL="https://github.com/XTLS/Xray-core/releases/latest/download/Xray-linux-64.zip"
    [[ "$ARCH" == "aarch64" ]] && V_URL="https://github.com/XTLS/Xray-core/releases/latest/download/Xray-linux-arm64-v8a.zip"

    wget -N -O /tmp/xray.zip $V_URL
    unzip -o /tmp/xray.zip -d /tmp/xray_bin
    mv /tmp/xray_bin/xray $BIN_PATH && chmod +x $BIN_PATH

    # --- 强效密钥捕捉逻辑 (兼容新旧版) ---
    $BIN_PATH x25519 > /tmp/xray_keys.txt 2>&1
    
    # 提取 PrivateKey (支持 PrivateKey:xxx 和 Private key: xxx)
    PK=$(grep -i "Private" /tmp/xray_keys.txt | sed 's/.*:[[:space:]]*//' | tr -d '[:space:]')
    
    # 提取 PublicKey (新版叫 Password，旧版叫 Public key)
    PUB=$(grep -Ei "Password|Public" /tmp/xray_keys.txt | head -n 1 | sed 's/.*:[[:space:]]*//' | tr -d '[:space:]')
    
    SHORT_ID=$(openssl rand -hex 8)

    if [ -z "$PK" ] || [ -z "$PUB" ]; then
        red "严重错误：即使使用了新逻辑依然无法捕捉密钥！"
        echo "原始输出如下：" && cat /tmp/xray_keys.txt
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
    blue "Clash 订阅:" && yellow "http://${SERVER_IP}:${SUB_PORT}/${SUB_PATH}.yaml"
    blue "V2Ray 订阅:" && yellow "http://${SERVER_IP}:${SUB_PORT}/${SUB_PATH}"
    blue "独立节点:" && echo "${VLESS_LINK}"
    green "==========================================="
}

main