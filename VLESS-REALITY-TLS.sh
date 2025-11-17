#!/bin/bash
# deploy-reality.sh
# 作者：Syuan | 适用于天翼云等国内环境
# 前提：/root/xray 已存在（通过 WinSCP 上传）

set -e

echo "=========================================="
echo "🚀 开始部署 VLESS + REALITY 服务"
echo "前提：/root/xray 已上传并完整"
echo "=========================================="

# =============== 第一步：安装 xray 到系统目录 ===============
echo "🔧 步骤 1: 安装 Xray 到 /usr/local/bin/"

# 删除可能存在的错误目录
if [ -d "/usr/local/bin/xray" ]; then
    rm -rf /usr/local/bin/xray
fi

# 移动并赋权
mv /root/xray /usr/local/bin/
chmod +x /usr/local/bin/xray

# 添加 PATH（仅当前会话）
export PATH="/usr/local/bin:$PATH"

# 验证
if ! xray version &>/dev/null; then
    echo "❌ Xray 无法运行，请检查 /root/xray 是否完整！"
    exit 1
fi

echo "✅ Xray 安装成功：$(xray version | head -n1)"

# =============== 第二步：获取公网 IP ===============
echo "🌐 步骤 2: 获取服务器公网 IP..."

PUBLIC_IP=$(curl -s --max-time 5 https://api.ipify.org || \
           curl -s --max-time 5 https://ipv4.icanhazip.com || \
           echo "150.223.194.15")  # 默认回退

if [[ "$PUBLIC_IP" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "✅ 公网 IP: $PUBLIC_IP"
else
    read -p "⚠️ 无法自动获取 IP，请手动输入: " PUBLIC_IP
fi

# =============== 第三步：生成 REALITY 参数 ===============
echo "🔑 步骤 3: 生成 REALITY 密钥和 UUID..."

KEY_OUT=$(xray x25519 2>/dev/null)
PRIVATE_KEY=$(echo "$KEY_OUT" | grep "Private key" | cut -d: -f2 | tr -d ' ')
PUBLIC_KEY=$(echo "$KEY_OUT" | grep "Public key"  | cut -d: -f2 | tr -d ' ')
UUID=$(cat /proc/sys/kernel/random/uuid)

if [ -z "$PRIVATE_KEY" ] || [ -z "$PUBLIC_KEY" ]; then
    echo "❌ 密钥生成失败！"
    exit 1
fi

echo "✅ UUID: $UUID"
echo "✅ Private Key (服务端用): ${PRIVATE_KEY:0:8}..."
echo "✅ Public Key (客户端用): ${PUBLIC_KEY:0:8}..."

# =============== 第四步：创建配置文件 ===============
echo "📄 步骤 4: 创建 config.json..."

mkdir -p /usr/local/etc/xray

cat > /usr/local/etc/xray/config.json <<EOF
{
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
        "dest": "www.baidu.com:443",
        "serverNames": ["www.baidu.com"],
        "privateKey": "$PRIVATE_KEY",
        "shortIds": ["", "62"]
      }
    }
  }],
  "outbounds": [{"protocol": "freedom"}]
}
EOF

# 测试配置
if ! xray run -config /usr/local/etc/xray/config.json -test &>/dev/null; then
    echo "❌ 配置文件有误！请检查 privateKey 格式。"
    exit 1
fi

echo "✅ 配置文件验证通过！"

# =============== 第五步：创建 systemd 服务 ===============
echo "⚙️ 步骤 5: 创建并启动 systemd 服务..."

cat > /etc/systemd/system/xray.service <<EOF
[Unit]
Description=Xray Service (VLESS+REALITY)
After=network.target

[Service]
ExecStart=/usr/local/bin/xray run -config /usr/local/etc/xray/config.json
Restart=on-failure
RestartSec=3
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
    echo "⚠️ 服务启动失败，查看日志：journalctl -u xray -n 20"
    exit 1
fi

# =============== 第六步：开放防火墙 ===============
echo "🛡️ 步骤 6: 开放系统防火墙 (ufw)..."

if command -v ufw &>/dev/null; then
    ufw allow 443/tcp &>/dev/null || true
    ufw reload &>/dev/null || true
    echo "✅ ufw 已放行 443/tcp"
else
    echo "ℹ️ ufw 未安装，跳过（请确保安全组已开 443）"
fi

# =============== 第七步：生成 vless:// 链接 ===============
echo "🔗 步骤 7: 生成客户端链接..."

# URL 编码 Public Key
PUB_ENCODED=$(echo "$PUBLIC_KEY" | sed 's/=/%3D/g; s/+/%2B/g; s/\//%2F/g')

VLESS_LINK="vless://${UUID}@${PUBLIC_IP}:443?security=reality&encryption=none&fp=randomized&pbk=${PUB_ENCODED}&sni=www.baidu.com&type=tcp&flow=xtls-rprx-vision#REALITY-Douyin"

echo ""
echo "=========================================="
echo "🎉 部署成功！请保存以下信息"
echo "=========================================="
echo "📱 VLESS-REALITY 链接（可导入 Shadowrocket / Sing-box）："
echo "$VLESS_LINK"
echo ""
echo "📝 手动参数："
echo "地址: $PUBLIC_IP"
echo "端口: 443"
echo "UUID: $UUID"
echo "Public Key: $PUBLIC_KEY"
echo "SNI: www.baidu.com"
echo ""
echo "❗ 重要：请登录天翼云控制台，确保【安全组】已放行 TCP 443 端口！"
echo "=========================================="
