#!/bin/bash
# nbw-proxy-install.sh
# 一键部署 SOCKS5 和 HTTP 代理节点
# 系统要求：Ubuntu 20.04+, Debian 12+
# by 南波丸 @nbw_one

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

# 随机生成配置
S5_PORT=$(shuf -i 10000-65000 -n 1)
HTTP_PORT=$(shuf -i 10000-65000 -n 1)
while [ "$S5_PORT" == "$HTTP_PORT" ]; do HTTP_PORT=$(shuf -i 10000-65000 -n 1); done

USER=$(openssl rand -hex 4)
PASS=$(openssl rand -hex 6)

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}   南波丸 SOCKS5/HTTP 一键安装脚本${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""

echo -e "${GREEN}[1/4] 安装依赖与 Xray...${NC}"
apt update -y
apt install -y curl openssl qrencode
if ! [ -f "/usr/local/bin/xray" ]; then
    bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install
fi

echo -e "${GREEN}[2/4] 写入代理配置...${NC}"
# 注意：这里会覆盖之前的 config.json，如果需要共存请手动合并
# 为了简单起见，我们创建一个独立的配置文件给这个服务，或者直接覆盖
cat > /usr/local/etc/xray/config.json << EOF
{
  "log": {
    "loglevel": "warning"
  },
  "inbounds": [
    {
      "port": ${S5_PORT},
      "protocol": "socks",
      "settings": {
        "auth": "password",
        "accounts": [
          {
            "user": "${USER}",
            "pass": "${PASS}"
          }
        ],
        "udp": true
      }
    },
    {
      "port": ${HTTP_PORT},
      "protocol": "http",
      "settings": {
        "allowTransparent": true,
        "accounts": [
          {
            "user": "${USER}",
            "pass": "${PASS}"
          }
        ]
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

echo -e "${GREEN}[3/4] 重启 Xray 服务...${NC}"
systemctl restart xray
systemctl enable xray

# 获取服务器IP
SERVER_IP=$(curl -s4 ip.sb 2>/dev/null || curl -s6 ip.sb 2>/dev/null || curl -s ifconfig.me)

# 开放防火墙端口
if command -v ufw &> /dev/null; then
    ufw allow ${S5_PORT}/tcp
    ufw allow ${S5_PORT}/udp
    ufw allow ${HTTP_PORT}/tcp
fi

echo -e "${GREEN}[4/4] 部署完成！${NC}"
echo ""
echo -e "${GREEN}============================================${NC}"
echo -e "${YELLOW}【SOCKS5 代理信息】${NC}"
echo "地址: ${SERVER_IP}"
echo "端口: ${S5_PORT}"
echo "用户: ${USER}"
echo "密码: ${PASS}"
echo ""
echo -e "${YELLOW}Telegram 一键连接链接:${NC}"
TG_LINK="https://t.me/socks?server=${SERVER_IP}&port=${S5_PORT}&user=${USER}&pass=${PASS}"
echo "${TG_LINK}"
echo ""
echo -e "${YELLOW}扫码连接 Telegram 代理:${NC}"
qrencode -t ansiutf8 "${TG_LINK}"
echo ""
echo -e "${GREEN}============================================${NC}"
echo -e "${YELLOW}【HTTP 代理信息】${NC}"
echo "地址: ${SERVER_IP}"
echo "端口: ${HTTP_PORT}"
echo "用户: ${USER}"
echo "密码: ${PASS}"
echo ""
echo -e "${YELLOW}HTTP 代理格式:${NC}"
echo "http://${USER}:${PASS}@${SERVER_IP}:${HTTP_PORT}"
echo ""
echo -e "${GREEN}============================================${NC}"
echo -e "${YELLOW}电报 Telegram 交流群:${NC}"
echo "TG: @nbw_club"
echo ""
echo -e "${GREEN}============================================${NC}"

# 保存到文件
cat > /root/proxy-info.txt << EOF
============================================
SOCKS5/HTTP 代理信息
============================================
【SOCKS5】
IP: ${SERVER_IP}
Port: ${S5_PORT}
User: ${USER}
Pass: ${PASS}
TG Link: ${TG_LINK}

【HTTP】
IP: ${SERVER_IP}
Port: ${HTTP_PORT}
User: ${USER}
Pass: ${PASS}
Format: http://${USER}:${PASS}@${SERVER_IP}:${HTTP_PORT}

【交流群】
TG: @nbw_club
============================================
EOF

echo -e "${GREEN}信息已保存到 /root/proxy-info.txt${NC}"
