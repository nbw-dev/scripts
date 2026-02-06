### 通用的准备工作
1、VPS一台（建议安装 Ubuntu 22以上版本），看脚本的功能，内存需求不同 （[购买VPS](https://n28.it/evoxt)）

2、远程连接 vps 工具 finalshell （[点击下载](https://www.hostbuf.com/t/988.html)）

#### 一键开启BBR，适用于较新的Debian、Ubuntu
```
echo "net.core.default_qdisc=fq" >> /etc/sysctl.conf
echo "net.ipv4.tcp_congestion_control=bbr" >> /etc/sysctl.conf
sysctl -p
sysctl net.ipv4.tcp_available_congestion_control
lsmod | grep bbr
```
#### vless+reality 一键安装命令
```
apt update && wget -N --no-check-certificate https://github.com/nbw-dev/scripts/raw/refs/heads/main/v2ray-reality/install.sh && chmod +x install.sh && ./install.sh
```

#### vless+reality 卸载命令
```
wget -N --no-check-certificate https://github.com/nbw-dev/scripts/raw/refs/heads/main/v2ray-reality/uninstall.sh && chmod +x uninstall.sh && ./uninstall.sh
```

#### http+socks5 搭建命令
```
apt update && wget -N --no-check-certificate https://github.com/nbw-dev/scripts/raw/refs/heads/main/socks5-http/install.sh && chmod +x install.sh && ./install.sh
```

脚本开源 Github 链接 （欢迎 star）：https://github.com/nbw-dev/scripts

低价 eSIM 流量: https://n28.it/EpYJj