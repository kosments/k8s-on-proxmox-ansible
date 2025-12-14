#!/bin/bash
# =============================================================================
# VM Clone Script - テンプレートからVMをクローン
# =============================================================================
#
# 使用方法: ./01-clone-vms.sh
#
# 前提条件:
#   - Proxmoxホスト上で実行
#   - テンプレートVM（9000）が存在
#
# 特徴:
#   - IP競合を自動検出し、空いているIPを動的に選択
#   - ARPテーブルとPingで二重チェック
#
# =============================================================================

set -e

# 設定
TEMPLATE_ID=9000
VM_IDS=(101 102 103)
VM_NAMES=("k8s-master" "k8s-worker1" "k8s-worker2")
GATEWAY="192.168.10.1"
SSH_USER="ubuntu"
SSH_PASSWORD="ubuntu"
VM_MEMORY=4096
VM_CORES=2
VM_DISK_SIZE="50G"

# IP範囲設定（この範囲から空いているIPを探す）
IP_PREFIX="192.168.10"
IP_RANGE_START=111
IP_RANGE_END=130

# カラー出力
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

log() { echo -e "${GREEN}[INFO]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

# =============================================================================
# IP競合チェック機能
# =============================================================================

# 指定IPが使用中かどうかチェック
check_ip_in_use() {
    local ip=$1
    
    # ARPテーブルをチェック
    if ip neigh show | grep -q "$ip "; then
        return 0  # 使用中
    fi
    
    # Pingでチェック（タイムアウト1秒）
    if ping -c 1 -W 1 $ip >/dev/null 2>&1; then
        return 0  # 使用中
    fi
    
    return 1  # 未使用
}

# 空いているIPアドレスを探す
find_available_ip() {
    local start=$1
    local end=$2
    
    for i in $(seq $start $end); do
        local ip="${IP_PREFIX}.${i}"
        if ! check_ip_in_use $ip; then
            echo $ip
            return 0
        fi
    done
    
    return 1  # 空きIPが見つからない
}

# 必要な数の空きIPを取得
get_available_ips() {
    local count=$1
    local ips=()
    local current=$IP_RANGE_START
    
    log "=== IP競合チェック開始 ==="
    log "範囲: ${IP_PREFIX}.${IP_RANGE_START} - ${IP_PREFIX}.${IP_RANGE_END}"
    
    # ARPキャッシュを更新（ネットワークスキャン）
    log "ネットワークをスキャン中..."
    for i in $(seq $IP_RANGE_START $IP_RANGE_END); do
        ping -c 1 -W 1 ${IP_PREFIX}.${i} >/dev/null 2>&1 &
    done
    wait
    sleep 2
    
    # 使用中のIPを表示
    log "使用中のIP（ARPテーブル）:"
    ip neigh show | grep "$IP_PREFIX" | while read line; do
        echo "  $line"
    done
    
    # 空きIPを探す
    log "空きIPを検索中..."
    for i in $(seq 1 $count); do
        while [ $current -le $IP_RANGE_END ]; do
            local ip="${IP_PREFIX}.${current}"
            if ! check_ip_in_use $ip; then
                ips+=($ip)
                log "  VM $i: $ip (空き確認済み)"
                ((current++))
                break
            else
                warn "  $ip は使用中 - スキップ"
            fi
            ((current++))
        done
        
        if [ ${#ips[@]} -lt $i ]; then
            error "空きIPが不足しています。範囲を広げてください。"
        fi
    done
    
    echo "${ips[@]}"
}

# =============================================================================
# メイン処理
# =============================================================================

# テンプレート確認
log "テンプレート(VM $TEMPLATE_ID)を確認中..."
qm status $TEMPLATE_ID >/dev/null 2>&1 || error "テンプレート $TEMPLATE_ID が見つかりません"
log "テンプレート確認OK"

# 空きIPを取得
VM_COUNT=${#VM_IDS[@]}
AVAILABLE_IPS=($(get_available_ips $VM_COUNT))

if [ ${#AVAILABLE_IPS[@]} -lt $VM_COUNT ]; then
    error "必要な空きIPが見つかりませんでした"
fi

log "=== 使用するIPアドレス ==="
for i in "${!VM_IDS[@]}"; do
    log "  ${VM_NAMES[$i]}: ${AVAILABLE_IPS[$i]}"
done

# 確認プロンプト
echo ""
read -p "これらのIPアドレスでVMを作成しますか？ (y/n): " confirm
if [ "$confirm" != "y" ]; then
    log "キャンセルしました"
    exit 0
fi

# VM作成
for i in "${!VM_IDS[@]}"; do
    VM_ID=${VM_IDS[$i]}
    VM_NAME=${VM_NAMES[$i]}
    VM_IP=${AVAILABLE_IPS[$i]}
    
    log "=== VM $VM_ID ($VM_NAME) を作成中 ==="
    log "IPアドレス: $VM_IP"
    
    # 既存VMの確認
    if qm status $VM_ID >/dev/null 2>&1; then
        log "VM $VM_ID は既に存在します。スキップします。"
        continue
    fi
    
    # クローン作成
    log "テンプレートからクローン中..."
    qm clone $TEMPLATE_ID $VM_ID --name $VM_NAME --full
    
    # VM設定
    log "VM設定を適用中..."
    qm set $VM_ID \
        --memory $VM_MEMORY \
        --cores $VM_CORES \
        --ipconfig0 ip=${VM_IP}/24,gw=$GATEWAY \
        --ciuser $SSH_USER \
        --cipassword $SSH_PASSWORD \
        --nameserver 8.8.8.8
    
    # ディスクリサイズ
    log "ディスクを ${VM_DISK_SIZE} にリサイズ中..."
    qm resize $VM_ID scsi0 $VM_DISK_SIZE
    
    # VM起動
    log "VM起動中..."
    qm start $VM_ID
    
    log "VM $VM_ID ($VM_NAME) 作成完了"
done

# 設定ファイルに選択されたIPを保存
CONFIG_FILE="$(dirname $0)/../selected-ips.txt"
echo "# 自動選択されたIPアドレス ($(date))" > $CONFIG_FILE
echo "MASTER_IP=${AVAILABLE_IPS[0]}" >> $CONFIG_FILE
echo "WORKER1_IP=${AVAILABLE_IPS[1]}" >> $CONFIG_FILE
echo "WORKER2_IP=${AVAILABLE_IPS[2]}" >> $CONFIG_FILE
log "選択されたIPを $CONFIG_FILE に保存しました"

# 起動待機
log "VMの起動を待機中（60秒）..."
sleep 60

# 接続確認
log "=== 接続確認 ==="
for i in "${!VM_IDS[@]}"; do
    VM_IP=${AVAILABLE_IPS[$i]}
    VM_NAME=${VM_NAMES[$i]}
    
    echo -n "$VM_NAME ($VM_IP): "
    if ping -c 1 -W 3 $VM_IP >/dev/null 2>&1; then
        echo -n "Ping OK, "
    else
        echo "Ping FAILED"
        continue
    fi
    
    if timeout 5 bash -c "echo | nc $VM_IP 22" 2>/dev/null | grep -q SSH; then
        echo "SSH OK"
    else
        echo "SSH waiting..."
    fi
done

log "=== VM作成完了 ==="
echo ""
echo "次のステップ:"
echo "  1. selected-ips.txt の内容を確認"
echo "  2. ./02-setup-k3s.sh を実行してKubernetesをセットアップ"
echo ""
echo "選択されたIPアドレス:"
cat $CONFIG_FILE | grep -v "^#"
