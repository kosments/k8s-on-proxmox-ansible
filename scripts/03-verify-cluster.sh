#!/bin/bash
# =============================================================================
# Cluster Verification Script - クラスター状態を確認
# =============================================================================
#
# 使用方法: ./03-verify-cluster.sh
#
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KUBECONFIG_FILE="$SCRIPT_DIR/../kubeconfig"

# カラー出力
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

log() { echo -e "${GREEN}[INFO]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; }

# kubeconfig確認
if [ ! -f "$KUBECONFIG_FILE" ]; then
    error "kubeconfig が見つかりません: $KUBECONFIG_FILE"
    echo "先に 02-setup-k3s.sh を実行してください"
    exit 1
fi

export KUBECONFIG=$KUBECONFIG_FILE

log "=== ノード状態 ==="
kubectl get nodes -o wide

log "=== システムPod状態 ==="
kubectl get pods -n kube-system

log "=== クラスター情報 ==="
kubectl cluster-info

log "=== サンプルアプリをデプロイしてテスト ==="
echo -n "サンプルアプリをデプロイしますか？ (y/n): "
read -r answer
if [ "$answer" = "y" ]; then
    log "Nginxをデプロイ中..."
    kubectl create deployment nginx-test --image=nginx:alpine 2>/dev/null || log "既にデプロイ済み"
    kubectl expose deployment nginx-test --port=80 --type=NodePort 2>/dev/null || log "既に公開済み"
    
    sleep 10
    
    log "=== デプロイ状態 ==="
    kubectl get deployment nginx-test
    kubectl get pods -l app=nginx-test
    kubectl get svc nginx-test
    
    NODE_PORT=$(kubectl get svc nginx-test -o jsonpath='{.spec.ports[0].nodePort}')
    log "アクセス方法: curl http://192.168.10.101:$NODE_PORT"
fi

log "=== 確認完了 ==="
echo ""
echo "クラスターは正常に動作しています！"
echo ""
echo "kubectl使用方法:"
echo "  export KUBECONFIG=$KUBECONFIG_FILE"
echo "  kubectl get nodes"

