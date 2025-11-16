#!/bin/bash
# xray-reality-full-setup.sh
# 一键安装 Xray + 配置 VLESS+REALITY + 生成客户端配置
# 适用于：天翼云 / 国内直播 / 地域伪装
# 运行方式：bash xray-reality-full-setup.sh

set -e

XRAY_BIN="/usr/local/bin/xray"
XRAY_CONFIG_DIR="/usr/local/etc/xray"
CONFIG_FILE="$XRAY_CONFIG_DIR/config.json"
SERVICE_FILE="/etc/systemd/system/xray.service"

echo "=========================================="
echo "🚀 Xray + VLESS-REALITY 一键部署脚本"
echo "作者：Qwen | 专为国内云服务器优化"
echo "=========================================="

# 获取公网 IP（用于客户端连接）
PUBLIC_IP=$(curl -s --max-time 5 https://api.ipify.org || \
           curl -s --max-time 5 https://ipv4.icanhazip.com || \
           echo "未能获取IP，请手动确认")

if [ "$PUBLIC_IP" = "未能获取IP，请手动确认" ]; then
    echo "⚠️ 无法自动获取公网 IP，请确保服务器有公网出口"
    read -p "请输入你的服务器公网 IP: " PUBLIC_IP
fi

echo "🌐 检测到服务器 IP: $PUBLIC_IP"

# ========================
# 第一步：安装 Xray（使用国内镜像）
# ========================
echo "⏳ 正在安装 Xray（使用 jsDelivr 镜像）..."

mkdir -p /tmp/xray-install
cd /tmp/xray-install

# 尝试从 jsDelivr 下载安装脚本（国内可访问）
if curl -fsSL -o install.sh https://cdn.jsdelivr.net/gh/XTLS/Xray-install@main/install-release.sh; then
    echo "✅ 成功从 jsDelivr 获取安装脚本"
elif curl -fsSL -o install.sh https://ghproxy.com/https://raw.githubusercontent.com/XTLS/Xray-install/main/install-release.sh; then
    echo "✅ 成功从 ghproxy 获取安装脚本"
else
    echo "❌ 无法下载安装脚本，请检查网络或手动安装 Xray"
    exit 1
fi

chmod +x install.sh
bash install.sh @ install

if ! command -v xray &> /dev/null; then
    echo "❌ Xray 安装失败，请手动上传二进制文件"
    exit 1
fi

echo "✅ Xray 安装成功，版本：$(xray version | head -n1)"

# ========================
# 第二步：生成 REALITY 参数
# ========================
echo "🔑 正在生成 REALITY 密钥和 UUID..."

UUID=$(cat /proc/sys/kernel/random/uuid)
KEY_PAIR=$(xray x25519 2>/dev/null)
PRIVATE_KEY=$(echo "$KEY_PAIR" | grep "Private key" | cut -d: -f2 | tr -d ' ')
PUBLIC_KEY=$(echo "$KEY_PAIR" | grep "Public key" | cut -d: -f2 | tr -d ' ')

# 选择伪装站点
echo ""
echo "请选择 REALITY 伪装目标（推荐百度）："
echo "1) www.baidu.com （推荐）"
echo "2) www.qq.com"
echo "3) www.163.com"
read -p "输入选项 [1-3]: " choice

case $choice in
  2) DEST="www.qq.com:443"; SERVER_NAME="www.qq.com" ;;
  3) DEST="www.163.com:443"; SERVER_NAME="www.163.com" ;;
  *) DEST="www.baidu.com:443"; SERVER_NAME="www.baidu.com" ;;
esac

# ========================
# 第三步：写入 config.json
# ========================
mkdir -p "$XRAY_CONFIG_DIR"

cat > "$CONFIG_FILE" <<EOF
{
  "log": {"loglevel": "warning"},
  "inbounds": [{
    "port": 443,
    "protocol": "vless",
    "settings": {
      "clients": [{"id": "$UUID", "flow": "xtls-rprx-vision"}],
      "decryption": "none"
    },
    "streamSettings": {
      "network": "tcp",
      "security": "reality",
      "realitySettings": {
        "show": false,
        "dest": "$DEST",
        "serverNames": ["$SERVER_NAME"],
        "privateKey": "$PRIVATE_KEY",
        "shortIds": [""]
      }
    }
  }],
  "outbounds": [{"protocol": "freedom"}]
}
EOF

# ========================
# 第四步：配置 systemd 服务
# ========================
cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=Xray Service (VLESS+REALITY)
After=network.target

[Service]
ExecStart=$XRAY_BIN -config $CONFIG_FILE
Restart=on-failure
User=root
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable xray
systemctl restart xray

sleep 2

if systemctl is-active --quiet xray; then
    echo "✅ Xray 服务已启动！"
else
    echo "⚠️ Xray 启动失败，检查配置："
    $XRAY_BIN -config $CONFIG_FILE -test
    exit 1
fi

# ========================
# 第五步：生成客户端配置
# ========================
echo ""
echo "=========================================="
echo "📱 客户端配置（请保存）"
echo "=========================================="

# 1. Sing-box JSON 配置（推荐）
SING_BOX_JSON=$(cat <<EOF
{
  "log": { "disabled": true },
  "inbounds": [{ "type": "mixed", "listen": "127.0.0.1", "listen_port": 2080 }],
  "outbounds": [{
    "type": "vless",
    "tag": "reality_out",
    "server": "$PUBLIC_IP",
    "server_port": 443,
    "uuid": "$UUID",
    "flow": "xtls-rprx-vision",
    "packet_encoding": "xudp",
    "tls": {
      "enabled": true,
      "server_name": "$SERVER_NAME",
      "reality": {
        "enabled": true,
        "public_key": "$PUBLIC_KEY",
        "short_id": ""
      }
    },
    "transport": { "type": "tcp" }
  }]
}
EOF
)

echo "📄 Sing-box 配置（保存为 config.json）："
echo "$SING_BOX_JSON" | jq . 2>/dev/null || echo "$SING_BOX_JSON"
echo ""

# 2. 通用分享链接（部分客户端支持）
SHARE_LINK="vless://${UUID}@${PUBLIC_IP}:443?encryption=none&security=reality&fp=chrome&pbk=${PUBLIC_KEY}&sni=${SERVER_NAME}&type=tcp&flow=xtls-rprx-vision#REALITY-CN"

echo "🔗 通用分享链接（可扫码或导入）："
echo "$SHARE_LINK"
echo ""

# 3. 手动参数列表
echo "📝 手动配置参数："
echo "协议: VLESS"
echo "地址: $PUBLIC_IP"
echo "端口: 443"
echo "UUID: $UUID"
echo "加密: none"
echo "传输: TCP"
echo "安全: reality"
echo "公钥: $PUBLIC_KEY"
echo "SNI: $SERVER_NAME"
echo "流控: xtls-rprx-vision"
echo ""

# 验证伪装是否生效
echo "🔍 验证伪装（在本地浏览器打开）：https://$PUBLIC_IP"
echo "应显示目标网站（如百度），否则检查防火墙是否开放 443 端口。"
echo "=========================================="