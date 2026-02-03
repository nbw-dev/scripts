#!/bin/bash

# ==========================================
# Xray-Reality 智能安装 + 自动订阅服务器
# ==========================================

RED="\033[31m"
GREEN="\033[32m"
YELLOW="\033[33m"
PLAIN="\033[0m"

# 订阅服务端口 (可修改)
SUB_PORT=2096
# 生成随机路径防止被扫描
SUB_PATH=$(openssl rand -hex 6)
WEB_ROOT="/root/xray_sub/$SUB_PATH"

if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}错误：${PLAIN} 必须使用 root 用户运行此脚本！\n"
   exit 1
fi

# 1. 基础环境与 Xray 安装
echo -e "${GREEN}正在准备环境...${PLAIN}"
apt-get update -y >/dev/null 2>&1 || yum update -y >/dev/null 2>&1
# 安装 python3 用于搭建简易订阅服务器
apt-get install -y curl wget jq openssl tar python3 >/dev/null 2>&1 || yum install -y curl wget jq openssl tar python3 >/dev/null 2>&1

echo -e "${GREEN}安装/更新 Xray-core...${PLAIN}"
bash <(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh) >/dev/null 2>&1

# 2. 智能 SNI 优选 (同前)
echo -e "${YELLOW}正在进行智能 SNI 优选...${PLAIN}"
DOMAINS="www.swift.com academy.nvidia.com www.cisco.com www.asus.com www.samsung.com www.amd.com www.umcg.nl www.fom-international.com www.u-can.co.jp github.io cname.vercel-dns.com vercel-dns.com www.python.org vuejs-jp.org vuejs.org zh-hk.vuejs.org react.dev www.java.com www.oracle.com www.mysql.com www.mongodb.com redis.io www.caltech.edu www.calstatela.edu www.suny.edu www.suffolk.edu one-piece.com lol.secure.dyn.riotcdn.net gateway.icloud.com itunes.apple.com swdist.apple.com swcdn.apple.com updates.cdn-apple.com mensura.cdn-apple.com osxapps.itunes.apple.com aod.itunes.apple.com download-installer.cdn.mozilla.net addons.mozilla.org s0.awsstatic.com d1.awsstatic.com cdn-dynmedia-1.microsoft.com"

BEST_DOMAIN=""
MIN_LATENCY=999999

for d in $DOMAINS; do
    t1=$(date +%s%3N)
    if timeout 2 openssl s_client -connect $d:443 -servername $d </dev/null &>/dev/null; then
        t2=$(date +%s%3N)
        latency=$((t2 - t1))
        # echo -e "$d - ${latency}ms" # 减少刷屏
        if [[ $latency -lt $MIN_LATENCY ]]; then
            MIN_LATENCY=$latency
            BEST_DOMAIN=$d
        fi
    fi
done

if [[ -z "$BEST_DOMAIN" ]]; then
    BEST_DOMAIN="www.microsoft.com"
fi
echo -e "${GREEN}优选 SNI: ${BEST_DOMAIN} (${MIN_LATENCY}ms)${PLAIN}"

# 3. 生成 Xray 配置
SERVER_IP=$(curl -s4 ifconfig.me)
UUID=$(xray uuid)
KEYS=$(xray x25519)
PRIVATE_KEY=$(echo "$KEYS" | grep "Private" | awk '{print $3}')
PUBLIC_KEY=$(echo "$KEYS" | grep "Public" | awk '{print $3}')
SHORT_ID=$(openssl rand -hex 8)

cat > /usr/local/etc/xray/config.json <<EOF
{
  "log": { "loglevel": "warning" },
  "inbounds": [
    {
      "port": 443,
      "protocol": "vless",
      "settings": {
        "clients": [ { "id": "$UUID", "flow": "xtls-rprx-vision" } ],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "tcp",
        "security": "reality",
        "realitySettings": {
          "show": false,
          "dest": "${BEST_DOMAIN}:443",
          "xver": 0,
          "serverNames": [ "${BEST_DOMAIN}" ],
          "privateKey": "$PRIVATE_KEY",
          "shortIds": [ "$SHORT_ID" ]
        }
      },
      "sniffing": { "enabled": true, "destOverride": [ "http", "tls", "quic" ] }
    }
  ],
  "outbounds": [ { "protocol": "freedom", "tag": "direct" } ]
}
EOF

systemctl restart xray

# 4. 生成订阅文件
echo -e "${GREEN}正在生成订阅文件...${PLAIN}"
rm -rf "$WEB_ROOT"
mkdir -p "$WEB_ROOT"

LINK_NAME="Reality-${BEST_DOMAIN}"

