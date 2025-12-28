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
PROXMOX_PASS="${PROXMOX_PASS:-Bassa627}"
REMOTE_PATH="/root/k8s-on-proxmox-ansible"
LOCAL_PATH="$(pwd)"
GIT_REPO_URL="${GIT_REPO_URL:-https://github.com/kosments/k8s-on-proxmox-ansible.git}"

# SSHコマンド（後で設定される）
SSH_CMD=""

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
    
    # SSH鍵認証を試す
    if ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no -o PasswordAuthentication=no "$PROXMOX_USER@$PROXMOX_HOST" "echo 'SSH OK'" >/dev/null 2>&1; then
        log "✓ SSH connection successful (SSH key)"
        SSH_CMD="ssh -o StrictHostKeyChecking=no"
        return 0
    fi
    
    # パスワード認証を試す（sshpassが利用可能な場合）
    if command -v sshpass &> /dev/null; then
        if sshpass -p "$PROXMOX_PASS" ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no -o PreferredAuthentications=password "$PROXMOX_USER@$PROXMOX_HOST" "echo 'SSH OK'" >/dev/null 2>&1; then
            log "✓ SSH connection successful (password authentication)"
            # パスワード認証を使用するためのSSH_CMDを設定
            SSH_CMD="sshpass -p '$PROXMOX_PASS' ssh -o StrictHostKeyChecking=no -o PreferredAuthentications=password"
            return 0
        fi
    fi
    
    error "✗ SSH connection failed. Please check your SSH configuration."
}

# SSH_CMDはtest_ssh_connection()で設定される

# リモートディレクトリ準備（Git clone）
clone_repository() {
    log "Cloning repository from Git..."
    $SSH_CMD "$PROXMOX_USER@$PROXMOX_HOST" "
        if [ -d '$REMOTE_PATH' ] && [ -d '$REMOTE_PATH/.git' ]; then
            log 'Repository already exists. Pulling latest changes...'
            cd '$REMOTE_PATH'
            git pull origin main || git pull origin master || true
        elif [ -d '$REMOTE_PATH' ]; then
            warn 'Directory exists but is not a git repository. Backing up and cloning...'
            mv '$REMOTE_PATH' '$REMOTE_PATH.backup.\$(date +%Y%m%d_%H%M%S)'
            cd /root
            git clone '$GIT_REPO_URL' k8s-on-proxmox-ansible
        else
            cd /root
            git clone '$GIT_REPO_URL' k8s-on-proxmox-ansible
        fi
        
        # スクリプトに実行権限を付与
        cd '$REMOTE_PATH'
        find . -name '*.sh' -type f -exec chmod +x {} \;
        log 'Repository cloned and scripts made executable'
    "
}

# リモートディレクトリ準備（ファイル転送用）
prepare_remote_directory() {
    log "Preparing remote directory..."
    $SSH_CMD "$PROXMOX_USER@$PROXMOX_HOST" "
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
            # rsyncにSSHオプションを渡す
            if [[ "$SSH_CMD" == *sshpass* ]]; then
                # sshpassの場合、rsyncの代わりにscpを使用
                log "Using scp instead of rsync (password authentication)"
                rsync -avz --delete \
                    -e "sshpass -p '$PROXMOX_PASS' ssh -o StrictHostKeyChecking=no" \
                    --exclude='.git' \
                    --exclude='*.log' \
                    --exclude='.DS_Store' \
                    --exclude='node_modules' \
                    "$LOCAL_PATH/" "$PROXMOX_USER@$PROXMOX_HOST:$REMOTE_PATH/"
            else
                rsync -avz --delete \
                    --exclude='.git' \
                    --exclude='*.log' \
                    --exclude='.DS_Store' \
                    --exclude='node_modules' \
                    "$LOCAL_PATH/" "$PROXMOX_USER@$PROXMOX_HOST:$REMOTE_PATH/"
            fi
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
    $SSH_CMD "$PROXMOX_USER@$PROXMOX_HOST" "cd $REMOTE_PATH && $command"
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

# K8s セットアップ実行（k3s）
setup_k8s() {
    log "Setting up Kubernetes (k3s) on Proxmox..."
    
    execute_remote "
        cd scripts
        chmod +x 02-setup-k3s.sh
        ./02-setup-k3s.sh
    " "Executing k3s setup script"
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
    echo "  clone             Clone repository from Git (recommended)"
    echo "  sync              Sync all files to Proxmox (rsync)"
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
    echo "  GIT_REPO_URL      Git repository URL (default: https://github.com/kosments/k8s-on-proxmox-ansible.git)"
    echo
    echo "Examples:"
    echo "  $0 clone          # Clone repository from Git (recommended)"
    echo "  $0 sync           # Sync files using rsync"
    echo "  $0 vm-create      # Create VMs after syncing"
}

# SSH接続開始
open_ssh() {
    log "Opening SSH connection to Proxmox..."
    if [[ "$SSH_CMD" == *sshpass* ]]; then
        # sshpassの場合は-tオプションが使えないので、別の方法
        $SSH_CMD "$PROXMOX_USER@$PROXMOX_HOST" "cd $REMOTE_PATH && bash"
    else
        ssh "$PROXMOX_USER@$PROXMOX_HOST" -t "cd $REMOTE_PATH && bash"
    fi
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
        "clone")
            test_ssh_connection
            clone_repository
            ;;
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
            if [ -d "$LOCAL_PATH/.git" ]; then
                # Gitリポジトリの場合はclone推奨
                log "Detected Git repository. Consider using 'clone' command instead."
                read -p "Use Git clone? (y/N): " -n 1 -r
                echo
                if [[ $REPLY =~ ^[Yy]$ ]]; then
                    clone_repository
                else
                    prepare_remote_directory
                    sync_files "vm-create"
                fi
            else
                prepare_remote_directory
                sync_files "vm-create"
            fi
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
