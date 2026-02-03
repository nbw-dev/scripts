#!/bin/bash
# xray-reality-install.sh
# 一键部署 Xray Reality 节点

set -e

# 颜色
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

# 生成随机端口
PORT=$(shuf -i 10000-65000 -n 1)
# 生成UUID
UUID=$(cat /proc/sys/kernel/random/uuid)

echo -e "${GREEN}[1/5] 安装 Xray...${NC}"
bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install

echo -e "${GREEN}[2/5] 生成 Reality 密钥对...${NC}"
KEYS=$(/usr/local/bin/xray x25519)
PRIVATE_KEY=$(echo "$KEYS" | grep "Private" | awk '{print $3}')
PUBLIC_KEY=$(echo "$KEYS" | grep "Public" | awk '{print $3}')
SHORT_ID=$(openssl rand -hex 8)

echo -e "${GREEN}[3/5] 写入配置...${NC}"
cat > /usr/local/etc/xray/config.json << EOF
{
  "log": {"loglevel": "warning"},
  "inbounds": [{
    "port": ${PORT},
    "protocol": "vless",
    "settings": {
      "clients": [{"id": "${UUID}", "flow": "xtls-rprx-vision"}],
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
  }],
  "outbounds": [{"protocol": "freedom"}]
}
EOF

echo -e "${GREEN}[4/5] 启动服务...${NC}"
systemctl restart xray
systemctl enable xray

# 获取服务器IP
SERVER_IP=$(curl -s4 ip.sb || curl -s6 ip.sb)

echo -e "${GREEN}[5/5] 生成连接信息...${NC}"

# VLESS链接
VLESS_LINK="vless://${UUID}@${SERVER_IP}:${PORT}?encryption=none&flow=xtls-rprx-vision&security=reality&sni=www.microsoft.com&fp=chrome&pbk=${PUBLIC_KEY}&sid=${SHORT_ID}&type=tcp#Reality-${SERVER_IP}"

# 输出信息
echo ""
echo "============================================"
echo -e "${GREEN}部署完成！${NC}"
echo "============================================"
echo "服务器IP: ${SERVER_IP}"
echo "端口: ${PORT}"
echo "UUID: ${UUID}"
echo "Public Key: ${PUBLIC_KEY}"
echo "Short ID: ${SHORT_ID}"
echo "SNI: www.microsoft.com"
echo "============================================"
echo ""
echo -e "${GREEN}VLESS 链接 (直接导入客户端):${NC}"
echo "${VLESS_LINK}"
echo ""

# 生成订阅文件
SUBSCRIBE_DIR="/var/www/subscribe"
mkdir -p ${SUBSCRIBE_DIR}
SUBSCRIBE_TOKEN=$(openssl rand -hex 16)
echo "${VLESS_LINK}" | base64 -w 0 > "${SUBSCRIBE_DIR}/${SUBSCRIBE_TOKEN}"

# 安装nginx提供订阅服务
if ! command -v nginx &> /dev/null; then
    apt update && apt install -y nginx
fi

cat > /etc/nginx/sites-available/subscribe << EOF
server {
    listen 8080;
    location /sub/ {
        alias ${SUBSCRIBE_DIR}/;
        default_type text/plain;
    }
}
EOF
ln -sf /etc/nginx/sites-available/subscribe /etc/nginx/sites-enabled/
systemctl restart nginx

echo -e "${GREEN}订阅链接:${NC}"
echo "http://${SERVER_IP}:8080/sub/${SUBSCRIBE_TOKEN}"
echo ""
echo "============================================"

# 保存信息到文件
cat > /root/xray-info.txt << EOF
VLESS链接: ${VLESS_LINK}
订阅链接: http://${SERVER_IP}:8080/sub/${SUBSCRIBE_TOKEN}
EOF
echo -e "${GREEN}信息已保存到 /root/xray-info.txt${NC}"