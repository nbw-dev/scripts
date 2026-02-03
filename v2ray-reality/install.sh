#!/bin/bash

# ==========================================
# 你的个人定制安装脚本 (全平台配置输出版)
# 功能：安装 Xray-Reality + 优选 SNI + 生成导入配置
# ==========================================

INSTALL_PATH="/usr/local/etc/xray"
BIN_PATH="/usr/local/bin/xray"
PORT=443
SERVER_IP=$(curl -s ifconfig.me)
UUID=$(cat /proc/sys/kernel/random/uuid)

# 颜色
red() { echo -e "\033[31m\033[01m$1\033[0m"; }
green() { echo -e "\033[32m\033[01m$1\033[0m"; }
yellow() { echo -e "\033[33m\033[01m$1\033[0m"; }
blue() { echo -e "\033[36m\033[01m$1\033[0m"; }

check_sys() {
    apt update && apt install -y wget curl unzip jq openssl
}

get_best_sni() {
    green "正在筛选最佳 SNI..."
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
    green "最佳 SNI: ${SELECTED_SNI}"
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

install_service() {
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

# --- 新增结果输出函数 ---
show_results() {
    local REMARK="My_Reality_Node"
    
    # 1. V2RayN / V2RayNG 链接 (VLESS 标准格式)
    local VLESS_LINK="vless://${UUID}@${SERVER_IP}:${PORT}?security=reality&sni=${SELECTED_SNI}&fp=chrome&pbk=${PUB}&sid=${SHORT_ID}&type=tcp&flow=xtls-rprx-vision#${REMARK}"

    # 2. Clash Meta (Mihomo) 格式
    read -r -d '' CLASH_CONFIG <<EOF
- name: ${REMARK}
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
EOF

    # 3. Sing-box 格式
    read -r -d '' SINGBOX_CONFIG <<EOF
{
  "type": "vless",
  "tag": "${REMARK}",
  "server": "${SERVER_IP}",
  "server_port": ${PORT},
  "uuid": "${UUID}",
  "flow": "xtls-rprx-vision",
  "network": "tcp",
  "tls": {
    "enabled": true,
    "server_name": "${SELECTED_SNI}",
    "utls": { "enabled": true, "fingerprint": "chrome" },
    "reality": { "enabled": true, "public_key": "${PUB}", "short_id": "${SHORT_ID}" }
  }
}
EOF

    echo -e "\n"
    green "==========================================="
    green "          Xray Reality 安装成功！          "
    green "==========================================="
    
    blue "1. V2RayN / v2rayNG (直接复制导入):"
    echo "$VLESS_LINK"
    echo "-------------------------------------------"
    
    blue "2. Clash Meta / Mihomo (复制到 proxies 列表):"
    echo "$CLASH_CONFIG"
    echo "-------------------------------------------"
    
    blue "3. Sing-box (复制到 outbounds 列表):"
    echo "$SINGBOX_CONFIG"
    green "==========================================="
}

main() {
    check_sys
    get_best_sni
    install_xray
    config_xray
    install_service
    show_results
}

main