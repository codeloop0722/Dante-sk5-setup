#!/bin/bash

# Dante SOCKS5 Proxy Setup Script for Ubuntu 20.04+
# Based on: https://www.digitalocean.com/community/tutorials/how-to-set-up-dante-proxy-on-ubuntu-20-04

set -e  # Exit on any error

echo "=== Dante SOCKS5 Proxy Setup ==="

# === 用户输入 ===
read -p "请输入 SOCKS 用户名 (例如: proxyuser): " SOCKS_USER
read -s -p "请输入该用户的密码: " SOCKS_PASS
echo
read -p "请输入允许连接的客户端 IP (例如: 192.168.1.100 或 0.0.0.0 表示不限制): " CLIENT_IP
CLIENT_IP=${CLIENT_IP:-0.0.0.0}

# 自动检测主网络接口（通常为 eth0 或 ens3 等）
MAIN_IFACE=$(ip route | grep default | awk '{print $5}' | head -n1)
if [ -z "$MAIN_IFACE" ]; then
    MAIN_IFACE="eth0"
fi
echo "检测到主网络接口: $MAIN_IFACE"

# === 1. 更新系统并安装 Dante ===
echo "正在更新软件包列表..."
sudo apt update

echo "正在安装 dante-server..."
sudo apt install -y dante-server

# === 2. 创建专用 SOCKS 用户（无登录 shell）===
echo "正在创建专用用户: $SOCKS_USER"
sudo useradd -r -s /bin/false "$SOCKS_USER"
echo "$SOCKS_USER:$SOCKS_PASS" | sudo chpasswd

# === 3. 备份并生成新的配置文件 ===
echo "正在配置 /etc/danted.conf..."
sudo rm -f /etc/danted.conf

cat <<EOF | sudo tee /etc/danted.conf
logoutput: syslog
user.privileged: root
user.unprivileged: nobody

# 监听所有 IPv4 地址，端口 1080
internal: 0.0.0.0 port=1080

# 使用主网络接口进行外部连接
external: $MAIN_IFACE

# 认证方式：用户名密码（SOCKS5）
socksmethod: username

# 客户端认证：无需认证（但通过规则限制 IP）
clientmethod: none

# 允许指定 IP 连接
client pass {
    from: $CLIENT_IP/32 to: 0.0.0.0/0
}

# 允许所有目标地址通过代理
socks pass {
    from: 0.0.0.0/0 to: 0.0.0.0/0
}
EOF

# 如果用户输入的是 0.0.0.0，则放宽 CIDR
if [ "$CLIENT_IP" = "0.0.0.0" ]; then
    sed -i 's|from: 0.0.0.0/32|from: 0.0.0.0/0|' /etc/danted.conf
fi

# === 4. 配置防火墙（如果启用 ufw）===
if command -v ufw >/dev/null 2>&1; then
    echo "检测到 ufw，正在开放端口 1080..."
    sudo ufw allow 1080/tcp comment "Dante SOCKS5 Proxy"
fi

# === 5. 启动并启用服务 ===
echo "正在重启 danted 服务..."
sudo systemctl restart danted
sudo systemctl enable danted

# === 6. 检查状态 ===
echo "检查服务状态..."
if systemctl is-active --quiet danted; then
    echo "✅ Dante SOCKS5 代理已成功启动！"
    echo
    echo "使用方法（本地测试）："
    echo "curl -v -x socks5://$SOCKS_USER:$SOCKS_PASS@$(hostname -I | awk '{print $1}'):1080 http://httpbin.org/ip"
    echo
    echo "你的代理地址：socks5://$SOCKS_USER:$SOCKS_PASS@$(curl -s ifconfig.me 2>/dev/null || hostname -I | awk '{print $1}'):1080"
else
    echo "❌ Dante 服务启动失败，请检查日志："
    sudo journalctl -u danted --no-pager -n 20
    exit 1
fi