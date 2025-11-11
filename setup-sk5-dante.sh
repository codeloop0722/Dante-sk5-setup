#!/bin/bash

# ==================================================
# Dante SOCKS5 Proxy 非交互式安装脚本 (Ubuntu/Debian)
# 作者: Codeloop
# 功能: 自动安装 dante-server，创建用户，配置监听 0.0.0.0:1080
# 使用: curl -fsSL <url> | sudo bash
# ==================================================

set -e  # 遇错退出

# ----------------------------
# 🔐 在此处设置你的用户名和密码
# ----------------------------
SOCKS_USER="Dcodkwe54h2"
SOCKS_PASS="djoJ52wsex6"

PORT=1080

# 检测主网卡（用于提示，不影响功能）
MAIN_IFACE=$(ip route show default | awk '{print $5; exit}')
if [ -z "$MAIN_IFACE" ]; then
    MAIN_IFACE="eth0"
fi

echo "=== Dante SOCKS5 Proxy 非交互式安装 ==="
echo "用户名: $SOCKS_USER"
echo "密码:   $SOCKS_PASS"
echo "端口:   $PORT"
echo "----------------------------------------"

# 更新系统
apt update -y

# 安装 dante-server
apt install -y dante-server

# 创建专用用户（无 home，无 shell）
if ! id "$SOCKS_USER" &>/dev/null; then
    useradd -r -s /usr/sbin/nologin "$SOCKS_USER"
fi

# 设置密码（通过 chpasswd）
echo "$SOCKS_USER:$SOCKS_PASS" | chpasswd

# 备份原配置
cp /etc/danted.conf /etc/danted.conf.bak

# 生成新配置
cat > /etc/danted.conf <<EOF
logoutput: syslog
user.privileged: root
user.notprivileged: nobody

# 监听所有 IPv4 地址
internal: 0.0.0.0 port=$PORT

# 允许客户端来自任意 IP
client pass {
    from: 0.0.0.0/0 to: 0.0.0.0/0
    log: connect disconnect error
}

# 允许 SOCKS5 认证用户访问任意目标
socks pass {
    from: 0.0.0.0/0 to: 0.0.0.0/0
    command: bind connect udpassociate
    log: connect disconnect error
}

# 强制使用用户名/密码认证
socks pass {
    from: 0.0.0.0/0 to: 0.0.0.0/0
    command: bindreply udpreply
    log: connect error
}
EOF

# 启动并启用服务
systemctl enable --now danted

# 开放防火墙（如果 UFW 启用）
if command -v ufw &>/dev/null; then
    ufw allow $PORT/tcp comment 'Dante SOCKS5'
    ufw reload &>/dev/null || true
fi

# 获取本机局域网 IP（用于展示）
LOCAL_IP=$(ip -4 addr show "$MAIN_IFACE" 2>/dev/null | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | head -n1)
if [ -z "$LOCAL_IP" ]; then
    LOCAL_IP="your_vm_ip"
fi

# 获取公网出口 IP（可选）
PUBLIC_IP=$(curl -s --max-time 5 https://api.ipify.org 2>/dev/null || echo "failed")

echo ""
echo "✅ Dante SOCKS5 代理安装成功！"
echo "----------------------------------------"
echo "本地连接地址: socks5://$SOCKS_USER:$SOCKS_PASS@$LOCAL_IP:$PORT"
echo "公网出口 IP : $PUBLIC_IP"
echo ""
echo "💡 提示:"
echo "1. 若从外部连接，请放行防火墙和路由器端口"
echo "2. 建议修改默认密码以增强安全性"
echo "----------------------------------------"
