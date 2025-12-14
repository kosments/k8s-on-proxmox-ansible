#!/bin/bash
# =============================================================================
# k3s Setup Script - k3sクラスターをセットアップ
# =============================================================================
#
# 使用方法: ./02-setup-k3s.sh
#
# 前提条件:
#   - 01-clone-vms.sh でVMが作成済み
#   - VMにSSH接続可能
#
# 特徴:
#   - selected-ips.txt から自動的にIPアドレスを読み込み
#   - 手動指定も可能
#
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SELECTED_IPS_FILE="$SCRIPT_DIR/../selected-ips.txt"

# カラー出力
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

log() { echo -e "${GREEN}[INFO]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

# IPアドレスの設定
if [ -f "$SELECTED_IPS_FILE" ]; then
    log "selected-ips.txt からIPアドレスを読み込み中..."
    source "$SELECTED_IPS_FILE"
    MASTER_IP=${MASTER_IP:-"192.168.10.111"}
    WORKER_IPS=("${WORKER1_IP:-192.168.10.112}" "${WORKER2_IP:-192.168.10.113}")
    log "  Master: $MASTER_IP"
    log "  Workers: ${WORKER_IPS[*]}"
else
    warn "selected-ips.txt が見つかりません。デフォルトIPを使用します。"
    MASTER_IP="192.168.10.111"
    WORKER_IPS=("192.168.10.112" "192.168.10.113")
fi

SSH_USER="ubuntu"
SSH_KEY="/root/.ssh/id_rsa"
SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR"

# SSH実行ヘルパー
ssh_exec() {
    local host=$1
    shift
    ssh $SSH_OPTS -i $SSH_KEY ${SSH_USER}@${host} "$@"
}

# 接続確認
log "=== SSH接続確認 ==="
all_ips=("$MASTER_IP" "${WORKER_IPS[@]}")
for ip in "${all_ips[@]}"; do
    echo -n "$ip: "
    if ssh_exec $ip "echo OK" 2>/dev/null; then
        :
    else
        error "$ip にSSH接続できません"
    fi
done

# マスターノードにk3sインストール
log "=== マスターノード ($MASTER_IP) にk3sをインストール ==="

ssh_exec $MASTER_IP "
    # k3sが既にインストールされているか確認
    if command -v k3s &> /dev/null; then
        echo 'k3sは既にインストールされています'
    else
        echo 'k3sをインストール中...'
        curl -sfL https://get.k3s.io | sh -
    fi
    
    # k3sの起動確認
    sudo systemctl is-active k3s || sudo systemctl start k3s
    
    # ノード確認
    sudo k3s kubectl get nodes
"

# トークン取得
log "=== クラスター参加トークンを取得 ==="
K3S_TOKEN=$(ssh_exec $MASTER_IP "sudo cat /var/lib/rancher/k3s/server/node-token")
log "トークン取得完了"

# ワーカーノードをクラスターに参加
log "=== ワーカーノードをクラスターに参加 ==="
for WORKER_IP in "${WORKER_IPS[@]}"; do
    log "ワーカー $WORKER_IP を参加させています..."
    
    ssh_exec $WORKER_IP "
        # k3s-agentが既にインストールされているか確認
        if systemctl is-active k3s-agent &> /dev/null; then
            echo 'k3s-agentは既に実行中です'
        else
            echo 'k3s-agentをインストール中...'
            curl -sfL https://get.k3s.io | K3S_URL=https://${MASTER_IP}:6443 K3S_TOKEN=${K3S_TOKEN} sh -
        fi
    "
    
    log "ワーカー $WORKER_IP 参加完了"
done

# クラスター状態確認
log "=== クラスター状態確認（30秒待機）==="
sleep 30

ssh_exec $MASTER_IP "sudo k3s kubectl get nodes -o wide"

# kubeconfig取得
log "=== kubeconfigを取得 ==="
KUBECONFIG_FILE="$SCRIPT_DIR/../kubeconfig"

ssh_exec $MASTER_IP "sudo cat /etc/rancher/k3s/k3s.yaml" | \
    sed "s/127.0.0.1/${MASTER_IP}/g" > $KUBECONFIG_FILE

chmod 600 $KUBECONFIG_FILE
log "kubeconfigを保存しました: $KUBECONFIG_FILE"

log "=== k3sクラスターセットアップ完了 ==="
echo ""
echo "クラスター操作方法:"
echo "  export KUBECONFIG=$KUBECONFIG_FILE"
echo "  kubectl get nodes"
echo ""
echo "次のステップ: ./03-verify-cluster.sh を実行してクラスターを確認"
