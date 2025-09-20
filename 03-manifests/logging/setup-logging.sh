#!/bin/bash
# =============================================================================
# Kubernetes Logging Stack Setup Script (Grafana Loki + Promtail)
# =============================================================================
#
# このスクリプトは、軽量で高性能なログ集約システムを構築します。
#
# 【インストールされるコンポーネント】
# - Grafana Loki: ログ保存・検索エンジン
# - Promtail: ログ収集エージェント
# - Grafana統合: 既存のGrafanaでログ表示
#
# 【特徴】
# - Prometheus風のラベル設計
# - 軽量（ElasticsearchよりもCPU/メモリ効率が良い）
# - Grafanaとの完全統合
# - LogQL: 強力なクエリ言語
#
# =============================================================================

set -euo pipefail

# Configuration
NAMESPACE="logging"
LOKI_RELEASE="loki"
PROMTAIL_RELEASE="promtail"
HELM_REPO="grafana"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Logging functions
log() { echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"; }
warn() { echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING: $1${NC}"; }
error() { echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $1${NC}"; exit 1; }
success() { echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"; }

# Check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    if ! command -v kubectl &> /dev/null; then
        error "kubectl not found"
    fi
    
    if ! command -v helm &> /dev/null; then
        error "helm not found"
    fi
    
    success "Prerequisites OK"
}

# Setup Helm repository
setup_helm_repo() {
    log "Setting up Grafana Helm repository..."
    
    helm repo add $HELM_REPO https://grafana.github.io/helm-charts
    helm repo update
    
    success "Helm repository configured"
}

# Create namespace
create_namespace() {
    log "Creating logging namespace..."
    kubectl create namespace $NAMESPACE --dry-run=client -o yaml | kubectl apply -f -
    success "Namespace ready"
}

# Install Loki
install_loki() {
    log "Installing Grafana Loki..."
    
    cat > /tmp/loki-values.yaml << 'EOF'
# Loki Configuration
loki:
  config:
    auth_enabled: false
    server:
      http_listen_port: 3100
    ingester:
      lifecycler:
        address: 127.0.0.1
        ring:
          kvstore:
            store: inmemory
          replication_factor: 1
    schema_config:
      configs:
        - from: 2020-10-24
          store: boltdb-shipper
          object_store: filesystem
          schema: v11
          index:
            prefix: index_
            period: 24h
    storage_config:
      boltdb_shipper:
        active_index_directory: /loki/boltdb-shipper-active
        cache_location: /loki/boltdb-shipper-cache
        shared_store: filesystem
      filesystem:
        directory: /loki/chunks
    limits_config:
      enforce_metric_name: false
      reject_old_samples: true
      reject_old_samples_max_age: 168h
      retention_period: 744h  # 31 days

# Persistence
persistence:
  enabled: true
  size: 50Gi

# Service configuration
service:
  type: ClusterIP
  port: 3100

# Resources
resources:
  requests:
    cpu: 100m
    memory: 256Mi
  limits:
    cpu: 1000m
    memory: 1Gi
EOF

    helm upgrade --install $LOKI_RELEASE $HELM_REPO/loki \
        --namespace $NAMESPACE \
        --values /tmp/loki-values.yaml \
        --wait \
        --timeout 10m
    
    success "Loki installed successfully"
}

# Install Promtail
install_promtail() {
    log "Installing Promtail..."
    
    cat > /tmp/promtail-values.yaml << 'EOF'
# Promtail Configuration
config:
  logLevel: info
  serverPort: 3101
  clients:
    - url: http://loki:3100/loki/api/v1/push

# DaemonSet configuration
daemonset:
  enabled: true

# Scrape configuration
scrapeConfigs:
  - job_name: kubernetes-pods
    kubernetes_sd_configs:
      - role: pod
    relabel_configs:
      - source_labels:
          - __meta_kubernetes_pod_controller_name
        regex: ([0-9a-z-.]+?)(-[0-9a-f]{8,10})?
        action: replace
        target_label: __tmp_controller_name
      - source_labels:
          - __meta_kubernetes_pod_label_app_kubernetes_io_name
          - __meta_kubernetes_pod_label_app
          - __tmp_controller_name
          - __meta_kubernetes_pod_name
        regex: ^;*([^;]+)(;.*)?$
        action: replace
        target_label: app
      - source_labels:
          - __meta_kubernetes_pod_label_app_kubernetes_io_instance
          - __meta_kubernetes_pod_label_release
        regex: ^;*([^;]+)(;.*)?$
        action: replace
        target_label: instance
      - source_labels:
          - __meta_kubernetes_pod_label_app_kubernetes_io_component
          - __meta_kubernetes_pod_label_component
        regex: ^;*([^;]+)(;.*)?$
        action: replace
        target_label: component
      - action: replace
        source_labels:
        - __meta_kubernetes_pod_node_name
        target_label: node_name
      - action: replace
        source_labels:
        - __meta_kubernetes_namespace
        target_label: namespace
      - action: replace
        replacement: $1
        separator: /
        source_labels:
        - namespace
        - app
        target_label: job
      - action: replace
        source_labels:
        - __meta_kubernetes_pod_name
        target_label: pod
      - action: replace
        source_labels:
        - __meta_kubernetes_pod_container_name
        target_label: container
      - action: replace
        replacement: /var/log/pods/*$1/*.log
        separator: /
        source_labels:
        - __meta_kubernetes_pod_uid
        - __meta_kubernetes_pod_container_name
        target_label: __path__
      - action: replace
        regex: true/(.*)
        replacement: /var/log/pods/*$1/*.log
        separator: /
        source_labels:
        - __meta_kubernetes_pod_annotationpresent_kubernetes_io_config_hash
        - __meta_kubernetes_pod_annotation_kubernetes_io_config_hash
        - __meta_kubernetes_pod_container_name
        target_label: __path__

# Resources
resources:
  requests:
    cpu: 100m
    memory: 128Mi
  limits:
    cpu: 200m
    memory: 256Mi

# Tolerations to run on all nodes
tolerations:
  - effect: NoSchedule
    operator: Exists
  - effect: NoExecute
    operator: Exists
EOF

    helm upgrade --install $PROMTAIL_RELEASE $HELM_REPO/promtail \
        --namespace $NAMESPACE \
        --values /tmp/promtail-values.yaml \
        --wait \
        --timeout 10m
    
    success "Promtail installed successfully"
}

# Configure Grafana data source
configure_grafana_datasource() {
    log "Configuring Grafana data source for Loki..."
    
    # Create Loki data source configuration
    cat > /tmp/loki-datasource.yaml << 'EOF'
apiVersion: v1
kind: ConfigMap
metadata:
  name: loki-datasource
  namespace: monitoring
  labels:
    grafana_datasource: "1"
data:
  loki-datasource.yaml: |
    apiVersion: 1
    datasources:
    - name: Loki
      type: loki
      access: proxy
      url: http://loki.logging.svc.cluster.local:3100
      isDefault: false
      editable: true
EOF
    
    kubectl apply -f /tmp/loki-datasource.yaml
    
    # Restart Grafana to pick up the new data source
    kubectl rollout restart deployment/kube-prometheus-stack-grafana -n monitoring 2>/dev/null || \
    warn "Could not restart Grafana. You may need to add Loki data source manually."
    
    success "Grafana data source configured"
}

# Create sample log dashboard
create_log_dashboard() {
    log "Creating sample log dashboard..."
    
    cat > /tmp/logs-dashboard.json << 'EOF'
{
  "dashboard": {
    "id": null,
    "title": "Kubernetes Logs",
    "tags": ["kubernetes", "logs"],
    "timezone": "browser",
    "panels": [
      {
        "id": 1,
        "title": "Log Volume by Namespace",
        "type": "bargauge",
        "targets": [
          {
            "expr": "sum by (namespace) (count_over_time({namespace=~\".+\"}[1h]))",
            "legendFormat": "{{namespace}}"
          }
        ],
        "gridPos": {"h": 8, "w": 24, "x": 0, "y": 0}
      },
      {
        "id": 2,
        "title": "Recent Logs",
        "type": "logs",
        "targets": [
          {
            "expr": "{namespace=~\".+\"}",
            "legendFormat": ""
          }
        ],
        "gridPos": {"h": 12, "w": 24, "x": 0, "y": 8}
      }
    ],
    "time": {"from": "now-1h", "to": "now"},
    "refresh": "30s"
  }
}
EOF
    
    success "Sample log dashboard created"
}

# Main execution
main() {
    echo "=== Kubernetes Logging Stack Setup ==="
    echo ""
    
    check_prerequisites
    setup_helm_repo
    create_namespace
    install_loki
    install_promtail
    configure_grafana_datasource
    create_log_dashboard
    
    echo ""
    echo "=== Logging Setup Complete! ==="
    echo ""
    echo "🎉 Grafana Loki logging stack is ready!"
    echo ""
    echo "Access logs via:"
    echo "1. Grafana Dashboard (add Loki data source if not auto-configured)"
    echo "   - URL: http://your-grafana-url"
    echo "   - Data Source: http://loki.logging.svc.cluster.local:3100"
    echo ""
    echo "2. LogQL Query Examples:"
    echo "   - All logs: {namespace=\"default\"}"
    echo "   - Error logs: {namespace=\"default\"} |= \"ERROR\""
    echo "   - Pod logs: {pod=\"my-pod\"}"
    echo "   - Rate: rate({namespace=\"default\"}[5m])"
    echo ""
    echo "3. Useful LogQL patterns:"
    echo "   - {namespace=\"kube-system\", container=\"coredns\"}"
    echo "   - {app=\"nginx\"} |= \"error\" | json"
    echo "   - sum by (pod) (rate({namespace=\"default\"}[1m]))"
    echo ""
}

main "$@"
