#!/bin/bash

# Ingressトラブルシューティングスクリプト
# 使用方法: ./troubleshoot-ingress.sh

set -e

export KUBECONFIG=${KUBECONFIG:-/root/k8s-on-proxmox-ansible/kubeconfig}

echo "=========================================="
echo "Ingress トラブルシューティング"
echo "=========================================="
echo ""

# 1. IngressClassの確認
echo "=== 1. IngressClass の確認 ==="
kubectl get ingressclass
echo ""

# 2. Traefik Podの状態
echo "=== 2. Traefik Pod の状態 ==="
kubectl get pods -n kube-system | grep traefik || echo "Traefik Podが見つかりません"
echo ""

# 3. Traefik Serviceの状態
echo "=== 3. Traefik Service の状態 ==="
kubectl get svc -n kube-system | grep traefik || echo "Traefik Serviceが見つかりません"
echo ""

# 4. すべてのIngressリソース
echo "=== 4. すべてのIngressリソース ==="
kubectl get ingress -A -o wide
echo ""

# 5. Ingressの詳細（各namespace）
echo "=== 5. Ingress の詳細 ==="
for ns in dev-guide local-llm; do
    echo "--- Namespace: $ns ---"
    kubectl get ingress -n $ns -o yaml 2>/dev/null || echo "Namespace $ns にIngressがありません"
    echo ""
done

# 6. Serviceの状態
echo "=== 6. Service の状態 ==="
for ns in dev-guide local-llm; do
    echo "--- Namespace: $ns ---"
    kubectl get svc -n $ns 2>/dev/null || echo "Namespace $ns が見つかりません"
    echo ""
done

# 7. Podの状態
echo "=== 7. Pod の状態 ==="
for ns in dev-guide local-llm; do
    echo "--- Namespace: $ns ---"
    kubectl get pods -n $ns 2>/dev/null || echo "Namespace $ns が見つかりません"
    echo ""
done

# 8. Endpointsの確認
echo "=== 8. Endpoints の確認 ==="
for ns in dev-guide local-llm; do
    echo "--- Namespace: $ns ---"
    kubectl get endpoints -n $ns 2>/dev/null || echo "Namespace $ns が見つかりません"
    echo ""
done

# 9. Traefikのログ（最新10行）
echo "=== 9. Traefik のログ（最新10行） ==="
TRAEFIK_POD=$(kubectl get pods -n kube-system -l app.kubernetes.io/name=traefik -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
if [ -n "$TRAEFIK_POD" ]; then
    kubectl logs -n kube-system $TRAEFIK_POD --tail=10 2>/dev/null || echo "ログの取得に失敗しました"
else
    echo "Traefik Podが見つかりません"
fi
echo ""

echo "=========================================="
echo "トラブルシューティング完了"
echo "=========================================="

