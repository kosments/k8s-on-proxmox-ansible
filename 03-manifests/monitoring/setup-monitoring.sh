#!/bin/bash
# =============================================================================
# Kubernetes Monitoring Stack Setup Script
# =============================================================================
#
# このスクリプトは、Kubernetesクラスターに包括的な監視スタックを構築します。
#
# 【インストールされるコンポーネント】
# - Prometheus: メトリクス収集・保存
# - Grafana: ダッシュボード・可視化
# - AlertManager: アラート管理
# - Node Exporter: ホストメトリクス
# - kube-state-metrics: Kubernetesリソース状態
# - Prometheus Operator: Prometheus管理の自動化
#
# 【前提条件】
# - Kubernetesクラスターが動作している
# - kubectl が設定済み
# - Helm がインストール済み
#
# 【使用方法】
# ./setup-monitoring.sh
#
# =============================================================================

set -euo pipefail

# Configuration
NAMESPACE="monitoring"
RELEASE_NAME="kube-prometheus-stack"
HELM_REPO="prometheus-community"
CHART_NAME="kube-prometheus-stack"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING: $1${NC}"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $1${NC}"
    exit 1
}

success() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

# Check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check kubectl
    if ! command -v kubectl &> /dev/null; then
        error "kubectl not found. Please install kubectl first."
    fi
    
    # Check cluster connection
    if ! kubectl cluster-info &> /dev/null; then
        error "Cannot connect to Kubernetes cluster. Please check your kubeconfig."
    fi
    
    # Check Helm
    if ! command -v helm &> /dev/null; then
        log "Helm not found. Installing Helm..."
        curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
    fi
    
    success "Prerequisites check completed"
}

# Install Helm repository
setup_helm_repo() {
    log "Setting up Helm repository..."
    
    helm repo add $HELM_REPO https://prometheus-community.github.io/helm-charts
    helm repo update
    
    success "Helm repository configured"
}

# Create namespace
create_namespace() {
    log "Creating monitoring namespace..."
    
    kubectl create namespace $NAMESPACE --dry-run=client -o yaml | kubectl apply -f -
    
    success "Namespace $NAMESPACE ready"
}

# Install monitoring stack
install_monitoring_stack() {
    log "Installing kube-prometheus-stack..."
    
    # Create values file for customization
    cat > /tmp/monitoring-values.yaml << 'EOF'
# Grafana Configuration
grafana:
  adminPassword: "admin123"  # Change this in production!
  service:
    type: NodePort
    nodePort: 30300
  persistence:
    enabled: true
    size: 10Gi
  dashboardProviders:
    dashboardproviders.yaml:
      apiVersion: 1
      providers:
      - name: 'default'
        orgId: 1
        folder: ''
        type: file
        disableDeletion: false
        editable: true
        options:
          path: /var/lib/grafana/dashboards/default

# Prometheus Configuration
prometheus:
  prometheusSpec:
    retention: 30d
    storageSpec:
      volumeClaimTemplate:
        spec:
          accessModes: ["ReadWriteOnce"]
          resources:
            requests:
              storage: 50Gi
    resources:
      requests:
        memory: 400Mi
        cpu: 100m
      limits:
        memory: 2Gi
        cpu: 1000m

# AlertManager Configuration
alertmanager:
  alertmanagerSpec:
    storage:
      volumeClaimTemplate:
        spec:
          accessModes: ["ReadWriteOnce"]
          resources:
            requests:
              storage: 10Gi

# Node Exporter Configuration
nodeExporter:
  enabled: true

# kube-state-metrics Configuration
kubeStateMetrics:
  enabled: true

# Disable components we don't need for basic setup
kubeApiServer:
  enabled: true
kubelet:
  enabled: true
kubeControllerManager:
  enabled: false  # Usually not accessible in managed clusters
kubeScheduler:
  enabled: false  # Usually not accessible in managed clusters
kubeProxy:
  enabled: true
kubeEtcd:
  enabled: false  # Usually not accessible in managed clusters
EOF

    # Install the stack
    helm upgrade --install $RELEASE_NAME $HELM_REPO/$CHART_NAME \
        --namespace $NAMESPACE \
        --values /tmp/monitoring-values.yaml \
        --wait \
        --timeout 10m
    
    success "Monitoring stack installed successfully"
}

