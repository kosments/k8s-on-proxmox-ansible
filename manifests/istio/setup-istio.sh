#!/bin/bash
# =============================================================================
# Istio Service Mesh Setup Script
# =============================================================================
#
# このスクリプトは、Kubernetesクラスターにistio Service Meshを構築します。
#
# 【インストールされるコンポーネント】
# - Istio Control Plane (istiod)
# - Istio Ingress Gateway
# - Istio Egress Gateway (オプション)
# - Kiali (Service Mesh可視化)
# - Jaeger (分散トレーシング)
# - Grafana統合
#
# 【前提条件】
# - Kubernetesクラスターが動作している
# - kubectl が設定済み
# - 十分なリソース（各ノード2GB以上のメモリ推奨）
#
# =============================================================================

set -euo pipefail

# Configuration
ISTIO_VERSION="1.19.0"
ISTIO_DIR="istio-${ISTIO_VERSION}"
ISTIO_NAMESPACE="istio-system"
INGRESS_NAMESPACE="istio-ingress"

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
    
    if ! kubectl cluster-info &> /dev/null; then
        error "Cannot connect to Kubernetes cluster"
    fi
    
    # Check cluster resources
    local nodes=$(kubectl get nodes --no-headers | wc -l)
    if [ $nodes -lt 1 ]; then
        error "At least 1 node required"
    fi
    
    success "Prerequisites check completed"
}

# Download and install Istio
install_istio_cli() {
    log "Downloading Istio ${ISTIO_VERSION}..."
    
    if [ ! -d "$ISTIO_DIR" ]; then
        curl -L https://istio.io/downloadIstio | ISTIO_VERSION=$ISTIO_VERSION sh -
    else
        log "Istio already downloaded"
    fi
    
    # Add istioctl to PATH for this session
    export PATH="$PWD/$ISTIO_DIR/bin:$PATH"
    
    # Verify installation
    if ! command -v istioctl &> /dev/null; then
        error "istioctl not found in PATH"
    fi
    
    success "Istio CLI installed successfully"
}

# Install Istio control plane
install_istio_control_plane() {
    log "Installing Istio control plane..."
    
    # Create namespace
    kubectl create namespace $ISTIO_NAMESPACE --dry-run=client -o yaml | kubectl apply -f -
    
    # Install Istio with demo profile (includes ingress/egress gateways)
    istioctl install --set values.defaultRevision=default -y
    
    # Verify installation
    kubectl wait --for=condition=ready pod -l app=istiod -n $ISTIO_NAMESPACE --timeout=300s
    
    success "Istio control plane installed"
}

# Install Istio addons (Kiali, Jaeger, etc.)
install_istio_addons() {
    log "Installing Istio addons..."
    
    # Apply all addons
    kubectl apply -f $ISTIO_DIR/samples/addons/
    
    # Wait for addons to be ready
    log "Waiting for addons to be ready..."
    
    # Wait for Kiali
    kubectl wait --for=condition=ready pod -l app=kiali -n $ISTIO_NAMESPACE --timeout=300s 2>/dev/null || warn "Kiali not ready"
    
    # Wait for Jaeger
    kubectl wait --for=condition=ready pod -l app=jaeger -n $ISTIO_NAMESPACE --timeout=300s 2>/dev/null || warn "Jaeger not ready"
    
    # Wait for Prometheus
    kubectl wait --for=condition=ready pod -l app=prometheus -n $ISTIO_NAMESPACE --timeout=300s 2>/dev/null || warn "Prometheus not ready"
    
    success "Istio addons installed"
}