# 4.1 生成 VLESS 链接 (用于通用客户端)
VLESS_LINK="vless://${UUID}@${SERVER_IP}:443?security=reality&encryption=none&pbk=${PUBLIC_KEY}&headerType=none&fp=chrome&type=tcp&flow=xtls-rprx-vision&sni=${BEST_DOMAIN}&sid=${SHORT_ID}#${LINK_NAME}"

# 将 VLESS 链接 Base64 编码保存为通用订阅
echo -n "${VLESS_LINK}" | base64 -w 0 > "$WEB_ROOT/v2ray"

# 4.2 生成 Clash Meta (Mihomo) 订阅文件
# 注意：Clash 订阅需要完整的 proxies 列表格式
cat > "$WEB_ROOT/clash.yaml" <<EOF
proxies:
  - name: ${LINK_NAME}
    type: vless
    server: ${SERVER_IP}
    port: 443
    uuid: ${UUID}
    network: tcp
    tls: true
    udp: true
    flow: xtls-rprx-vision
    servername: ${BEST_DOMAIN}
    reality-opts:
      public-key: ${PUBLIC_KEY}
      short-id: ${SHORT_ID}
    client-fingerprint: chrome
EOF

# 4.3 生成 Sing-box 订阅文件
# Sing-box 订阅通常只需出站部分的 JSON
cat > "$WEB_ROOT/sb.json" <<EOF
{
  "outbounds": [
    {
      "type": "vless",
      "tag": "${LINK_NAME}",
      "server": "${SERVER_IP}",
      "server_port": 443,
      "uuid": "${UUID}",
      "flow": "xtls-rprx-vision",
      "tls": {
        "enabled": true,
        "server_name": "${BEST_DOMAIN}",
        "utls": { "enabled": true, "fingerprint": "chrome" },
        "reality": { "enabled": true, "public_key": "${PUBLIC_KEY}", "short_id": "${SHORT_ID}" }
      }
    }
  ]
}
EOF

# 5. 启动简易 HTTP 订阅服务器 (后台运行)
# 停止旧的订阅进程
pkill -f "python3 -m http.server $SUB_PORT"

# 创建 systemd 服务以保证重启后订阅依然有效
cat > /etc/systemd/system/xray-sub.service <<EOF
[Unit]
Description=Xray Simple Subscription Server
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/root/xray_sub
ExecStart=/usr/bin/python3 -m http.server $SUB_PORT
Restart=always

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable xray-sub >/dev/null 2>&1
systemctl restart xray-sub

# 6. 开启防火墙端口 (如果有 ufw 或 firewalld)
if command -v ufw >/dev/null 2>&1; then
    ufw allow $SUB_PORT/tcp >/dev/null 2>&1
fi
if command -v firewall-cmd >/dev/null 2>&1; then
    firewall-cmd --zone=public --add-port=$SUB_PORT/tcp --permanent >/dev/null 2>&1
    firewall-cmd --reload >/dev/null 2>&1
fi

# 7. 输出最终链接
IP_ADDR=$(curl -s4 ifconfig.me)
BASE_URL="http://${IP_ADDR}:${SUB_PORT}/${SUB_PATH}"

clear
echo -e "${GREEN}=========================================================${PLAIN}"
echo -e "${GREEN}      Xray-Reality 安装完成 & 订阅服务已启动${PLAIN}"
echo -e "${GREEN}=========================================================${PLAIN}"
echo ""
echo -e "${YELLOW}--- 1. Clash Meta (Mihomo) 订阅链接 ---${PLAIN}"
echo -e "在 Clash 中粘贴此 URL:"
echo -e "${GREEN}${BASE_URL}/clash.yaml${PLAIN}"
echo ""
echo -e "${YELLOW}--- 2. Sing-box 订阅链接 ---${PLAIN}"
echo -e "在 Sing-box 导入 -> 从 URL 导入:"
echo -e "${GREEN}${BASE_URL}/sb.json${PLAIN}"
echo ""
echo -e "${YELLOW}--- 3. v2rayNG / V2RayN 订阅链接 ---${PLAIN}"
echo -e "通用 Base64 订阅 (也可手动复制 VLESS 链接):"
echo -e "${GREEN}${BASE_URL}/v2ray${PLAIN}"
echo ""
echo -e "${YELLOW}--- 4. 单节点链接 (VLESS) ---${PLAIN}"
echo -e "${VLESS_LINK}"
echo ""
echo -e "${GREEN}=========================================================${PLAIN}"
echo -e "注意：订阅服务运行在端口 ${SUB_PORT}。为了安全，路径包含了随机字符串。"
echo -e "如果无法更新订阅，请检查云服务商防火墙是否放行 TCP ${SUB_PORT}。"