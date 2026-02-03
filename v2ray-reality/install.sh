#!/bin/bash

# ==========================================
# 你的个人定制安装脚本 (含自动订阅生成)
# 功能：Xray-Reality + SNI 优选 + 自动 Nginx 订阅
# ==========================================

INSTALL_PATH="/usr/local/etc/xray"
BIN_PATH="/usr/local/bin/xray"
WEB_PATH="/var/www/html"
PORT=443
SUB_PORT=8080  # 订阅服务器端口，可自行修改
SUB_PATH=$(openssl rand -hex 6) # 随机订阅路径
SERVER_IP=$(curl -s ifconfig.me)
UUID=$(cat /proc/sys/kernel/random/uuid)

# 颜色
green() { echo -e "\033[32m\033[01m$1\033[0m"; }
blue() { echo -e "\033[36m\033[01m$1\033[0m"; }
yellow() { echo -e "\033[33m\033[01m$1\033[0m"; }

check_sys() {
    apt update && apt install -y wget curl unzip jq openssl nginx
    systemctl enable nginx
}

get_best_sni() {
    green "正在筛选最佳 SNI..."
    local domains="www.swift.com academy.nvidia.com www.cisco.com www.asus.com www.samsung.com www.amd.com github.io cname.vercel-dns.com"
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
}

install_xray() {
    mkdir -p $INSTALL_PATH
    local XRAY_URL="https://github.com/XTLS/Xray-core/releases/latest/download/Xray-linux-64.zip"
    wget -N --no-check-certificate -O /tmp/xray.zip $XRAY_URL
    unzip -o /tmp/xray.zip -d /tmp/xray_bin
    mv /tmp/xray_bin/xray $BIN_PATH
    chmod +x $BIN_PATH
}

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

# --- 新增：配置 Nginx 订阅服务 ---
setup_subscription() {
    green "正在配置订阅服务..."
    
    # 1. 准备节点基础信息
    local REMARK="My_Reality_${SERVER_IP}"
    VLESS_LINK="vless://${UUID}@${SERVER_IP}:${PORT}?security=reality&sni=${SELECTED_SNI}&fp=chrome&pbk=${PUB}&sid=${SHORT_ID}&type=tcp&flow=xtls-rprx-vision#${REMARK}"
    
    # 2. 生成通用订阅 (Base64) - 供 v2rayN/v2rayNG 使用
    mkdir -p $WEB_PATH
    echo -n "$VLESS_LINK" | base64 -w 0 > "$WEB_PATH/$SUB_PATH"

    # 3. 生成 Clash 专用订阅 (YAML) - 供 Clash/FLClash 使用
    # 这里的路径设为：原路径 + .yaml
    cat <<EOF > "$WEB_PATH/${SUB_PATH}.yaml"
port: 7890
socks-port: 7891
allow-lan: true
mode: rule
log-level: info
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
  - name: 🚀 节点选择
    type: select
    proxies:
      - "${REMARK}"
      - DIRECT
rules:
  - GEOIP,LAN,DIRECT
  - FINAL,🚀 节点选择
EOF

    # 4. 重启 Nginx
    systemctl restart nginx
}

show_results() {
    echo -e "\n"
    green "==========================================="
    green "          Xray Reality 安装成功！          "
    green "==========================================="
    
    blue "1. 订阅链接 (直接填入 v2rayN/v2rayNG/小火箭):"
    yellow "http://${SERVER_IP}:${SUB_PORT}/${SUB_PATH}"
    echo "-------------------------------------------"
    
    blue "2. VLESS 节点链接 (单节点直接导入):"
    echo "$VLESS_LINK"
    echo "-------------------------------------------"
    
    blue "3. Clash Meta / Sing-box 配置:"
    echo "请根据上方 VLESS 链接参数手动转换或查看脚本 show_results 函数。"
    green "==========================================="
    echo "提示：如果无法连接，请务必在云服务器防火墙开启 $PORT 和 $SUB_PORT 端口！"
}

main() {
    check_sys
    get_best_sni
    install_xray
    config_xray
    setup_subscription
    
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
    show_results
}

main