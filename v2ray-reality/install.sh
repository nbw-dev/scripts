#!/bin/bash

# ==========================================
# 你的个人定制安装脚本 (智能 SNI 版)
# 功能：极速安装 Xray (Reality) + 自动优选 SNI
# 适配：Debian / Ubuntu
# ==========================================

# 1. 基础配置
INSTALL_PATH="/usr/local/etc/xray"
BIN_PATH="/usr/local/bin/xray"
PORT=443
# 自动获取本机 IP
SERVER_IP=$(curl -s ifconfig.me)
UUID=$(cat /proc/sys/kernel/random/uuid)

# 颜色输出
red() { echo -e "\033[31m\033[01m$1\033[0m"; }
green() { echo -e "\033[32m\033[01m$1\033[0m"; }
yellow() { echo -e "\033[33m\033[01m$1\033[0m"; }

# 2. 系统检查与依赖安装
check_sys() {
    if [[ -f /etc/debian_version ]]; then
        # 必须安装 openssl 用于测速
        apt update && apt install -y wget curl unzip jq openssl
    else
        red "目前仅支持 Debian/Ubuntu 系统！"
        exit 1
    fi
}

# 3. 智能筛选最佳 SNI (核心新增功能)
get_best_sni() {
    green "正在进行 SNI 延迟筛选，请稍候..."
    
    # 待选列表 (你提供的列表)
    local domains="www.swift.com academy.nvidia.com www.cisco.com www.asus.com www.samsung.com www.amd.com www.umcg.nl www.fom-international.com www.u-can.co.jp github.io cname.vercel-dns.com vercel-dns.com www.python.org vuejs-jp.org vuejs.org zh-hk.vuejs.org react.dev www.java.com www.oracle.com www.mysql.com www.mongodb.com redis.io www.caltech.edu www.calstatela.edu www.suny.edu www.suffolk.edu one-piece.com gateway.icloud.com itunes.apple.com swdist.apple.com swcdn.apple.com updates.cdn-apple.com mensura.cdn-apple.com osxapps.itunes.apple.com aod.itunes.apple.com download-installer.cdn.mozilla.net addons.mozilla.org s0.awsstatic.com d1.awsstatic.com cdn-dynmedia-1.microsoft.com"

    local best_time=99999
    # 默认回退域名，防止全挂
    SELECTED_SNI="www.microsoft.com"

    for d in $domains; do
        # 记录开始时间戳 (毫秒)
        t1=$(date +%s%3N)
        
        # 尝试 TLS 握手，超时设为 1秒
        if timeout 1 openssl s_client -connect $d:443 -servername $d </dev/null &>/dev/null; then
            t2=$(date +%s%3N)
            time_taken=$((t2 - t1))
            
            # echo " - $d: ${time_taken}ms" # 调试用，不想看刷屏可注释掉
            
            # 比较并更新最佳结果
            if [[ $time_taken -lt $best_time ]]; then
                best_time=$time_taken
                SELECTED_SNI=$d
            fi
        # else
            # echo " - $d: 超时"
        fi
    done

    green "--> 筛选完成！最佳 SNI: ${SELECTED_SNI} (延迟: ${best_time}ms)"
}

# 4. 安装 Xray 核心
install_xray() {
    green "开始安装 Xray 核心..."
    mkdir -p $INSTALL_PATH
    
    # 下载最新版 Xray
    local XRAY_URL="https://github.com/XTLS/Xray-core/releases/latest/download/Xray-linux-64.zip"
    wget -N --no-check-certificate -O /tmp/xray.zip $XRAY_URL
    
    # 解压
    unzip -o /tmp/xray.zip -d /tmp/xray_bin
    mv /tmp/xray_bin/xray $BIN_PATH
    chmod +x $BIN_PATH
    rm -rf /tmp/xray.zip /tmp/xray_bin
}

# 5. 生成配置文件 (动态填入 SNI)
config_xray() {
    green "生成配置文件..."
    
    local KEYS=$($BIN_PATH x25519)
    local PK=$(echo "$KEYS" | grep "Private" | awk '{print $3}')
    local PUB=$(echo "$KEYS" | grep "Public" | awk '{print $3}')
    local SHORT_ID=$(openssl rand -hex 8)

    # 这里的 dest 和 serverNames 使用了变量 $SELECTED_SNI
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
          "dest": "${SELECTED_SNI}:443",
          "serverNames": ["${SELECTED_SNI}"],
          "privateKey": "$PK",
          "shortIds": ["$SHORT_ID"]
        }
      }
    }
  ],
  "outbounds": [{ "protocol": "freedom" }]
}
EOF

    REALITY_PUB=$PUB
}

# 6. 配置 Systemd 服务
install_service() {
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

# 7. 主程序
main() {
    check_sys
    install_xray
    get_best_sni  # 执行筛选
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
    yellow "SNI (ServerName): ${SELECTED_SNI}"
    echo "指纹 (Fingerprint): chrome"
    green "=================================="
}

main