# Setup port forwarding for easy access
setup_access() {
    log "Setting up access to monitoring services..."
    
    # Wait for pods to be ready
    kubectl wait --for=condition=ready pod -l "app.kubernetes.io/name=grafana" -n $NAMESPACE --timeout=300s
    kubectl wait --for=condition=ready pod -l "app.kubernetes.io/name=prometheus" -n $NAMESPACE --timeout=300s
    
    # Get service information
    echo ""
    echo "=== Monitoring Services Access ==="
    echo ""
    
    # Grafana
    GRAFANA_PORT=$(kubectl get svc -n $NAMESPACE | grep grafana | grep NodePort | awk '{print $5}' | cut -d: -f2 | cut -d/ -f1)
    echo "🎨 Grafana Dashboard:"
    echo "   URL: http://$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}'):${GRAFANA_PORT:-30300}"
    echo "   Username: admin"
    echo "   Password: admin123"
    echo ""
    
    # Prometheus
    echo "📊 Prometheus:"
    echo "   Port Forward: kubectl port-forward -n $NAMESPACE svc/kube-prometheus-stack-prometheus 9090:9090"
    echo "   Then access: http://localhost:9090"
    echo ""
    
    # AlertManager
    echo "🚨 AlertManager:"
    echo "   Port Forward: kubectl port-forward -n $NAMESPACE svc/kube-prometheus-stack-alertmanager 9093:9093"
    echo "   Then access: http://localhost:9093"
    echo ""
    
    success "Access information displayed above"
}

# Install sample dashboards
install_sample_dashboards() {
    log "Installing sample dashboards..."
    
    # Create a sample custom dashboard
    cat > /tmp/sample-dashboard.json << 'EOF'
{
  "dashboard": {
    "id": null,
    "title": "Kubernetes Cluster Overview",
    "tags": ["kubernetes"],
    "timezone": "browser",
    "panels": [
      {
        "id": 1,
        "title": "Cluster CPU Usage",
        "type": "stat",
        "targets": [
          {
            "expr": "100 - (avg by (instance) (irate(node_cpu_seconds_total{mode=\"idle\"}[5m])) * 100)",
            "legendFormat": "CPU Usage %"
          }
        ],
        "gridPos": {"h": 8, "w": 12, "x": 0, "y": 0}
      },
      {
        "id": 2,
        "title": "Cluster Memory Usage",
        "type": "stat",
        "targets": [
          {
            "expr": "(1 - (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes)) * 100",
            "legendFormat": "Memory Usage %"
          }
        ],
        "gridPos": {"h": 8, "w": 12, "x": 12, "y": 0}
      }
    ],
    "time": {"from": "now-1h", "to": "now"},
    "refresh": "30s"
  }
}
EOF
    
    success "Sample dashboards prepared"
}

# Main execution
main() {
    echo "=== Kubernetes Monitoring Stack Setup ==="
    echo ""
    
    check_prerequisites
    setup_helm_repo
    create_namespace
    install_monitoring_stack
    install_sample_dashboards
    setup_access
    
    echo ""
    echo "=== Setup Complete! ==="
    echo ""
    echo "🎉 Your Kubernetes monitoring stack is ready!"
    echo ""
    echo "Next steps:"
    echo "1. Access Grafana dashboard using the URL above"
    echo "2. Import additional dashboards from https://grafana.com/grafana/dashboards/"
    echo "3. Configure alerting rules as needed"
    echo "4. Set up log aggregation with Loki (optional)"
    echo ""
    echo "Popular Grafana Dashboard IDs:"
    echo "- 315: Kubernetes cluster monitoring"
    echo "- 6417: Kubernetes cluster autoscaler"
    echo "- 7249: Kubernetes cluster"
    echo "- 10000: Kubernetes cluster (Prometheus)"
    echo ""
}

# Run main function
main "$@"
