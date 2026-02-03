#!/bin/bash

# ==========================================
# 你的个人定制安装脚本
# 功能：极速安装 Xray (VLESS-Vision-Reality)
# 适配：Debian / Ubuntu
# ==========================================

# 1. 预设配置 (这里修改为你喜欢的默认值)
INSTALL_PATH="/usr/local/etc/xray"
BIN_PATH="/usr/local/bin/xray"
PORT=443
# 自动获取本机 IP 用于展示
SERVER_IP=$(curl -s ifconfig.me)
UUID=$(cat /proc/sys/kernel/random/uuid)

# 颜色输出
red() { echo -e "\033[31m\033[01m$1\033[0m"; }
green() { echo -e "\033[32m\033[01m$1\033[0m"; }

# 2. 系统检查与依赖安装
check_sys() {
    if [[ -f /etc/debian_version ]]; then
        apt update && apt install -y wget curl unzip jq openssl
    else
        red "目前仅支持 Debian/Ubuntu 系统！"
        exit 1
    fi
}

# 3. 安装 Xray 核心
install_xray() {
    green "开始安装 Xray 核心..."
    # 创建目录
    mkdir -p $INSTALL_PATH
    
    # 下载最新版 Xray (这里使用了官方源，你也可以换成自己的镜像源)
    local XRAY_URL="https://github.com/XTLS/Xray-core/releases/latest/download/Xray-linux-64.zip"
    wget -N --no-check-certificate -O /tmp/xray.zip $XRAY_URL
    
    # 解压并安装
    unzip -o /tmp/xray.zip -d /tmp/xray_bin
    mv /tmp/xray_bin/xray $BIN_PATH
    chmod +x $BIN_PATH
    
    # 清理
    rm -rf /tmp/xray.zip /tmp/xray_bin
}

# 4. 生成配置文件 (VLESS-Reality)
config_xray() {
    green "生成配置文件..."
    
    # 生成 Reality 密钥对
    local KEYS=$($BIN_PATH x25519)
    local PK=$(echo "$KEYS" | grep "Private" | awk '{print $3}')
    local PUB=$(echo "$KEYS" | grep "Public" | awk '{print $3}')
    local SHORT_ID=$(openssl rand -hex 8)

    # 写入配置 config.json
    cat <<EOF > $INSTALL_PATH/config.json
{
  "log": { "loglevel": "warning" },
  "inbounds": [
    {
      "port": $PORT,
      "protocol": "vless",
      "settings": {
        "clients": [
          { "id": "$UUID", "flow": "xtls-rprx-vision" }
        ],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "tcp",
        "security": "reality",
        "realitySettings": {
          "show": false,
          "dest": "www.microsoft.com:443",
          "serverNames": ["www.microsoft.com", "microsoft.com"],
          "privateKey": "$PK",
          "shortIds": ["$SHORT_ID"]
        }
      }
    }
  ],
  "outbounds": [{ "protocol": "freedom" }]
}
EOF

    # 保存公钥用于最后输出
    REALITY_PUB=$PUB
}

# 5. 配置 Systemd 服务并启动
install_service() {
    green "配置系统服务..."
    cat <<EOF > /etc/systemd/system/xray.service
[Unit]
Description=Xray Service
After=network.target nss-lookup.target

[Service]
User=root
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
NoNewPrivileges=true
ExecStart=$BIN_PATH run -c $INSTALL_PATH/config.json
Restart=on-failure
RestartPreventExitStatus=23

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable xray
    systemctl restart xray
}

# 6. 主逻辑
main() {
    check_sys
    install_xray
    config_xray
    install_service
    
    green "=================================="
    green "  安装完成！配置信息如下："
    green "=================================="
    echo "地址 (Address): ${SERVER_IP}"
    echo "端口 (Port)   : ${PORT}"
    echo "用户ID (UUID) : ${UUID}"
    echo "流控 (Flow)   : xtls-rprx-vision"
    echo "加密 (Security): reality"
    echo "公钥 (Public Key): ${REALITY_PUB}"
    echo "SNI (ServerName): www.microsoft.com"
    echo "指纹 (Fingerprint): chrome"
    green "=================================="
}

main