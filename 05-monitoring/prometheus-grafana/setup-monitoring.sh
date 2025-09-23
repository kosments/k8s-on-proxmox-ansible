#!/bin/bash

# =============================================================================
# Prometheus + Grafana Monitoring Stack Setup Script
# =============================================================================
# 
# このスクリプトは、KubernetesクラスターにPrometheus + Grafana監視スタックをセットアップします
#
# 前提条件:
# - Kubernetesクラスターが構築済み
# - kubectl コマンドが利用可能
# - Helm がインストール済み（自動インストール対応）
#
# 使用方法:
#   ./setup-monitoring.sh [command]
#
# コマンド:
#   install   - 監視スタックをインストール（デフォルト）
#   status    - 監視スタックの状態を確認
#   logs      - ログを表示
#   uninstall - 監視スタックをアンインストール
#   help      - ヘルプを表示
#
# =============================================================================

set -euo pipefail

# 設定
NAMESPACE="ops"
PROMETHEUS_RELEASE="prometheus"
GRAFANA_RELEASE="grafana"
HELM_REPO_PROMETHEUS="https://prometheus-community.github.io/helm-charts"
HELM_REPO_GRAFANA="https://grafana.github.io/helm-charts"

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
    echo "Usage: $0 [command]"
    echo
    echo "Commands:"
    echo "  install     Install monitoring stack (default)"
    echo "  status      Check monitoring stack status"
    echo "  logs        Show logs"
    echo "  uninstall   Uninstall monitoring stack"
    echo "  help        Show this help"
    echo
    echo "Examples:"
    echo "  $0                    # Install monitoring stack"
    echo "  $0 status            # Check status"
    echo "  $0 logs              # Show logs"
    echo "  $0 uninstall         # Uninstall"
    echo
}

