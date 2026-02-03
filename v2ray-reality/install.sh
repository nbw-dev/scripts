#!/bin/bash

# ==========================================
# 你的個人定制安裝腳本 (修復 Clash 訂閱版)
# 功能：Xray-Reality + SNI 優選 + Nginx 雙格式訂閱
# ==========================================

INSTALL_PATH="/usr/local/etc/xray"
BIN_PATH="/usr/local/bin/xray"
WEB_PATH="/var/www/html"
PORT=443
SUB_PORT=8080                   # 訂閱伺服器連接埠
SUB_PATH=$(openssl rand -hex 6)  # 隨機訂閱路徑
SERVER_IP=$(curl -s ifconfig.me)
UUID=$(cat /proc/sys/kernel/random/uuid)

# 顏色定義
green() { echo -e "\033[32m\033[01m$1\033[0m"; }
blue() { echo -e "\033[36m\033[01m$1\033[0m"; }
yellow() { echo -e "\033[33m\033[01m$1\033[0m"; }
red() { echo -e "\033[31m\033[01m$1\033[0m"; }

# 1. 系統檢查與依賴安裝
check_sys() {
    green "正在檢查系統並安裝依賴..."
    apt update && apt install -y wget curl unzip jq openssl nginx
    systemctl enable nginx
}

# 2. 智能篩選最佳 SNI
get_best_sni() {
    green "正在進行 SNI 延遲篩選 (從你提供的列表)..."
    local domains="www.swift.com academy.nvidia.com www.cisco.com www.asus.com www.samsung.com www.amd.com github.io cname.vercel-dns.com vercel-dns.com www.python.org itunes.apple.com swdist.apple.com download-installer.cdn.mozilla.net s0.awsstatic.com cdn-dynmedia-1.microsoft.com"
    local best_time=99999
    SELECTED_SNI="www.microsoft.com"

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
    green "--> 篩選完成！最佳 SNI: ${SELECTED_SNI}"
}

# 3. 安裝 Xray 核心
install_xray() {
    green "安裝 Xray 核心..."
    mkdir -p $INSTALL_PATH
    local XRAY_URL="https://github.com/XTLS/Xray-core/releases/latest/download/Xray-linux-64.zip"
    wget -N --no-check-certificate -O /tmp/xray.zip $XRAY_URL
    unzip -o /tmp/xray.zip -d /tmp/xray_bin
    mv /tmp/xray_bin/xray $BIN_PATH
    chmod +x $BIN_PATH
    rm -rf /tmp/xray.zip /tmp/xray_bin
}

# 4. 生成 Xray 配置文件
config_xray() {
    local KEYS=$($BIN_PATH x25519)
    PK=$(echo "$KEYS" | grep "Private" | awk '{print $3}')
    PUB=$(echo "$KEYS" | grep "Public" | awk '{print $3}')
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

# 5. 配置 Nginx 訂閱服務 (雙格式)
setup_subscription() {
    green "配置 Nginx 訂閱服務..."
    
    # 設置 Nginx 監聽埠
    cat <<EOF > /etc/nginx/sites-available/default
server {
    listen $SUB_PORT;
    root $WEB_PATH;
    location / { try_files \$uri \$uri/ =404; }
}
EOF
    systemctl restart nginx

    local REMARK="My_Reality_${SERVER_IP}"
    # 生成 VLESS 鏈接
    VLESS_LINK="vless://${UUID}@${SERVER_IP}:${PORT}?security=reality&sni=${SELECTED_SNI}&fp=chrome&pbk=${PUB}&sid=${SHORT_ID}&type=tcp&flow=xtls-rprx-vision#${REMARK}"
    
    mkdir -p $WEB_PATH
    # (1) 通用 Base64 訂閱
    echo -n "$VLESS_LINK" | base64 -w 0 > "$WEB_PATH/$SUB_PATH"

    # (2) Clash 專用 YAML 訂閱
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
  - name: "節點選擇"
    type: select
    proxies: ["${REMARK}", "DIRECT"]
rules:
  - FINAL,節點選擇
EOF
}

# 6. 啟動服務
start_services() {
    cat <<EOF > /etc/systemd/system/xray.service
[Unit]
Description=Xray Service
After=network.target
[Service]
ExecStart=$BIN_PATH run -c $INSTALL_PATH/config.json
Restart=on-failure
[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload && systemctl enable xray && systemctl restart xray
}

# 7. 輸出結果
show_results() {
    echo -e "\n"
    green "==========================================="
    green "          Xray Reality 安裝成功！          "
    green "==========================================="
    
    blue "1. v2rayN / v2rayNG / 小火箭 訂閱連結:"
    yellow "http://${SERVER_IP}:${SUB_PORT}/${SUB_PATH}"
    echo "-------------------------------------------"
    
    blue "2. Clash / FLClash / Clash Verge 訂閱連結:"
    yellow "http://${SERVER_IP}:${SUB_PORT}/${SUB_PATH}.yaml"
    echo "-------------------------------------------"
    
    blue "3. 單節點 VLESS 連結 (直接複製導入):"
    echo "$VLESS_LINK"
    green "==========================================="
    red "注意：請務必放行防火牆 TCP 埠: $PORT 和 $SUB_PORT"
}

# 執行主程序
main() {
    check_sys
    get_best_sni
    install_xray
    config_xray
    setup_subscription
    start_services
    show_results
}

main