#!/bin/bash
# nbwxray-reality-install.sh
# 一键部署 Xray Reality 节点
# 同时生成 Clash 和 V2Ray 订阅链接

set -e

# 颜色
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

# 检查root权限
if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}请使用 root 权限运行此脚本${NC}"
    exit 1
fi

# 生成随机端口
PORT=$(shuf -i 10000-65000 -n 1)
# 生成UUID
UUID=$(cat /proc/sys/kernel/random/uuid)

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}   南波丸 Xray Reality 一键安装脚本${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""

echo -e "${GREEN}[1/6] 安装依赖...${NC}"
apt update -y
apt install -y curl openssl nginx

echo -e "${GREEN}[2/6] 安装 Xray...${NC}"
bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install

echo -e "${GREEN}[3/6] 生成 Reality 密钥对...${NC}"
KEYS=$(/usr/local/bin/xray x25519)
# 使用 $NF 提取最后一个字段，兼容不同格式的输出
PRIVATE_KEY=$(echo "$KEYS" | grep -i "private" | awk '{print $NF}')
PUBLIC_KEY=$(echo "$KEYS" | grep -i "public" | awk '{print $NF}')
SHORT_ID=$(openssl rand -hex 8)

# 验证密钥是否生成成功
if [[ -z "$PRIVATE_KEY" ]] || [[ -z "$PUBLIC_KEY" ]]; then
    echo -e "${RED}错误: 密钥生成失败，请检查 Xray 安装${NC}"
    echo "KEYS 输出内容: $KEYS"
    exit 1
fi
echo "Private Key: ${PRIVATE_KEY}"
echo "Public Key: ${PUBLIC_KEY}"

echo -e "${GREEN}[4/6] 写入 Xray 配置...${NC}"
cat > /usr/local/etc/xray/config.json << EOF
{
  "log": {
    "loglevel": "warning"
  },
  "inbounds": [
    {
      "port": ${PORT},
      "protocol": "vless",
      "settings": {
        "clients": [
          {
            "id": "${UUID}",
            "flow": "xtls-rprx-vision"
          }
        ],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "tcp",
        "security": "reality",
        "realitySettings": {
          "dest": "www.microsoft.com:443",
          "serverNames": ["www.microsoft.com"],
          "privateKey": "${PRIVATE_KEY}",
          "shortIds": ["${SHORT_ID}"]
        }
      }
    }
  ],
  "outbounds": [
    {
      "protocol": "freedom"
    }
  ]
}
EOF

echo -e "${GREEN}[5/6] 启动 Xray 服务...${NC}"
systemctl restart xray
systemctl enable xray

# 获取服务器IP
SERVER_IP=$(curl -s4 ip.sb 2>/dev/null || curl -s6 ip.sb 2>/dev/null || curl -s ifconfig.me)

echo -e "${GREEN}[6/6] 生成订阅文件...${NC}"

# 创建订阅目录
SUBSCRIBE_DIR="/var/www/subscribe"
mkdir -p ${SUBSCRIBE_DIR}
SUBSCRIBE_TOKEN=$(openssl rand -hex 16)

# ============================================
# V2Ray 订阅 (Base64 编码的 VLESS 链接)
# ============================================
VLESS_LINK="vless://${UUID}@${SERVER_IP}:${PORT}?encryption=none&flow=xtls-rprx-vision&security=reality&sni=www.microsoft.com&fp=chrome&pbk=${PUBLIC_KEY}&sid=${SHORT_ID}&type=tcp#Reality-${SERVER_IP}"

echo "${VLESS_LINK}" | base64 -w 0 > "${SUBSCRIBE_DIR}/${SUBSCRIBE_TOKEN}.txt"

# ============================================
# Clash Meta 订阅 (YAML 格式)
# ============================================
cat > "${SUBSCRIBE_DIR}/${SUBSCRIBE_TOKEN}.yaml" << EOF
mixed-port: 7890
allow-lan: true
mode: rule
log-level: info
external-controller: 127.0.0.1:9090

dns:
  enable: true
  enhanced-mode: fake-ip
  nameserver:
    - 8.8.8.8
    - 1.1.1.1

proxies:
  - name: Reality-${SERVER_IP}
    type: vless
    server: ${SERVER_IP}
    port: ${PORT}
    uuid: ${UUID}
    network: tcp
    udp: true
    tls: true
    flow: xtls-rprx-vision
    servername: www.microsoft.com
    reality-opts:
      public-key: ${PUBLIC_KEY}
      short-id: ${SHORT_ID}
    client-fingerprint: chrome

proxy-groups:
  - name: 🚀 节点选择
    type: select
    proxies:
      - Reality-${SERVER_IP}
      - DIRECT

  - name: 🎯 全球直连
    type: select
    proxies:
      - DIRECT
      - 🚀 节点选择

rules:
  - DOMAIN-SUFFIX,cn,🎯 全球直连
  - DOMAIN-KEYWORD,baidu,🎯 全球直连
  - DOMAIN-KEYWORD,taobao,🎯 全球直连
  - DOMAIN-KEYWORD,aliyun,🎯 全球直连
  - GEOIP,CN,🎯 全球直连
  - MATCH,🚀 节点选择
EOF

# ============================================
# 配置 Nginx
# ============================================
cat > /etc/nginx/sites-available/subscribe << EOF
server {
    listen 8080;
    server_name _;
    
    location /sub/ {
        alias ${SUBSCRIBE_DIR}/;
        types {
            text/yaml yaml yml;
            text/plain txt;
        }
        default_type text/plain;
        add_header Access-Control-Allow-Origin *;
    }
}
EOF

ln -sf /etc/nginx/sites-available/subscribe /etc/nginx/sites-enabled/
rm -f /etc/nginx/sites-enabled/default 2>/dev/null || true
nginx -t && systemctl restart nginx
systemctl enable nginx

# 开放防火墙端口
if command -v ufw &> /dev/null; then
    ufw allow ${PORT}/tcp
    ufw allow 8080/tcp
fi

# ============================================
# 输出信息
# ============================================
echo ""
echo -e "${GREEN}============================================${NC}"
echo -e "${GREEN}           部署完成！${NC}"
echo -e "${GREEN}============================================${NC}"
echo ""
echo -e "${YELLOW}【节点信息】${NC}"
echo "服务器IP:    ${SERVER_IP}"
echo "端口:        ${PORT}"
echo "UUID:        ${UUID}"
echo "Public Key:  ${PUBLIC_KEY}"
echo "Short ID:    ${SHORT_ID}"
echo "SNI:         www.microsoft.com"
echo "Fingerprint: chrome"
echo "Flow:        xtls-rprx-vision"
echo ""
echo -e "${GREEN}============================================${NC}"
echo -e "${YELLOW}【VLESS 链接】${NC} (复制到 v2rayN / v2rayNG)"
echo -e "${GREEN}============================================${NC}"
echo "${VLESS_LINK}"
echo ""
echo -e "${GREEN}============================================${NC}"
echo -e "${YELLOW}【订阅链接】${NC}"
echo -e "${GREEN}============================================${NC}"
echo ""
echo -e "${YELLOW}V2Ray 订阅 (v2rayN / v2rayNG / Shadowrocket):${NC}"
echo "http://${SERVER_IP}:8080/sub/${SUBSCRIBE_TOKEN}.txt"
echo ""
echo -e "${YELLOW}Clash 订阅 (Clash Meta / FlClash / Clash Verge):${NC}"
echo "http://${SERVER_IP}:8080/sub/${SUBSCRIBE_TOKEN}.yaml"
echo ""
echo -e "${GREEN}============================================${NC}"

# 保存信息到文件
cat > /root/xray-info.txt << EOF
============================================
Xray Reality 节点信息
============================================

【节点信息】
服务器IP:    ${SERVER_IP}
端口:        ${PORT}
UUID:        ${UUID}
Public Key:  ${PUBLIC_KEY}
Short ID:    ${SHORT_ID}
SNI:         www.microsoft.com
Fingerprint: chrome
Flow:        xtls-rprx-vision

【VLESS 链接】
${VLESS_LINK}

【V2Ray 订阅】
http://${SERVER_IP}:8080/sub/${SUBSCRIBE_TOKEN}.txt

【Clash 订阅】
http://${SERVER_IP}:8080/sub/${SUBSCRIBE_TOKEN}.yaml

============================================
EOF

echo -e "${GREEN}所有信息已保存到 /root/xray-info.txt${NC}"
echo ""