#!/bin/bash

# =============================================================================
# Proxmoxホスト再起動時に実行するセットアップスクリプト
# =============================================================================
# このスクリプトは、Proxmoxホストの再起動後にVMの設定を確認・修正します
# systemdサービスまたはcronで自動実行することを想定
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

LOG_FILE="/var/log/proxmox-post-boot-setup.log"

# ログ関数
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# VMを起動
start_vm_if_stopped() {
    local vm_id=$1
    local vm_name=$2
    
    if qm status $vm_id &>/dev/null; then
        local status=$(qm status $vm_id | awk '{print $2}')
        if [ "$status" != "running" ]; then
            log "VM $vm_id ($vm_name) が停止中です。起動します..."
            qm start $vm_id
            sleep 10  # VM起動を待つ
        else
            log "VM $vm_id ($vm_name) は既に起動中です"
        fi
    else
        log "⚠️ VM $vm_id ($vm_name) が見つかりません"
    fi
}

# VMのSSH設定を確認・修正
check_and_fix_vm_ssh() {
    local vm_ip=$1
    local vm_id=$2
    local vm_name=$3
    
    log "VM $vm_id ($vm_name) - $vm_ip のSSH設定を確認中..."
    
    # VMが起動しているか確認
    if ! qm status $vm_id &>/dev/null; then
        log "⚠️ VM $vm_id が見つかりません"
        return 1
    fi
    
    local status=$(qm status $vm_id | awk '{print $2}')
    if [ "$status" != "running" ]; then
        log "VM $vm_id が起動していません（状態: $status）"
        return 1
    fi
    
    # SSH接続を試みる（最大5回、30秒間隔）
    local max_attempts=5
    local attempt=1
    local ssh_success=false
    
    while [ $attempt -le $max_attempts ]; do
        # ポート22が開いているか確認
        if timeout 3 nc -zv $vm_ip 22 2>/dev/null; then
            log "ポート22が開いています"
            
            # SSH接続を試みる
            if timeout 5 sshpass -p 'ubuntu' ssh -o StrictHostKeyChecking=no -o PreferredAuthentications=password -o ConnectTimeout=3 ubuntu@${vm_ip} "echo OK" 2>/dev/null; then
                log "✅ SSH接続成功（パスワード認証）"
                ssh_success=true
                break
            elif timeout 5 ssh -o StrictHostKeyChecking=no -o ConnectTimeout=3 -o PasswordAuthentication=no ubuntu@${vm_ip} "echo OK" 2>/dev/null; then
                log "✅ SSH接続成功（SSH鍵認証）"
                ssh_success=true
                break
            else
                log "SSH接続失敗（試行 $attempt/$max_attempts）"
            fi
        else
            log "ポート22が閉じています（試行 $attempt/$max_attempts）"
        fi
        
        attempt=$((attempt + 1))
        sleep 30
    done
    
    if [ "$ssh_success" = false ]; then
        log "⚠️ VM $vm_id ($vm_name) にSSH接続できません"
        log "  → Proxmoxコンソールから手動で確認してください"
        return 1
    fi
    
    # VM内でSSH設定を確認・修正
    log "VM $vm_id 内でSSH設定を確認中..."
    
    sshpass -p 'ubuntu' ssh -o StrictHostKeyChecking=no ubuntu@${vm_ip} "sudo bash -s" << 'EOF' || \
    ssh -o StrictHostKeyChecking=no ubuntu@${vm_ip} "sudo bash -s" << 'EOF' || return 1
# SSHサービスが起動しているか確認
if ! systemctl is-active --quiet ssh && ! systemctl is-active --quiet sshd; then
    echo "SSHサービスが起動していません。起動します..."
    systemctl enable ssh || systemctl enable sshd
    systemctl start ssh || systemctl start sshd
fi

# パスワード認証が有効か確認
if ! grep -q "^PasswordAuthentication yes" /etc/ssh/sshd_config; then
    echo "パスワード認証を有効化します..."
    sed -i 's/#PasswordAuthentication no/PasswordAuthentication yes/' /etc/ssh/sshd_config
    sed -i 's/PasswordAuthentication no/PasswordAuthentication yes/' /etc/ssh/sshd_config
    systemctl restart ssh || systemctl restart sshd || true
fi

echo "✅ SSH設定は正常です"
EOF
    
    log "✅ VM $vm_id ($vm_name) の確認完了"
}

# メイン処理
main() {
    log "=== Proxmoxホスト再起動後セットアップ開始 ==="
    
    # VMを起動
    log "Phase 1: VMの起動確認..."
    for i in "${!VM_IDS[@]}"; do
        start_vm_if_stopped "${VM_IDS[$i]}" "${VM_NAMES[$i]}"
    done
    
    # VM起動を待つ
    log "VM起動を待機中（60秒）..."
    sleep 60
    
    # SSH設定を確認・修正
    log "Phase 2: SSH設定の確認・修正..."
    for i in "${!VM_IPS[@]}"; do
        check_and_fix_vm_ssh "${VM_IPS[$i]}" "${VM_IDS[$i]}" "${VM_NAMES[$i]}"
        echo ""
    done
    
    log "=== セットアップ完了 ==="
    log "ログファイル: $LOG_FILE"
}

main "$@"

