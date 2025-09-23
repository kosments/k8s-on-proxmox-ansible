#!/bin/bash

# =============================================================================
# Proxmox デプロイメントスクリプト
# =============================================================================
# 
# このスクリプトは、ローカルの変更をProxmoxホストに自動同期します
#
# 使用方法:
#   ./deploy-to-proxmox.sh [target] [action]
#
# Examples:
#   ./deploy-to-proxmox.sh sync          # 全体同期
#   ./deploy-to-proxmox.sh monitoring    # 監視設定のみ
#   ./deploy-to-proxmox.sh vm-create     # VM作成のみ
#   ./deploy-to-proxmox.sh k8s-setup     # K8s設定のみ
#
# =============================================================================

set -euo pipefail

# 設定
PROXMOX_HOST="${PROXMOX_HOST:-192.168.10.108}"
PROXMOX_USER="${PROXMOX_USER:-root}"
REMOTE_PATH="/root/k8s-on-proxmox-ansible"
LOCAL_PATH="$(pwd)"

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

# SSH接続テスト
test_ssh_connection() {
    log "Testing SSH connection to Proxmox..."
    if ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no "$PROXMOX_USER@$PROXMOX_HOST" "echo 'SSH OK'" >/dev/null 2>&1; then
        log "✓ SSH connection successful"
    else
        error "✗ SSH connection failed. Please check your SSH configuration."
    fi
}

# リモートディレクトリ準備
prepare_remote_directory() {
    log "Preparing remote directory..."
    ssh "$PROXMOX_USER@$PROXMOX_HOST" "
        if [ ! -d '$REMOTE_PATH' ]; then
            mkdir -p '$REMOTE_PATH'
            log 'Created remote directory: $REMOTE_PATH'
        fi
    "
}

# ファイル同期
sync_files() {
    local target=${1:-"all"}
    
    log "Syncing files to Proxmox (target: $target)..."
    
    case $target in
        "all"|"sync")
            rsync -avz --delete \
                --exclude='.git' \
                --exclude='*.log' \
                --exclude='.DS_Store' \
                --exclude='node_modules' \
                "$LOCAL_PATH/" "$PROXMOX_USER@$PROXMOX_HOST:$REMOTE_PATH/"
            ;;
        "monitoring")
            rsync -avz \
                "$LOCAL_PATH/05-monitoring/" \
                "$LOCAL_PATH/config.sh" \
                "$PROXMOX_USER@$PROXMOX_HOST:$REMOTE_PATH/"
            ;;
        "vm-create")
            rsync -avz \
                "$LOCAL_PATH/01-vm-creation/" \
                "$LOCAL_PATH/config.sh" \
                "$PROXMOX_USER@$PROXMOX_HOST:$REMOTE_PATH/"
            ;;
        "k8s-setup")
            rsync -avz \
                "$LOCAL_PATH/02-k8s-cluster/" \
                "$LOCAL_PATH/config.sh" \
                "$PROXMOX_USER@$PROXMOX_HOST:$REMOTE_PATH/"
            ;;
        *)
            warn "Unknown target: $target. Syncing all files."
            sync_files "all"
            ;;
    esac
    
    log "✓ File sync completed"
}

# リモート実行
execute_remote() {
    local command="$1"
    local description="$2"
    
    log "$description"
    ssh "$PROXMOX_USER@$PROXMOX_HOST" "cd $REMOTE_PATH && $command"
}

# 監視セットアップ実行
setup_monitoring() {
    log "Setting up monitoring on Proxmox..."
    
    execute_remote "
        # kubeconfigの確認
        if [ ! -f '02-k8s-cluster/kubeconfig' ]; then
            echo 'Error: kubeconfig not found. Please run k8s setup first.'
            exit 1
        fi
        
        export KUBECONFIG=\$PWD/02-k8s-cluster/kubeconfig
        
        # 運用ネームスペース作成
        kubectl create namespace ops --dry-run=client -o yaml | kubectl apply -f -
        kubectl label namespace ops name=ops --overwrite
        
        echo 'Monitoring namespace created successfully!'
        kubectl get namespace ops
    " "Creating monitoring namespace"
}

# VM作成実行
create_vms() {
    log "Creating VMs on Proxmox..."
    
    execute_remote "
        cd 01-vm-creation
        chmod +x create-vms.sh
        ./create-vms.sh
    " "Executing VM creation script"
}

# K8s セットアップ実行
setup_k8s() {
    log "Setting up Kubernetes on Proxmox..."
    
    execute_remote "
        cd 02-k8s-cluster
        chmod +x setup-k8s-cluster.sh
        ./setup-k8s-cluster.sh
    " "Executing K8s setup script"
}

# ステータス確認
check_status() {
    log "Checking system status..."
    
    execute_remote "
        echo '=== Proxmox VMs ==='
        qm list
        echo
        
        if [ -f '02-k8s-cluster/kubeconfig' ]; then
            export KUBECONFIG=\$PWD/02-k8s-cluster/kubeconfig
            echo '=== Kubernetes Nodes ==='
            kubectl get nodes -o wide || echo 'K8s cluster not ready'
            echo
            echo '=== Kubernetes Pods ==='
            kubectl get pods -A || echo 'K8s cluster not ready'
        else
            echo 'K8s cluster not configured yet'
        fi
    " "Checking system status"
}

# ヘルプ表示
show_help() {
    echo "Usage: $0 [command]"
    echo
    echo "Commands:"
    echo "  sync              Sync all files to Proxmox"
    echo "  monitoring        Sync and setup monitoring"
    echo "  vm-create         Create VMs"
    echo "  k8s-setup         Setup Kubernetes cluster"
    echo "  status            Check system status"
    echo "  ssh               Open SSH connection to Proxmox"
    echo "  help              Show this help"
    echo
    echo "Environment Variables:"
    echo "  PROXMOX_HOST      Proxmox host IP (default: 192.168.10.108)"
    echo "  PROXMOX_USER      Proxmox user (default: root)"
    echo
}

# SSH接続開始
open_ssh() {
    log "Opening SSH connection to Proxmox..."
    ssh "$PROXMOX_USER@$PROXMOX_HOST" -t "cd $REMOTE_PATH && bash"
}

# メイン処理
main() {
    local command=${1:-"help"}
    
    echo -e "${BLUE}"
    echo "================================================"
    echo "  Proxmox Deployment Script"
    echo "  Target: $PROXMOX_USER@$PROXMOX_HOST"
    echo "================================================"
    echo -e "${NC}"
    
    case $command in
        "sync")
            test_ssh_connection
            prepare_remote_directory
            sync_files "all"
            ;;
        "monitoring")
            test_ssh_connection
            prepare_remote_directory
            sync_files "monitoring"
            setup_monitoring
            ;;
        "vm-create")
            test_ssh_connection
            prepare_remote_directory
            sync_files "vm-create"
            create_vms
            ;;
        "k8s-setup")
            test_ssh_connection
            prepare_remote_directory
            sync_files "k8s-setup"
            setup_k8s
            ;;
        "status")
            test_ssh_connection
            check_status
            ;;
        "ssh")
            test_ssh_connection
            open_ssh
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