# Configure ingress gateway
configure_ingress_gateway() {
    log "Configuring Istio Ingress Gateway..."
    
    # Create ingress namespace
    kubectl create namespace $INGRESS_NAMESPACE --dry-run=client -o yaml | kubectl apply -f -
    kubectl label namespace $INGRESS_NAMESPACE istio-injection=enabled --overwrite
    
    # Get ingress gateway service info
    local gateway_ip=$(kubectl get svc istio-ingressgateway -n $ISTIO_NAMESPACE -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")
    local gateway_port=$(kubectl get svc istio-ingressgateway -n $ISTIO_NAMESPACE -o jsonpath='{.spec.ports[?(@.name=="http2")].nodePort}')
    local gateway_secure_port=$(kubectl get svc istio-ingressgateway -n $ISTIO_NAMESPACE -o jsonpath='{.spec.ports[?(@.name=="https")].nodePort}')
    
    # Create basic gateway configuration
    cat > /tmp/istio-gateway.yaml << 'EOF'
apiVersion: networking.istio.io/v1alpha3
kind: Gateway
metadata:
  name: default-gateway
  namespace: istio-system
spec:
  selector:
    istio: ingressgateway
  servers:
  - port:
      number: 80
      name: http
      protocol: HTTP
    hosts:
    - "*"
  - port:
      number: 443
      name: https
      protocol: HTTPS
    tls:
      mode: SIMPLE
      credentialName: tls-secret
    hosts:
    - "*"
EOF
    
    kubectl apply -f /tmp/istio-gateway.yaml
    
    success "Ingress gateway configured"
    
    echo ""
    echo "=== Ingress Gateway Information ==="
    echo "HTTP Port: ${gateway_port:-30080}"
    echo "HTTPS Port: ${gateway_secure_port:-30443}"
    if [ -n "$gateway_ip" ]; then
        echo "External IP: $gateway_ip"
    else
        echo "External IP: Use NodePort with any node IP"
    fi
    echo ""
}

# Create sample Istio configuration
create_sample_config() {
    log "Creating sample Istio configurations..."
    
    # Virtual Service for sample app
    cat > /tmp/sample-app-vs.yaml << 'EOF'
apiVersion: networking.istio.io/v1alpha3
kind: VirtualService
metadata:
  name: sample-app-vs
  namespace: sample-apps
spec:
  hosts:
  - "*"
  gateways:
  - istio-system/default-gateway
  http:
  - match:
    - uri:
        prefix: "/sample"
    rewrite:
      uri: "/"
    route:
    - destination:
        host: sample-app
        port:
          number: 80
  - match:
    - uri:
        exact: "/"
    route:
    - destination:
        host: sample-app
        port:
          number: 80
---
apiVersion: networking.istio.io/v1alpha3
kind: DestinationRule
metadata:
  name: sample-app-dr
  namespace: sample-apps
spec:
  host: sample-app
  trafficPolicy:
    loadBalancer:
      simple: LEAST_CONN
  subsets:
  - name: v1
    labels:
      version: v1
EOF
    
    kubectl apply -f /tmp/sample-app-vs.yaml
    
    success "Sample Istio configurations created"
}

# Setup access to Istio addons
setup_addon_access() {
    log "Setting up access to Istio addons..."
    
    echo ""
    echo "=== Istio Addons Access ==="
    echo ""
    
    # Kiali
    echo "🕸️  Kiali (Service Mesh Dashboard):"
    echo "   Port Forward: kubectl port-forward -n $ISTIO_NAMESPACE svc/kiali 20001:20001"
    echo "   Then access: http://localhost:20001"
    echo ""
    
    # Jaeger
    echo "🔍 Jaeger (Distributed Tracing):"
    echo "   Port Forward: kubectl port-forward -n $ISTIO_NAMESPACE svc/jaeger 16686:16686"
    echo "   Then access: http://localhost:16686"
    echo ""
    
    # Grafana (if installed)
    echo "📊 Grafana (Istio Metrics):"
    echo "   Port Forward: kubectl port-forward -n $ISTIO_NAMESPACE svc/grafana 3000:3000"
    echo "   Then access: http://localhost:3000"
    echo ""
    
    # Prometheus (if installed)
    echo "📈 Prometheus (Istio Metrics):"
    echo "   Port Forward: kubectl port-forward -n $ISTIO_NAMESPACE svc/prometheus 9090:9090"
    echo "   Then access: http://localhost:9090"
    echo ""
    
    success "Access information displayed"
}

# Enable automatic sidecar injection for sample-apps namespace
enable_sidecar_injection() {
    log "Enabling automatic sidecar injection for sample-apps namespace..."
    
    # Create namespace if it doesn't exist
    kubectl create namespace sample-apps --dry-run=client -o yaml | kubectl apply -f -
    
    # Enable Istio injection
    kubectl label namespace sample-apps istio-injection=enabled --overwrite
    
    # Restart sample app pods if they exist
    if kubectl get deployment sample-app -n sample-apps &>/dev/null; then
        kubectl rollout restart deployment/sample-app -n sample-apps
        kubectl wait --for=condition=ready pod -l app=sample-app -n sample-apps --timeout=300s
    fi
    
    success "Sidecar injection enabled for sample-apps namespace"
}

# Create monitoring configuration for Istio
create_istio_monitoring() {
    log "Creating Istio monitoring configuration..."
    
    # ServiceMonitor for Istio metrics (if Prometheus Operator is installed)
    cat > /tmp/istio-monitoring.yaml << 'EOF'
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: istio-proxy
  namespace: monitoring
  labels:
    app: istio-proxy
spec:
  selector:
    matchLabels:
      app: istio-proxy
  endpoints:
  - port: http-monitoring
    interval: 15s
    path: /stats/prometheus
---
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: istiod
  namespace: monitoring
  labels:
    app: istiod
spec:
  selector:
    matchLabels:
      app: istiod
  endpoints:
  - port: http-monitoring
    interval: 15s
    path: /metrics
EOF
    
    kubectl apply -f /tmp/istio-monitoring.yaml 2>/dev/null || warn "Could not create ServiceMonitor (Prometheus Operator not found)"
    
    success "Istio monitoring configuration created"
}

# Main execution
main() {
    echo "=== Istio Service Mesh Setup ==="
    echo ""
    
    check_prerequisites
    install_istio_cli
    install_istio_control_plane
    install_istio_addons
    configure_ingress_gateway
    enable_sidecar_injection
    create_sample_config
    create_istio_monitoring
    setup_addon_access
    
    echo ""
    echo "=== Istio Setup Complete! ==="
    echo ""
    echo "🎉 Istio Service Mesh is ready!"
    echo ""
    echo "Next steps:"
    echo "1. Deploy sample application: kubectl apply -f ../apps/sample-app.yaml"
    echo "2. Access Kiali dashboard to visualize service mesh"
    echo "3. Check distributed tracing in Jaeger"
    echo "4. Monitor service metrics in Grafana"
    echo ""
    echo "Useful commands:"
    echo "- Check Istio status: istioctl proxy-status"
    echo "- Analyze configuration: istioctl analyze"
    echo "- View proxy config: istioctl proxy-config cluster <pod-name>"
    echo "- Enable debug logging: istioctl proxy-config log <pod-name> --level debug"
    echo ""
    echo "Access sample app:"
    local node_ip=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')
    local gateway_port=$(kubectl get svc istio-ingressgateway -n $ISTIO_NAMESPACE -o jsonpath='{.spec.ports[?(@.name=="http2")].nodePort}')
    echo "- http://${node_ip}:${gateway_port}/sample"
    echo ""
}

# Run main function
main "$@"
