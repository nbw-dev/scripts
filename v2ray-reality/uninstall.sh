#!/bin/bash
# 卸载 Xray Reality 节点

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}    卸载 Xray Reality${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""

# 1. 停止并卸载 Xray
echo -e "${GREEN}[1/5] 卸载 Xray...${NC}"
systemctl stop xray 2>/dev/null || true
systemctl disable xray 2>/dev/null || true
bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ remove

# 2. 删除 Xray 配置
echo -e "${GREEN}[2/5] 删除 Xray 配置...${NC}"
rm -rf /usr/local/etc/xray
rm -rf /var/log/xray

# 3. 删除订阅文件
echo -e "${GREEN}[3/5] 删除订阅文件...${NC}"
rm -rf /var/www/subscribe

# 4. 删除 Nginx 配置
echo -e "${GREEN}[4/5] 删除 Nginx 订阅配置...${NC}"
rm -f /etc/nginx/sites-available/subscribe
rm -f /etc/nginx/sites-enabled/subscribe
# 恢复默认配置
ln -sf /etc/nginx/sites-available/default /etc/nginx/sites-enabled/default 2>/dev/null || true
systemctl restart nginx 2>/dev/null || true

# 5. 删除信息文件
echo -e "${GREEN}[5/5] 删除信息文件...${NC}"
rm -f /root/xray-info.txt

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}    卸载完成！${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo "注意: Nginx 本身未卸载 (可能被其他服务使用)"
echo "如需完全卸载 Nginx: apt remove --purge nginx -y"
echo ""
