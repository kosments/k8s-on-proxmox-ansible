#!/bin/bash

# Proxmoxホストにスクリプトを転送するヘルパースクリプト
# 使用方法: ./transfer-to-proxmox.sh

set -e

PROXMOX_HOST="${PROXMOX_HOST:-192.168.10.108}"
PROXMOX_USER="${PROXMOX_USER:-root}"
# パスワードは環境変数から読み込む（git管理外）
PROXMOX_PASS="${PROXMOX_PASS:-}"
REMOTE_PATH="/root/k8s-on-proxmox-ansible"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "=========================================="
echo "Proxmoxホストへのファイル転送"
echo "=========================================="
echo ""

# SSH接続テスト
echo "SSH接続をテスト中..."
if sshpass -p "$PROXMOX_PASS" ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 "$PROXMOX_USER@$PROXMOX_HOST" "echo 'SSH OK'" 2>/dev/null; then
    echo "✓ SSH接続成功"
else
    echo "✗ SSH接続失敗"
    echo ""
    echo "ProxmoxホストでSSHサービスを起動してください:"
    echo "  systemctl start ssh"
    echo "  または"
    echo "  systemctl start sshd"
    echo ""
    echo "その後、再度このスクリプトを実行してください。"
    exit 1
fi

# リモートディレクトリの作成
echo "リモートディレクトリを作成中..."
sshpass -p "$PROXMOX_PASS" ssh -o StrictHostKeyChecking=no "$PROXMOX_USER@$PROXMOX_HOST" "
    mkdir -p $REMOTE_PATH/scripts
    mkdir -p $REMOTE_PATH
"

# ファイル転送
echo "ファイルを転送中..."

# recreate-master.sh
echo "  - recreate-master.sh"
sshpass -p "$PROXMOX_PASS" scp -o StrictHostKeyChecking=no \
    "$SCRIPT_DIR/recreate-master.sh" \
    "$PROXMOX_USER@$PROXMOX_HOST:$REMOTE_PATH/scripts/"

# check-vm-status.sh
echo "  - check-vm-status.sh"
sshpass -p "$PROXMOX_PASS" scp -o StrictHostKeyChecking=no \
    "$SCRIPT_DIR/check-vm-status.sh" \
    "$PROXMOX_USER@$PROXMOX_HOST:$REMOTE_PATH/scripts/"

# config.sh（存在する場合）
if [ -f "$SCRIPT_DIR/../config.sh" ]; then
    echo "  - config.sh"
    sshpass -p "$PROXMOX_PASS" scp -o StrictHostKeyChecking=no \
        "$SCRIPT_DIR/../config.sh" \
        "$PROXMOX_USER@$PROXMOX_HOST:$REMOTE_PATH/"
fi

# 実行権限を付与
echo "実行権限を付与中..."
sshpass -p "$PROXMOX_PASS" ssh -o StrictHostKeyChecking=no "$PROXMOX_USER@$PROXMOX_HOST" "
    chmod +x $REMOTE_PATH/scripts/recreate-master.sh
    chmod +x $REMOTE_PATH/scripts/check-vm-status.sh
"

echo ""
echo "=========================================="
echo "転送完了"
echo "=========================================="
echo ""
echo "Proxmoxホストで以下のコマンドを実行してください:"
echo ""
echo "  ssh root@192.168.10.108"
echo "  cd /root/k8s-on-proxmox-ansible/scripts"
echo "  ./check-vm-status.sh    # VM状態確認"
echo "  ./recreate-master.sh     # マスターノード再作成"
echo ""

