#!/bin/bash

# ==========================================
# 功能：Xray-Reality + 智能 SNI + 双格式订阅 + 单节点输出
# 修复：公钥捕获、YAML 语法兼容性、IPv4 强制校验
# ==========================================

# --- 基础配置 ---
INSTALL_PATH="/usr/local/etc/xray"
BIN_PATH="/usr/local/bin/xray"
WEB_PATH="/var/www/html"
PORT=443
SUB_PORT=8080
SUB_PATH=$(openssl rand -hex 6)

# 强制获取 IPv4 地址
SERVER_IP=$(curl -s4 http://icanhazip.com || curl -s4 http://ifconfig.me)
UUID=$(cat /proc/sys/kernel/random/uuid)

# 颜色定义
green() { echo -e "\033[32m\033[01m$1\033[0m"; }
blue() { echo -e "\033[36m\033[01m$1\033[0m"; }
yellow() { echo -e "\033[33m\033[01m$1\033[0m"; }
red() { echo -e "\033[31m\033[01m$1\033[0m"; }

# 1. 环境准备
prepare_env() {
    green "正在准备环境并安装 Nginx..."
    apt update && apt install -y wget curl unzip jq openssl nginx
    systemctl enable nginx && systemctl start nginx
    mkdir -p $INSTALL_PATH $WEB_PATH
}

# 2. 优选伪装域名 (SNI)
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

# 3. 安装 Xray 并获取密钥
setup_xray() {
    green "安装 Xray 核心..."
    local XRAY_URL="https://github.com/XTLS/Xray-core/releases/latest/download/Xray-linux-64.zip"
    wget -N -O /tmp/xray.zip $XRAY_URL
    unzip -o /tmp/xray.zip -d /tmp/xray_bin
    mv /tmp/xray_bin/xray $BIN_PATH && chmod +x $BIN_PATH

    # 关键修复：直接捕捉变量
    local KEY_INFO=$($BIN_PATH x25519)
    PK=$(echo "$KEY_INFO" | grep "Private key:" | awk '{print $3}')
    PUB=$(echo "$KEY_INFO" | grep "Public key:" | awk '{print $3}')
    SHORT_ID=$(openssl rand -hex 8)

    if [ -z "$PK" ] || [ -z "$PUB" ]; then
        red "错误：无法生成 Reality 密钥，安装中止！"
        exit 1
    fi

    cat <<EOF > $INSTALL_PATH/config.json
{
  "log": { "loglevel": "warning" },
  "inbounds": [{
    "port": $PORT,
    "protocol": "vless",
    "settings": {
      "clients": [{ "id": "$UUID", "flow": "xtls-rprx-vision" }],
      "decryption": "none"
    },
    "streamSettings": {
      "network": "tcp",
      "security": "reality",
      "realitySettings": {
        "show": false,
        "dest": "${SELECTED_SNI}:443",
        "serverNames": ["${SELECTED_SNI}"],
        "privateKey": "$PK",
        "shortIds": ["$SHORT_ID"]
      }
    }
  }],
  "outbounds": [{ "protocol": "freedom" }]
}
EOF
}

# 4. 配置订阅分发
setup_sub() {
    green "配置订阅分发..."
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
    
    # 生成单节点链接
    VLESS_LINK="vless://${UUID}@${SERVER_IP}:${PORT}?security=reality&sni=${SELECTED_SNI}&fp=chrome&pbk=${PUB}&sid=${SHORT_ID}&type=tcp&flow=xtls-rprx-vision#${REMARK}"

    # 1. 通用 Base64 订阅
    echo -n "$VLESS_LINK" | base64 -w 0 > "$WEB_PATH/$SUB_PATH"

    # 2. Clash YAML 订阅
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

# 5. 启动服务
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
    systemctl daemon-reload && systemctl restart xray && systemctl enable xray
}

# 执行
main() {
    prepare_env
    get_best_sni
    setup_xray
    setup_sub
    start_services
    
    echo -e "\n"
    green "==========================================="
    green "          Xray Reality 安装完成！          "
    green "==========================================="
    
    blue "1. Clash / FLClash 订阅链接 (YAML):"
    yellow "http://${SERVER_IP}:${SUB_PORT}/${SUB_PATH}.yaml"
    echo "-------------------------------------------"
    
    blue "2. V2RayN / v2rayNG 订阅链接 (Base64):"
    yellow "http://${SERVER_IP}:${SUB_PORT}/${SUB_PATH}"
    echo "-------------------------------------------"
    
    blue "3. 独立 VLESS 单节点链接 (直接复制导入):"
    magenta() { echo -e "\033[35m$1\033[0m"; }
    magenta "${VLESS_LINK}"
    
    green "==========================================="
    red "提示：请确保云商后台已开启 TCP 443 (节点) 和 8080 (订阅) 端口"
    echo -e "\n"
}

main