# 前提条件チェック
check_prerequisites() {
    log "Checking prerequisites..."
    
    # kubectl チェック
    if ! command -v kubectl &> /dev/null; then
        error "kubectl is not installed or not in PATH"
    fi
    
    # kubeconfig設定
    local kubeconfig_path="/root/k8s-on-proxmox-ansible/02-k8s-cluster/kubeconfig"
    if [[ -f "$kubeconfig_path" ]]; then
        export KUBECONFIG="$kubeconfig_path"
        log "Using kubeconfig: $kubeconfig_path"
    else
        warn "kubeconfig not found at $kubeconfig_path"
        # 相対パスも試す
        local relative_path="../02-k8s-cluster/kubeconfig"
        if [[ -f "$relative_path" ]]; then
            export KUBECONFIG="$relative_path"
            log "Using kubeconfig: $relative_path"
        else
            error "kubeconfig not found. Please run setup-kubeconfig.sh first."
        fi
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

# ネームスペース作成
create_namespace() {
    log "Creating namespace: $NAMESPACE"
    
    kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
    kubectl label namespace "$NAMESPACE" name="$NAMESPACE" --overwrite
    
    log "✓ Namespace created successfully"
}

# Helm リポジトリ追加
add_helm_repos() {
    log "Adding Helm repositories..."
    
    # Prometheus リポジトリ
    helm repo add prometheus-community "$HELM_REPO_PROMETHEUS"
    
    # Grafana リポジトリ
    helm repo add grafana "$HELM_REPO_GRAFANA"
    
    # リポジトリ更新
    helm repo update
    
    log "✓ Helm repositories added and updated"
}

# Prometheus インストール
install_prometheus() {
    log "Installing Prometheus..."
    
    helm install "$PROMETHEUS_RELEASE" prometheus-community/kube-prometheus-stack \
        --namespace "$NAMESPACE" \
        --set grafana.enabled=false \
        --set alertmanager.enabled=true \
        --set prometheus.prometheusSpec.serviceMonitorSelectorNilUsesHelmValues=false \
        --set prometheus.prometheusSpec.podMonitorSelectorNilUsesHelmValues=false \
        --set prometheus.prometheusSpec.ruleSelectorNilUsesHelmValues=false \
        --wait \
        --timeout=10m
    
    log "✓ Prometheus installed successfully"
}

# Grafana インストール
install_grafana() {
    log "Installing Grafana..."
    
    # Grafana のデフォルトパスワードを生成
    local grafana_password
    grafana_password=$(openssl rand -base64 32 | tr -d "=+/" | cut -c1-25)
    
    # パスワードをSecretに保存
    kubectl create secret generic grafana-admin \
        --from-literal=admin-password="$grafana_password" \
        --namespace="$NAMESPACE" \
        --dry-run=client -o yaml | kubectl apply -f -
    
    helm install "$GRAFANA_RELEASE" grafana/grafana \
        --namespace "$NAMESPACE" \
        --set admin.existingSecret=grafana-admin \
        --set admin.userKey=admin-username \
        --set admin.passwordKey=admin-password \
        --set service.type=NodePort \
        --set service.nodePort=30000 \
        --set persistence.enabled=true \
        --set persistence.size=10Gi \
        --wait \
        --timeout=10m
    
    log "✓ Grafana installed successfully"
    log "Grafana Admin Password: $grafana_password"
    log "Grafana URL: http://192.168.10.101:30000"
}

# 監視スタックインストール
install_monitoring() {
    log "Installing monitoring stack..."
    
    create_namespace
    add_helm_repos
    install_prometheus
    install_grafana
    
    log "✓ Monitoring stack installed successfully"
}

# インストール確認
verify_installation() {
    log "Verifying installation..."
    
    # Pod 状態確認
    log "Checking pod status..."
    kubectl get pods -n "$NAMESPACE"
    
    # サービス確認
    log "Checking services..."
    kubectl get svc -n "$NAMESPACE"
    
    # イングレス確認
    log "Checking ingress..."
    kubectl get ingress -n "$NAMESPACE" 2>/dev/null || echo "No ingress found"
    
    log "✓ Installation verification completed"
}

# ステータス確認
check_status() {
    log "Checking monitoring stack status..."
    
    echo -e "${BLUE}=== Pod Status ===${NC}"
    kubectl get pods -n "$NAMESPACE" -o wide
    
    echo -e "\n${BLUE}=== Service Status ===${NC}"
    kubectl get svc -n "$NAMESPACE"
    
    echo -e "\n${BLUE}=== Grafana Access ===${NC}"
    local grafana_nodeport
    grafana_nodeport=$(kubectl get svc -n "$NAMESPACE" "$GRAFANA_RELEASE" -o jsonpath='{.spec.ports[0].nodePort}' 2>/dev/null || echo "N/A")
    if [ "$grafana_nodeport" != "N/A" ]; then
        echo "Grafana URL: http://192.168.10.101:$grafana_nodeport"
        echo "Username: admin"
        echo "Password: $(kubectl get secret grafana-admin -n "$NAMESPACE" -o jsonpath='{.data.admin-password}' | base64 -d 2>/dev/null || echo 'Check secret')"
    else
        echo "Grafana service not found"
    fi
    
    echo -e "\n${BLUE}=== Prometheus Access ===${NC}"
    local prometheus_nodeport
    prometheus_nodeport=$(kubectl get svc -n "$NAMESPACE" "$PROMETHEUS_RELEASE-kube-prometheus-prometheus" -o jsonpath='{.spec.ports[0].nodePort}' 2>/dev/null || echo "N/A")
    if [ "$prometheus_nodeport" != "N/A" ]; then
        echo "Prometheus URL: http://192.168.10.101:$prometheus_nodeport"
    else
        echo "Prometheus service not found"
    fi
    
    echo -e "\n${BLUE}=== Recent Events ===${NC}"
    kubectl get events -n "$NAMESPACE" --sort-by=.metadata.creationTimestamp | tail -10
}

# ログ表示
show_logs() {
    log "Showing monitoring stack logs..."
    
    echo -e "${BLUE}=== Prometheus Logs ===${NC}"
    local prometheus_pod
    prometheus_pod=$(kubectl get pods -n "$NAMESPACE" -l app.kubernetes.io/name=prometheus -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
    if [ -n "$prometheus_pod" ]; then
        kubectl logs -n "$NAMESPACE" "$prometheus_pod" --tail=20
    else
        warn "Prometheus pod not found"
    fi
    
    echo -e "\n${BLUE}=== Grafana Logs ===${NC}"
    local grafana_pod
    grafana_pod=$(kubectl get pods -n "$NAMESPACE" -l app.kubernetes.io/name=grafana -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
    if [ -n "$grafana_pod" ]; then
        kubectl logs -n "$NAMESPACE" "$grafana_pod" --tail=20
    else
        warn "Grafana pod not found"
    fi
}

# アンインストール
uninstall() {
    log "Uninstalling monitoring stack..."
    
    helm uninstall "$GRAFANA_RELEASE" -n "$NAMESPACE" || true
    helm uninstall "$PROMETHEUS_RELEASE" -n "$NAMESPACE" || true
    
    # ネームスペース削除（オプション）
    read -p "Do you want to delete the namespace '$NAMESPACE'? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        kubectl delete namespace "$NAMESPACE" || true
        log "✓ Namespace deleted"
    fi
    
    log "✓ Monitoring stack uninstalled"
}

# メイン処理
main() {
    local command="${1:-install}"
    
    echo -e "${BLUE}"
    echo "================================================"
    echo "  Prometheus + Grafana Monitoring Stack"
    echo "  Namespace: $NAMESPACE"
    echo "================================================"
    echo -e "${NC}"
    
    case $command in
        "install")
            check_prerequisites
            install_monitoring
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
