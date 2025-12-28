#!/bin/bash

# =============================================================================
# VM起動後のセットアップスクリプト
# =============================================================================
# このスクリプトは、VM起動後にSSHサービスとパスワード認証を確実に有効化します
# ProxmoxホストからVMにSSH接続して実行、またはVM内で直接実行
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/../config.sh"

if [ -f "$CONFIG_FILE" ]; then
    source "$CONFIG_FILE"
else
    echo "❌ 設定ファイルが見つかりません: $CONFIG_FILE"
    exit 1
fi

# ログ関数
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

# VM内で実行するセットアップコマンド
setup_vm_ssh() {
    local vm_ip=$1
    
    log "VM $vm_ip のSSH設定を確認中..."
    
    # SSH接続を試みる（複数の方法を試す）
    local ssh_success=false
    
    # 方法1: SSH鍵認証
    if ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 -o PasswordAuthentication=no ${SSH_USER}@${vm_ip} "echo OK" 2>/dev/null; then
        log "✅ SSH鍵認証で接続成功"
        ssh_success=true
    # 方法2: パスワード認証（ubuntu/ubuntu）
    elif sshpass -p 'ubuntu' ssh -o StrictHostKeyChecking=no -o PreferredAuthentications=password ${SSH_USER}@${vm_ip} "echo OK" 2>/dev/null; then
        log "✅ パスワード認証で接続成功"
        ssh_success=true
    fi
    
    if [ "$ssh_success" = false ]; then
        log "⚠️ VM $vm_ip にSSH接続できません。VMコンソールから手動で設定してください。"
        return 1
    fi
    
    # VM内でセットアップスクリプトを実行
    log "VM $vm_ip 内でSSH設定を実行中..."
    
    ssh -o StrictHostKeyChecking=no ${SSH_USER}@${vm_ip} "sudo bash -s" << 'EOF'
# SSHサービスを確実に起動
systemctl enable ssh || systemctl enable sshd
systemctl start ssh || systemctl start sshd

# パスワード認証を有効化
sed -i 's/#PasswordAuthentication no/PasswordAuthentication yes/' /etc/ssh/sshd_config
sed -i 's/PasswordAuthentication no/PasswordAuthentication yes/' /etc/ssh/sshd_config

# rootログインを許可（必要に応じて）
sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin yes/' /etc/ssh/sshd_config || true
sed -i 's/PermitRootLogin prohibit-password/PermitRootLogin yes/' /etc/ssh/sshd_config || true
sed -i 's/PermitRootLogin no/PermitRootLogin yes/' /etc/ssh/sshd_config || true

# SSHサービスを再起動
systemctl restart ssh || systemctl restart sshd || true

# 確認
systemctl status ssh --no-pager | head -5 || systemctl status sshd --no-pager | head -5

echo "✅ SSH設定が完了しました"
EOF
    
    log "✅ VM $vm_ip のセットアップ完了"
}

# メイン処理
main() {
    log "=== VM起動後セットアップスクリプト ==="
    
    for i in "${!VM_IPS[@]}"; do
        local vm_ip="${VM_IPS[$i]}"
        local vm_id="${VM_IDS[$i]}"
        local vm_name="${VM_NAMES[$i]}"
        
        log "処理中: VM $vm_id ($vm_name) - $vm_ip"
        setup_vm_ssh "$vm_ip" || log "⚠️ VM $vm_id のセットアップに失敗しました"
        echo ""
    done
    
    log "=== セットアップ完了 ==="
}

main "$@"

