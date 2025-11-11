#!/bin/bash

# ==================================================
# Dante SOCKS5 代理 - 非交互式一键安装脚本 (Ubuntu/Debian)
# 支持云服务器（阿里云/AWS/腾讯云等）
# 使用方式: curl -fsSL <url> | sudo bash
# ==================================================

set -e

# ----------------------------
# 🔧 配置区（按需修改）
# ----------------------------
SOCKS_USER="Dcodkwe54h2"
SOCKS_PASS="djoJ52wsex6"
SOCKS_PORT=14569

# ----------------------------
# 🚀 脚本开始
# ----------------------------
echo "🚀 开始安装 Dante SOCKS5 代理..."
echo "用户名: $SOCKS_USER"
echo "密码:   $SOCKS_PASS"
echo "端口:   $SOCKS_PORT"
echo "----------------------------------------"

# 检测系统
if ! command -v apt &>/dev/null; then
    echo "❌ 仅支持 Debian/Ubuntu 系统"
    exit 1
fi

# 自动检测外网网卡（用于 external）
MAIN_IFACE=$(ip route show default 2>/dev/null | awk '{print $5; exit}')
if [ -z "$MAIN_IFACE" ]; then
    # 尝试常见网卡名
    for iface in eth0 ens3 enp0s3 ens160; do
        if ip link show "$iface" &>/dev/null; then
            MAIN_IFACE="$iface"
            break
        fi
    done
fi

if [ -z "$MAIN_IFACE" ]; then
    echo "❌ 无法确定外网网卡，请手动检查 'ip route' 输出"
    exit 1
fi

echo "🌐 检测到外网网卡: $MAIN_IFACE"

# 更新并安装 dante-server
apt update -y
DEBIAN_FRONTEND=noninteractive apt install -y dante-server

# 创建专用用户（无登录权限）
if ! id "$SOCKS_USER" &>/dev/null; then
    useradd -r -s /usr/sbin/nologin "$SOCKS_USER"
fi
echo "$SOCKS_USER:$SOCKS_PASS" | chpasswd

# 生成正确配置文件
cat > /etc/danted.conf << EOF
logoutput: syslog
user.privileged: root
user.notprivileged: nobody

# 监听所有 IPv4 地址（客户端连接入口）
internal: 0.0.0.0 port = $SOCKS_PORT

# 出口网卡（必须指定！）
external: $MAIN_IFACE

# socks-rules determine what is proxied through the external interface.
socksmethod: username

# client-rules determine who can connect to the internal interface.
clientmethod: none

client pass {
    from: 0.0.0.0/0 to: 0.0.0.0/0
}

socks pass {
    from: 0.0.0.0/0 to: 0.0.0.0/0
}
EOF

# 启动服务
systemctl enable --now danted

# 防火墙放行（UFW）
if command -v ufw &>/dev/null && ufw status | grep -q "Status: active"; then
    ufw allow $SOCKS_PORT/tcp comment 'Dante SOCKS5'
    ufw reload &>/dev/null || true
fi

# 获取本机内网 IP
LOCAL_IP=$(ip -4 addr show "$MAIN_IFACE" 2>/dev/null | grep -oP 'inet \K[\d.]+')
if [ -z "$LOCAL_IP" ]; then
    LOCAL_IP="your_server_ip"
fi

# 获取公网出口 IP
PUBLIC_IP=$(timeout 5 curl -s https://api.ipify.org 2>/dev/null || echo "获取失败")
#检测danted服务的状态 active 则为启动成功
systemctl status danted.service
# 最终提示
echo ""
echo "✅ Dante SOCKS5 代理已成功启动！"
echo "----------------------------------------"
echo "连接地址: socks5://$SOCKS_USER:$SOCKS_PASS@$LOCAL_IP:$SOCKS_PORT"
echo "出口 IP : $PUBLIC_IP"
echo ""
echo "💡 注意事项:"
echo "- 若从外部连接，请确保安全组/防火墙已开放 $SOCKS_PORT 端口"
echo "- 建议修改默认密码以提高安全性"
echo "- 日志查看: journalctl -u danted -f"
echo "----------------------------------------"
