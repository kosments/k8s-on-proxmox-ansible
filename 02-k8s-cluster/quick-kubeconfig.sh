#!/bin/bash

# =============================================================================
# Quick kubeconfig Setup Script for k3s
# =============================================================================
# マスターノードからkubeconfigを素早く取得して設定します
# =============================================================================

set -e

MASTER_IP="${1:-192.168.10.111}"
SSH_USER="${SSH_USER:-ubuntu}"
KUBECONFIG_PATH="${HOME}/.kube/config-k3s"

echo "🔧 kubeconfigを取得中..."
echo "マスターノード: $MASTER_IP"

# kubeconfigを取得
if ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 ${SSH_USER}@${MASTER_IP} "sudo cat /etc/rancher/k3s/k3s.yaml" 2>/dev/null | \
   sed "s/127.0.0.1/${MASTER_IP}/g" > /tmp/kubeconfig-k3s; then
    echo "✅ kubeconfigを取得しました"
else
    echo "❌ kubeconfigの取得に失敗しました"
    echo "以下を確認してください:"
    echo "  1. VM ($MASTER_IP) が起動しているか"
    echo "  2. SSH接続が可能か（ssh ${SSH_USER}@${MASTER_IP}）"
    echo "  3. k3sがインストールされているか"
    exit 1
fi

# .kubeディレクトリを作成
mkdir -p "$(dirname "$KUBECONFIG_PATH")"

# 既存のkubeconfigがある場合はバックアップ
if [[ -f "$KUBECONFIG_PATH" ]]; then
    mv "$KUBECONFIG_PATH" "${KUBECONFIG_PATH}.backup.$(date +%Y%m%d_%H%M%S)"
    echo "✅ 既存のkubeconfigをバックアップしました"
fi

# kubeconfigをコピー
cp /tmp/kubeconfig-k3s "$KUBECONFIG_PATH"
chmod 600 "$KUBECONFIG_PATH"
rm /tmp/kubeconfig-k3s

echo "✅ kubeconfigを保存しました: $KUBECONFIG_PATH"
echo ""
echo "使用方法:"
echo "  export KUBECONFIG=$KUBECONFIG_PATH"
echo "  kubectl get nodes"
echo ""
echo "または、~/.zshrcや~/.bashrcに以下を追加:"
echo "  export KUBECONFIG=\$HOME/.kube/config-k3s"

