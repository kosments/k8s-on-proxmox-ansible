#!/bin/bash

# =============================================================================
# New Relic Kubernetes Integration Setup Script
# =============================================================================
# 
# このスクリプトは、KubernetesクラスターにNew Relic監視をセットアップします
#
# 前提条件:
# - Kubernetesクラスターが構築済み
# - kubectl コマンドが利用可能
# - New Relic ライセンスキーが設定済み
#
# 使用方法:
#   ./setup-newrelic.sh [license-key]
#
# 例:
#   ./setup-newrelic.sh "your-license-key-here"
#   NEW_RELIC_LICENSE_KEY="your-key" ./setup-newrelic.sh
#
# =============================================================================

set -euo pipefail

# 設定
NAMESPACE="ops"
CLUSTER_NAME="k8s-proxmox-cluster"
HELM_REPO="https://helm-charts.newrelic.com"
CHART_NAME="nri-bundle"

# カラー出力
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# ログ関数
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

warn() {
    echo -e "${YELLOW}[WARN] $1${NC}"
}

error() {
    echo -e "${RED}[ERROR] $1${NC}"
    exit 1
}

# ヘルプ表示
show_help() {
    echo "Usage: $0 [license-key]"
    echo
    echo "Arguments:"
    echo "  license-key    New Relic ライセンスキー"
    echo
    echo "Environment Variables:"
    echo "  NEW_RELIC_LICENSE_KEY    New Relic ライセンスキー"
    echo
    echo "Examples:"
    echo "  $0 \"your-license-key-here\""
    echo "  NEW_RELIC_LICENSE_KEY=\"your-key\" $0"
    echo
}

# 前提条件チェック
check_prerequisites() {
    log "Checking prerequisites..."
    
    # kubectl チェック
    if ! command -v kubectl &> /dev/null; then
        error "kubectl is not installed or not in PATH"
    fi
    
    # クラスター接続チェック
    if ! kubectl cluster-info &> /dev/null; then
        error "Cannot connect to Kubernetes cluster. Please check kubeconfig."
    fi
    
    # Helm チェック
    if ! command -v helm &> /dev/null; then
        warn "Helm is not installed. Installing Helm..."
        install_helm
    fi
    
    log "✓ Prerequisites check completed"
}

# Helm インストール
install_helm() {
    log "Installing Helm..."
    
    curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
    
    if ! command -v helm &> /dev/null; then
        error "Failed to install Helm"
    fi
    
    log "✓ Helm installed successfully"
}

# ライセンスキー取得
get_license_key() {
    local license_key="${1:-}"
    
    if [ -n "$license_key" ]; then
        echo "$license_key"
    elif [ -n "${NEW_RELIC_LICENSE_KEY:-}" ]; then
        echo "$NEW_RELIC_LICENSE_KEY"
    else
        error "New Relic license key is required. Please provide it as an argument or set NEW_RELIC_LICENSE_KEY environment variable."
    fi
}

# ネームスペース作成
create_namespace() {
    log "Creating namespace: $NAMESPACE"
    
    kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
    kubectl label namespace "$NAMESPACE" name="$NAMESPACE" --overwrite
    
    log "✓ Namespace created successfully"
}

# Helm リポジトリ追加
add_helm_repo() {
    log "Adding Helm repository: $HELM_REPO"
    
    helm repo add newrelic "$HELM_REPO"
    helm repo update
    
    log "✓ Helm repository added and updated"
}

# New Relic インストール
install_newrelic() {
    local license_key="$1"
    
    log "Installing New Relic Kubernetes Integration..."
    
    helm install newrelic-bundle newrelic/nri-bundle \
        --namespace "$NAMESPACE" \
        --set global.licenseKey="$license_key" \
        --set global.cluster="$CLUSTER_NAME" \
        --set infrastructure.enabled=true \
        --set prometheus.enabled=true \
        --set webhook.enabled=true \
        --set ksm.enabled=true \
        --set kubeEvents.enabled=true \
        --set logging.enabled=true \
        --set kubeStateMetrics.enabled=true \
        --set kubeStateMetrics.extraArgs[0]="--metric-labels-allowlist=nodes=[*],pods=[*]" \
        --wait \
        --timeout=10m
    
    log "✓ New Relic installed successfully"
}

# インストール確認
verify_installation() {
    log "Verifying installation..."
    
    # Pod 状態確認
    log "Checking pod status..."
    kubectl get pods -n "$NAMESPACE" -l app.kubernetes.io/name=newrelic-infrastructure
    
    # サービス確認
    log "Checking services..."
    kubectl get svc -n "$NAMESPACE" | grep newrelic
    
    # 設定確認
    log "Checking configuration..."
    kubectl get configmap -n "$NAMESPACE" | grep newrelic
    
    log "✓ Installation verification completed"
}

# ログ表示
show_logs() {
    log "Showing New Relic agent logs..."
    
    local pod_name
    pod_name=$(kubectl get pods -n "$NAMESPACE" -l app.kubernetes.io/name=newrelic-infrastructure -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
    
    if [ -n "$pod_name" ]; then
        kubectl logs -n "$NAMESPACE" "$pod_name" --tail=50
    else
        warn "New Relic agent pod not found"
    fi
}

# ステータス確認
check_status() {
    log "Checking New Relic status..."
    
    echo -e "${BLUE}=== Pod Status ===${NC}"
    kubectl get pods -n "$NAMESPACE" -l app.kubernetes.io/name=newrelic-infrastructure -o wide
    
    echo -e "\n${BLUE}=== Service Status ===${NC}"
    kubectl get svc -n "$NAMESPACE" | grep newrelic
    
    echo -e "\n${BLUE}=== ConfigMap Status ===${NC}"
    kubectl get configmap -n "$NAMESPACE" | grep newrelic
    
    echo -e "\n${BLUE}=== Recent Events ===${NC}"
    kubectl get events -n "$NAMESPACE" --sort-by=.metadata.creationTimestamp | tail -10
}

# アンインストール
uninstall() {
    log "Uninstalling New Relic..."
    
    helm uninstall newrelic-bundle -n "$NAMESPACE" || true
    
    log "✓ New Relic uninstalled"
}

# メイン処理
main() {
    local command="${1:-install}"
    local license_key="${2:-}"
    
    echo -e "${BLUE}"
    echo "================================================"
    echo "  New Relic Kubernetes Integration Setup"
    echo "  Cluster: $CLUSTER_NAME"
    echo "  Namespace: $NAMESPACE"
    echo "================================================"
    echo -e "${NC}"
    
    case $command in
        "install")
            check_prerequisites
            license_key=$(get_license_key "$license_key")
            create_namespace
            add_helm_repo
            install_newrelic "$license_key"
            verify_installation
            check_status
            ;;
        "status")
            check_status
            ;;
        "logs")
            show_logs
            ;;
        "uninstall")
            uninstall
            ;;
        "help"|"--help"|"-h")
            show_help
            ;;
        *)
            warn "Unknown command: $command"
            show_help
            exit 1
            ;;
    esac
    
    log "Operation completed successfully!"
}

# スクリプト実行
main "$@"
