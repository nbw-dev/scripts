#!/bin/bash

# ==========================================
# 终极版 Xray-Reality 安装脚本 (IPv4 优先 + 双订阅版)
# ==========================================

# --- 基础配置 ---
INSTALL_PATH="/usr/local/etc/xray"
BIN_PATH="/usr/local/bin/xray"
WEB_PATH="/var/www/html"
PORT=443
SUB_PORT=8080
SUB_PATH=$(openssl rand -hex 6)

# 强制获取 IPv4 地址，避免订阅链接格式混乱
SERVER_IP=$(curl -s4 http://icanhazip.com || curl -s4 http://ifconfig.me)
UUID=$(cat /proc/sys/kernel/random/uuid)

# 颜色定义
green() { echo -e "\033[32m\033[01m$1\033[0m"; }
blue() { echo -e "\033[36m\033[01m$1\033[0m"; }
yellow() { echo -e "\033[33m\033[01m$1\033[0m"; }
red() { echo -e "\033[31m\033[01m$1\033[0m"; }

# 1. 环境准备与 Nginx 强制安装
prepare_env() {
    green "正在准备运行环境..."
    apt update && apt install -y wget curl unzip jq openssl nginx
    systemctl enable nginx
    systemctl start nginx
    mkdir -p $WEB_PATH
}

# 2. 筛选低延迟 SNI
get_best_sni() {
    green "正在从你的列表中筛选延迟最低的 SNI..."
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
    green "--> 筛选结果: ${SELECTED_SNI} (${best_time}ms)"
}

# 3. 安装与配置 Xray
setup_xray() {
    green "正在安装 Xray 核心..."
    mkdir -p $INSTALL_PATH
    local XRAY_URL="https://github.com/XTLS/Xray-core/releases/latest/download/Xray-linux-64.zip"
    wget -N --no-check-certificate -O /tmp/xray.zip $XRAY_URL
    unzip -o /tmp/xray.zip -d /tmp/xray_bin
    mv /tmp/xray_bin/xray $BIN_PATH
    chmod +x $BIN_PATH

    # 生成 Reality 密钥
    local KEYS=$($BIN_PATH x25519)
    PK=$(echo "$KEYS" | grep "Private" | awk '{print $3}')
    PUB=$(echo "$KEYS" | grep "Public" | awk '{print $3}')
    SHORT_ID=$(openssl rand -hex 8)

    # 写入配置
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

# 4. 配置订阅分发系统 (Nginx)
setup_sub() {
    green "正在配置订阅链接服务..."
    
    # 强制覆盖 Nginx 默认配置
    cat <<EOF > /etc/nginx/sites-available/default
server {
    listen $SUB_PORT;
    root $WEB_PATH;
    server_name _;
    location / {
        try_files \$uri \$uri/ =404;
        add_header Content-Type 'text/plain; charset=utf-8';
    }
}
EOF
    systemctl restart nginx

    local REMARK="Reality_${SERVER_IP}"
    VLESS_LINK="vless://${UUID}@${SERVER_IP}:${PORT}?security=reality&sni=${SELECTED_SNI}&fp=chrome&pbk=${PUB}&sid=${SHORT_ID}&type=tcp&flow=xtls-rprx-vision#${REMARK}"

    # 处理 Clash 专用 IP (若是 IPv6 加方括号)
    local CLASH_IP=$SERVER_IP
    [[ "$SERVER_IP" == *:* ]] && CLASH_IP="[$SERVER_IP]"

    # (1) 生成 V2Ray 格式 (Base64)
    echo -n "$VLESS_LINK" | base64 -w 0 > "$WEB_PATH/$SUB_PATH"

    # (2) 生成 Clash 格式 (YAML)
    cat <<EOF > "$WEB_PATH/${SUB_PATH}.yaml"
port: 7890
socks-port: 7891
allow-lan: true
mode: rule
proxies:
  - name: "${REMARK}"
    type: vless
    server: ${CLASH_IP}
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
  - name: "🚀 节点选择"
    type: select
    proxies: ["${REMARK}", "DIRECT"]
rules:
  - FINAL,🚀 节点选择
EOF
}

# 5. 启动服务与扫尾
start_all() {
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

# 6. 最终展示
show_results() {
    echo -e "\n"
    green "==========================================="
    green "          Xray Reality 安装成功！          "
    green "==========================================="
    
    blue "1. v2rayN / v2rayNG / 小火箭 订阅链接:"
    yellow "http://${SERVER_IP}:${SUB_PORT}/${SUB_PATH}"
    echo "-------------------------------------------"
    
    blue "2. Clash / FLClash / Verge 订阅链接:"
    yellow "http://${SERVER_IP}:${SUB_PORT}/${SUB_PATH}.yaml"
    echo "-------------------------------------------"
    
    blue "3. 独立 VLESS 节点链接:"
    echo "$VLESS_LINK"
    green "==========================================="
    red "注意：请确保已在云面板防火墙开启 TCP 端口: $PORT 和 $SUB_PORT"
}

# 顺序执行
main() {
    prepare_env
    get_best_sni
    setup_xray
    setup_sub
    start_all
    show_results
}

main