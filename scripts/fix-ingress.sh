#!/bin/bash

# Ingress設定を修正・適用するスクリプト
# 使用方法: ./fix-ingress.sh

set -e

export KUBECONFIG=${KUBECONFIG:-/root/k8s-on-proxmox-ansible/kubeconfig}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "=========================================="
echo "Ingress設定の修正・適用"
echo "=========================================="
echo ""

# 1. IngressClassの確認
echo "=== 1. IngressClass の確認 ==="
INGRESS_CLASS=$(kubectl get ingressclass -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "traefik")
echo "使用するIngressClass: $INGRESS_CLASS"
echo ""

# 2. dev-guide Ingressの適用
echo "=== 2. dev-guide Ingress の適用 ==="
kubectl apply -f "$REPO_ROOT/04-applications/dev-guide-hugo/k8s/ingress.yaml"
echo ""

# 3. local-llm Ingressの適用
echo "=== 3. local-llm Ingress の適用 ==="
kubectl apply -f "$REPO_ROOT/04-applications/local-llm/k8s/ingress.yaml"
echo ""

# 4. Ingressの状態確認
echo "=== 4. Ingress の状態確認 ==="
kubectl get ingress -A
echo ""

# 5. Traefik Serviceの確認
echo "=== 5. Traefik Service の確認 ==="
kubectl get svc -n kube-system | grep traefik
echo ""

echo "=========================================="
echo "適用完了"
echo "=========================================="
echo ""
echo "次のコマンドで詳細を確認できます:"
echo "  ./scripts/troubleshoot-ingress.sh"

