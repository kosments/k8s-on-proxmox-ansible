#!/bin/bash

# =============================================================================
# Kubernetes Cluster Setup Script for Proxmox VMs
# =============================================================================
# 
# このスクリプトは、ProxmoxVE上のVMにKubernetesクラスターを構築します。
# 
# 【主な機能】
# - 動的VM検出（config.shの設定に基づく）
# - 全ノードへのKubernetes共通コンポーネント導入
# - マスターノードの初期化（kubeadm init）
# - CNI（Flannel）の自動インストール
# - ワーカーノードの自動参加
# - クラスター状態の検証
# - 冪等性保証（再実行可能）
# - 詳細なSSH接続診断とエラーハンドリング
# 
# 【実行フェーズ】
# Phase 0: ディスク容量チェックとクリーンアップ
# Phase 1: 全ノードへの共通セットアップ
# Phase 2: マスターノードの初期化
# Phase 3: CNI（Flannel）のインストール
# Phase 4: ワーカーノードのクラスター参加
# Phase 5: クラスター状態の検証
# 
# 【使用方法】
# ./setup-k8s-cluster.sh
# 
# 【前提条件】
# - create-vms.sh でVMが作成済み
# - VMが起動中でSSH接続可能
# 
# 【出力ファイル】
# - kubeconfig: kubectl用の設定ファイル
# - join-command.txt: ワーカーノード参加用コマンド
# 
# 【kubectl使用方法】
# Proxmoxホストでkubectlが利用できない場合：
# 1. kubectl インストール（推奨）:
#    curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
#    chmod +x kubectl && mv kubectl /usr/local/bin/
#    export KUBECONFIG=$PWD/kubeconfig
#    kubectl get nodes
# 
# 2. スクリプト経由でクラスター管理:
#    ./setup-k8s-cluster.sh status
#    ./setup-k8s-cluster.sh logs
# 
# =============================================================================

set -e

# Load shared configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="$SCRIPT_DIR/../config.sh"

if [ -f "$CONFIG_FILE" ]; then
    source "$CONFIG_FILE"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Loaded configuration from $CONFIG_FILE"
else
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: Configuration file not found: $CONFIG_FILE"
    exit 1
fi

# K8s setup specific configuration
SSH_KEY="$SSH_KEY_PATH"
K8S_VERSION="1.28.2-1.1"
POD_CIDR="$POD_NETWORK_CIDR"

# Get active VMs for cluster setup
ACTIVE_VMS=($(get_active_vms))
MASTER_VM=$(get_master_vm)
WORKER_VMS=($(get_worker_vms))

# Set legacy variables for backward compatibility
MASTER_IP=$(get_vm_ip $MASTER_VM)
if [ ${#WORKER_VMS[@]} -gt 0 ]; then
    NODE1_IP=$(get_vm_ip ${WORKER_VMS[0]})
fi
if [ ${#WORKER_VMS[@]} -gt 1 ]; then
    NODE2_IP=$(get_vm_ip ${WORKER_VMS[1]})
fi

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING: $1${NC}"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $1${NC}"
    exit 1
}

# Clear SSH host keys for all active VMs (to avoid host key conflicts on VM recreation)
clear_ssh_host_keys() {
    log "Clearing SSH host keys to avoid conflicts..."
    
    # Remove host keys for all active VM IPs
    for vm_id in "${ACTIVE_VMS[@]}"; do
        local vm_ip=$(get_vm_ip $vm_id)
        if [ -n "$vm_ip" ]; then
            ssh-keygen -f "/root/.ssh/known_hosts" -R "$vm_ip" 2>/dev/null || true
            log "Cleared host key for VM $vm_id ($vm_ip)"
        fi
    done
    
    log "SSH host keys cleared for all active VMs"
}

# Test SSH connectivity with aggressive host key management
test_ssh() {
    local host=$1
    log "Testing SSH connectivity to $host..."
    
    # Use very permissive SSH options to avoid host key issues
    local ssh_opts="-o ConnectTimeout=10 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR"
    
    if ssh $ssh_opts -i $SSH_KEY $SSH_USER@$host "echo 'SSH OK'" >/dev/null 2>&1; then
        log "SSH to $host: OK"
        return 0
    else
        warn "SSH to $host: FAILED - running diagnosis..."
        
        # Run diagnosis first
        if ! diagnose_ssh $host; then
            warn "VM $host appears to have connectivity issues. Waiting 30 seconds and retrying..."
            sleep 30
            
            # Try diagnosis again
            if ! diagnose_ssh $host; then
                error "VM $host is not accessible. Please check VM status manually with: qm status <vm_id>"
                return 1
            fi
        fi
        
        # Try to setup SSH key
        log "Attempting to setup SSH key..."
        if setup_ssh_key $host; then
            log "SSH key setup successful, testing connection again..."
            sleep 5
            
            # Test again after key setup
            if ssh $ssh_opts -i $SSH_KEY $SSH_USER@$host "echo 'SSH OK'" >/dev/null 2>&1; then
                log "SSH to $host: OK (after key setup)"
                return 0
            else
                warn "SSH key authentication still failing, trying password authentication test..."
                if sshpass -p "ubuntu" ssh $ssh_opts $SSH_USER@$host "echo 'SSH OK'" >/dev/null 2>&1; then
                    warn "Password authentication works but key authentication doesn't. There may be an issue with the SSH key setup."
                else
                    warn "Both key and password authentication are failing."
                fi
                error "SSH to $host: STILL FAILED after key setup"
                return 1
            fi
        else
            error "SSH key setup failed for $host"
            return 1
        fi
    fi
}

# Diagnose SSH connection issues
diagnose_ssh() {
    local host=$1
    log "Diagnosing SSH connection issues for $host..."
    
    # Test basic connectivity
    log "Testing basic connectivity (ping)..."
    if ping -c 1 -W 5 $host &>/dev/null; then
        log "✓ Host $host is reachable via ping"
    else
        warn "✗ Host $host is not reachable via ping"
        return 1
    fi
    
    # Test SSH port
    log "Testing SSH port (22)..."
    if timeout 5 nc -z $host 22 &>/dev/null; then
        log "✓ SSH port 22 is open on $host"
    else
        warn "✗ SSH port 22 is not accessible on $host"
        log "VM may still be booting or SSH service is not running"
        return 1
    fi
    
    # Test SSH banner
    log "Testing SSH service response..."
    local ssh_banner=$(timeout 5 nc $host 22 </dev/null 2>/dev/null | head -1)
    if [[ $ssh_banner == *"SSH"* ]]; then
        log "✓ SSH service is responding: $ssh_banner"
    else
        warn "✗ SSH service is not responding properly"
        return 1
    fi
    
    return 0
}

# Setup SSH key for a host
setup_ssh_key() {
    local host=$1
    log "Setting up SSH key for $host..."
    
    # First, diagnose the connection
    if ! diagnose_ssh $host; then
        warn "SSH diagnosis failed for $host, skipping key setup"
        return 1
    fi
    
    # Try password authentication to copy the key
    if command -v sshpass &> /dev/null; then
        log "Using sshpass to copy SSH key..."
        local ssh_copy_opts="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10"
        if sshpass -p "ubuntu" ssh-copy-id $ssh_copy_opts -i ${SSH_KEY}.pub $SSH_USER@$host 2>/dev/null; then
            log "✓ SSH key successfully copied to $host"
            return 0
        else
            warn "✗ Failed to copy SSH key to $host using password authentication"
            return 1
        fi
    else
        warn "sshpass not available. Manual SSH key setup may be required."
        log "Please run: ssh-copy-id -i ${SSH_KEY}.pub $SSH_USER@$host"
        log "Or ensure the VMs were created with the SSH key already installed."
        return 1
    fi
}

# Execute command on remote host
remote_exec() {
    local host=$1
    shift
    local cmd="$*"
    log "Executing on $host: $cmd"
    
    # Use consistent SSH options across all connections
    local ssh_opts="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR"
    
    # Use heredoc to avoid quoting issues
    if ssh $ssh_opts -i $SSH_KEY $SSH_USER@$host "sudo bash -s" <<< "$cmd"; then
        log "Command executed successfully on $host"
        return 0
    else
        warn "Command failed on $host, but continuing..."
        return 1
    fi
}

# Setup common components on a node
setup_common() {
    local host=$1
    local hostname=$2
    
    log "Setting up common components on $hostname ($host)..."
    
    # Update system and set hostname
    remote_exec $host "
        # Set hostname (idempotent)
        hostnamectl set-hostname $hostname
        
        # Fix any package issues first (idempotent)
        export DEBIAN_FRONTEND=noninteractive
        
        # Clean up disk space first
        apt-get clean
        apt-get autoclean
        apt-get autoremove -y || true
        
        # Clear old kernels to free up space
        apt-get autoremove --purge -y || true
        
        # Remove old log files
        journalctl --vacuum-time=3d || true
        
        # Update and fix broken packages
        apt-get update || true
        apt --fix-broken install -y || true
        apt-get update
        
        # Upgrade system (idempotent) - skip if disk space is low
        df -h / | awk 'NR==2 {print \$5}' | sed 's/%//' | (read percent; if [ \$percent -lt 90 ]; then apt-get upgrade -y; else echo 'Skipping upgrade due to low disk space'; fi) || true
        apt-get autoremove -y || true
        
        # Additional cleanup after upgrade
        apt-get clean
        apt-get autoclean
        
        # Install required packages (idempotent)
        apt-get install -y apt-transport-https ca-certificates curl gnupg lsb-release software-properties-common
        
        # Disable swap (idempotent)
        swapoff -a || true
        # Comment out swap entries in fstab (more robust approach)
        if grep -q '^[^#]*swap' /etc/fstab 2>/dev/null; then
            sed -i.bak '/^[^#]*swap/s/^/#/' /etc/fstab || true
        fi
        
        # Load kernel modules (idempotent)
        modprobe overlay || true
        modprobe br_netfilter || true
        
        # Setup kernel modules to load at boot (idempotent)
        if [ ! -f /etc/modules-load.d/containerd.conf ]; then
            cat <<EOF > /etc/modules-load.d/containerd.conf
overlay
br_netfilter
EOF
        fi

        # Setup sysctl params (idempotent)
        if [ ! -f /etc/sysctl.d/99-kubernetes-cri.conf ]; then
            cat <<EOF > /etc/sysctl.d/99-kubernetes-cri.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF
        fi
        sysctl --system || true
        
        # Install containerd (idempotent)
        if ! command -v containerd &> /dev/null; then
            curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
            echo \"deb [arch=amd64 signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu \$(lsb_release -cs) stable\" > /etc/apt/sources.list.d/docker.list
            apt-get update
            apt-get install -y containerd.io
        fi
        
        # Configure containerd (idempotent)
        mkdir -p /etc/containerd
        if [ ! -f /etc/containerd/config.toml ] || ! grep -q 'SystemdCgroup = true' /etc/containerd/config.toml; then
            containerd config default > /etc/containerd/config.toml
            sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
            systemctl restart containerd
        fi
        systemctl enable containerd
        
        # Add Kubernetes repository (idempotent)
        if [ ! -f /usr/share/keyrings/kubernetes-archive-keyring.gpg ]; then
            curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.28/deb/Release.key | gpg --dearmor -o /usr/share/keyrings/kubernetes-archive-keyring.gpg
        fi
        if [ ! -f /etc/apt/sources.list.d/kubernetes.list ]; then
            echo \"deb [signed-by=/usr/share/keyrings/kubernetes-archive-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.28/deb/ /\" > /etc/apt/sources.list.d/kubernetes.list
        fi
        
        # Install Kubernetes components (idempotent)
        if ! command -v kubeadm &> /dev/null; then
            apt-get update
            apt-get install -y kubelet=$K8S_VERSION kubeadm=$K8S_VERSION kubectl=$K8S_VERSION
            apt-mark hold kubelet kubeadm kubectl
        fi
        
        # Enable kubelet (idempotent)
        systemctl enable kubelet || true
    "
    
    log "Common setup completed on $hostname"
}

# Initialize master node
setup_master() {
    local host=$1
    local pod_cidr="$POD_CIDR"
    
    log "Initializing Kubernetes master on $host..."
    
    remote_exec $host "
        # Check if cluster is already initialized (idempotent)
        if [ ! -f /etc/kubernetes/admin.conf ]; then
            echo 'Initializing Kubernetes cluster...'
            kubeadm init --pod-network-cidr=$pod_cidr --apiserver-advertise-address=$host --control-plane-endpoint=$host:6443 --upload-certs
        else
            echo 'Kubernetes cluster already initialized'
        fi
        
        # Setup kubectl for ubuntu user (idempotent)
        mkdir -p /home/ubuntu/.kube
        if [ ! -f /home/ubuntu/.kube/config ]; then
            cp /etc/kubernetes/admin.conf /home/ubuntu/.kube/config
            chown ubuntu:ubuntu /home/ubuntu/.kube/config
        fi
        
        # Generate join command for worker nodes (always refresh)
        kubeadm token create --print-join-command > /tmp/kubeadm-join-command.txt
    "
    
    # Copy kubeconfig and join command locally (idempotent)
    local scp_opts="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR"
    
    log "Copying kubeconfig from master node..."
    if scp $scp_opts -i $SSH_KEY $SSH_USER@$host:/etc/kubernetes/admin.conf ./kubeconfig 2>/dev/null; then
        log "✓ kubeconfig successfully copied to ./kubeconfig"
        chmod 600 ./kubeconfig
    else
        warn "✗ Failed to copy kubeconfig, attempting alternative method..."
        # Alternative method: get kubeconfig content via SSH
        remote_exec $host "cat /etc/kubernetes/admin.conf" > ./kubeconfig
        if [ -s ./kubeconfig ]; then
            log "✓ kubeconfig successfully retrieved via SSH"
            chmod 600 ./kubeconfig
        else
            error "Failed to retrieve kubeconfig. Please check SSH connectivity and permissions."
        fi
    fi
    
    log "Copying join command..."
    if scp $scp_opts -i $SSH_KEY $SSH_USER@$host:/tmp/kubeadm-join-command.txt ./join-command.txt 2>/dev/null; then
        log "✓ join-command.txt successfully copied"
    else
        warn "✗ Failed to copy join command via scp, attempting alternative method..."
        remote_exec $host "cat /tmp/kubeadm-join-command.txt" > ./join-command.txt
        if [ -s ./join-command.txt ]; then
            log "✓ join-command.txt successfully retrieved via SSH"
        else
            warn "Failed to retrieve join command. Worker nodes may need manual joining."
        fi
    fi
    
    log "Master node setup completed"
}

# Install CNI (Flannel)
install_cni() {
    local host=$1
    
    log "Installing Flannel CNI on master..."
    
    remote_exec $host "
        export KUBECONFIG=/etc/kubernetes/admin.conf
        
        # Check if Flannel namespace exists and has pods
        if kubectl get namespace kube-flannel &>/dev/null && kubectl get pods -n kube-flannel --no-headers 2>/dev/null | grep -q .; then
            echo 'Flannel CNI already installed and running'
            kubectl get pods -n kube-flannel -o wide
        else
            echo 'Installing Flannel CNI...'
            kubectl apply -f https://github.com/flannel-io/flannel/releases/latest/download/kube-flannel.yml
            
            echo 'Waiting for Flannel pods to start...'
            sleep 30
            kubectl get pods -n kube-flannel -o wide
            
            # Wait for Flannel to be ready
            echo 'Waiting for Flannel to be ready (up to 2 minutes)...'
            timeout 120 bash -c '
                while true; do
                    ready_pods=\$(kubectl get pods -n kube-flannel --no-headers 2>/dev/null | grep -c \"Running\" || echo 0)
                    total_pods=\$(kubectl get pods -n kube-flannel --no-headers 2>/dev/null | wc -l || echo 0)
                    if [ \$total_pods -gt 0 ] && [ \$ready_pods -eq \$total_pods ]; then
                        echo \"All Flannel pods are ready (\$ready_pods/\$total_pods)\"
                        break
                    fi
                    echo \"Waiting for Flannel pods: \$ready_pods/\$total_pods ready\"
                    sleep 10
                done
            ' || echo 'Timeout waiting for Flannel pods, but continuing...'
        fi
    "
    
    log "CNI installation completed"
}

# Join worker node to cluster
join_worker() {
    local host=$1
    local hostname=$2
    
    log "Joining worker node $hostname ($host) to cluster..."
    
    # Check if node is already joined (idempotent)
    remote_exec $host "
        if [ -f /etc/kubernetes/kubelet.conf ]; then
            echo 'Node $hostname already joined to cluster'
        else
            if [ ! -f '/tmp/kubeadm-join-command.txt' ]; then
                echo 'Join command not found, copying from controller...'
            fi
            # Execute join command
            if [ -f '/tmp/kubeadm-join-command.txt' ]; then
                bash /tmp/kubeadm-join-command.txt
            else
                echo 'Warning: Could not join node - join command missing'
            fi
        fi
    "
    
    # Copy join command to worker node
    if [ -f "./join-command.txt" ]; then
        local scp_opts="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR"
        scp $scp_opts -i $SSH_KEY ./join-command.txt $SSH_USER@$host:/tmp/kubeadm-join-command.txt 2>/dev/null || true
    fi
    
    log "Worker node $hostname setup completed"
}

# Verify cluster status
verify_cluster() {
    local host=$1
    
    log "Verifying cluster status..."
    
    remote_exec $host "
        export KUBECONFIG=/etc/kubernetes/admin.conf
        echo '=== Node Status ==='
        kubectl get nodes -o wide
        echo ''
        echo '=== All Pods Status ==='
        kubectl get pods -A -o wide
        echo ''
        echo '=== Flannel Pods Status ==='
        kubectl get pods -n kube-flannel -o wide
        echo ''
        echo '=== Node Conditions ==='
        kubectl get nodes -o jsonpath='{range .items[*]}{.metadata.name}{\"\\t\"}{.status.conditions[?(@.type==\"Ready\")].status}{\"\\n\"}{end}'
        echo ''
        
        # Check if all nodes are Ready
        not_ready_nodes=\$(kubectl get nodes --no-headers | grep -v ' Ready ' | wc -l)
        if [ \$not_ready_nodes -gt 0 ]; then
            echo '⚠️  WARNING: Some nodes are not Ready. This might be due to CNI issues.'
            echo 'If nodes remain NotReady after setup, run this manual fix:'
            echo '  kubectl apply -f https://github.com/flannel-io/flannel/releases/latest/download/kube-flannel.yml'
            echo '  kubectl get pods -n kube-flannel -w  # Wait for pods to be Running'
            echo '  kubectl get nodes  # Verify nodes are Ready'
        else
            echo '✅ All nodes are Ready! Kubernetes cluster is fully operational.'
        fi
    "
    
    log "Waiting for nodes to become Ready (this may take a few minutes)..."
    remote_exec $host "
        export KUBECONFIG=/etc/kubernetes/admin.conf
        timeout 300 bash -c '
            while true; do
                ready_count=\$(kubectl get nodes --no-headers | grep -c \" Ready \")
                total_count=\$(kubectl get nodes --no-headers | wc -l)
                echo \"Ready nodes: \$ready_count/\$total_count\"
                if [ \"\$ready_count\" -eq \"\$total_count\" ] && [ \"\$total_count\" -gt 0 ]; then
                    echo \"All nodes are Ready!\"
                    break
                fi
                sleep 10
            done
        ' || echo 'Timeout waiting for nodes to become Ready. This is normal for initial setup.'
        
        echo ''
        echo '=== Final Cluster Status ==='
        kubectl get nodes
        kubectl get pods -A | grep -E '(NAME|kube-system|kube-flannel)'
    "
}

# Check disk space on VMs
check_disk_space() {
    local host=$1
    local hostname=$2
    
    log "Checking disk space on $hostname ($host)..."
    
    remote_exec $host "
        # Show disk usage
        echo 'Disk usage:'
        df -h /
        
        # Check if we have enough space (at least 2GB free)
        available=\$(df / | awk 'NR==2 {print \$4}')
        if [ \$available -lt 2097152 ]; then
            echo 'WARNING: Less than 2GB available disk space'
            echo 'Attempting to free up space...'
            
            # Aggressive cleanup
            apt-get clean
            apt-get autoclean
            apt-get autoremove --purge -y || true
            
            # Clear logs
            journalctl --vacuum-time=1d || true
            
            # Clear temp files
            find /tmp -type f -atime +7 -delete || true
            find /var/tmp -type f -atime +7 -delete || true
            
            # Clear apt cache completely
            rm -rf /var/cache/apt/archives/*.deb || true
            
            echo 'After cleanup:'
            df -h /
        else
            echo 'Disk space OK'
        fi
    "
}

# Check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if SSH key exists
    if [ ! -f "$SSH_KEY" ]; then
        warn "SSH key not found at $SSH_KEY"
        log "Generating SSH key pair..."
        ssh-keygen -t rsa -b 2048 -f "$SSH_KEY" -N "" -q
        log "SSH key generated. You may need to copy it to the VMs:"
        log "ssh-copy-id -i ${SSH_KEY}.pub $SSH_USER@$MASTER_IP"
        log "ssh-copy-id -i ${SSH_KEY}.pub $SSH_USER@$NODE1_IP"
        log "ssh-copy-id -i ${SSH_KEY}.pub $SSH_USER@$NODE2_IP"
    fi
    
    # Check if required commands are available
    for cmd in ssh scp; do
        if ! command -v $cmd &> /dev/null; then
            error "$cmd command not found. Please install OpenSSH client."
        fi
    done
    
    # Install sshpass if not available (for automatic SSH key setup)
    if ! command -v sshpass &> /dev/null; then
        log "Installing sshpass for automatic SSH key setup..."
        if command -v apt-get &> /dev/null; then
            apt-get update && apt-get install -y sshpass
        else
            warn "sshpass not available and cannot be installed automatically."
        fi
    fi
    
    log "Prerequisites check completed"
}

# Main execution
main() {
    log "Starting Kubernetes cluster setup..."
    
    # Check prerequisites
    check_prerequisites
    
    # Clear SSH host keys to avoid conflicts from VM recreation
    clear_ssh_host_keys
    
    # Display cluster configuration
    log "Kubernetes cluster configuration:"
    log "  Master VM: $MASTER_VM ($(get_vm_ip $MASTER_VM))"
    log "  Worker VMs: ${WORKER_VMS[*]}"
    for worker_vm in "${WORKER_VMS[@]}"; do
        log "    VM $worker_vm ($(get_vm_ip $worker_vm))"
    done
    log "  Total active VMs: ${#ACTIVE_VMS[@]}"
    
    # Check VM status for all active VMs
    log "Checking VM status on Proxmox..."
    for vm_id in "${ACTIVE_VMS[@]}"; do
        local vm_name=$(get_vm_name $vm_id)
        if qm status $vm_id &>/dev/null; then
            local status=$(qm status $vm_id | grep -o 'status: [^,]*' | cut -d' ' -f2)
            log "VM $vm_id ($vm_name) status: $status"
            if [ "$status" != "running" ]; then
                warn "VM $vm_id is not running. Starting VM..."
                qm start $vm_id || warn "Failed to start VM $vm_id"
                sleep 10
            fi
        else
            error "VM $vm_id ($vm_name) does not exist. Please create VMs first using 01-vm-creation/create-vms.sh"
        fi
    done
    
    # Wait for VMs to be fully ready
    log "Waiting 30 seconds for VMs to be fully ready..."
    sleep 30
    
    # Test SSH connectivity to all active VMs
    for vm_id in "${ACTIVE_VMS[@]}"; do
        local vm_ip=$(get_vm_ip $vm_id)
        local vm_name=$(get_vm_name $vm_id)
        log "Testing SSH to VM $vm_id ($vm_name) at $vm_ip..."
        test_ssh $vm_ip
    done
    
    # Check disk space on all active nodes
    log "Phase 0: Checking and cleaning up disk space..."
    for vm_id in "${ACTIVE_VMS[@]}"; do
        local vm_ip=$(get_vm_ip $vm_id)
        local vm_name=$(get_vm_name $vm_id)
        check_disk_space $vm_ip $vm_name
    done
    
    # Setup common components on all active nodes
    log "Phase 1: Setting up common components..."
    for vm_id in "${ACTIVE_VMS[@]}"; do
        local vm_ip=$(get_vm_ip $vm_id)
        local vm_name=$(get_vm_name $vm_id)
        setup_common $vm_ip $vm_name
    done
    
    # Initialize master node
    log "Phase 2: Initializing master node..."
    local master_ip=$(get_vm_ip $MASTER_VM)
    setup_master $master_ip
    
    # Install CNI
    log "Phase 3: Installing CNI..."
    sleep 30  # Wait for master to be ready
    install_cni $master_ip
    
    # Join worker nodes
    log "Phase 4: Joining worker nodes..."
    sleep 60  # Wait for CNI to be ready
    
    if [ ${#WORKER_VMS[@]} -eq 0 ]; then
        log "No worker nodes to join (single-node cluster)"
    else
        # Copy join command to all worker nodes first
        if [ -f "./join-command.txt" ]; then
            log "Copying join command to worker nodes..."
            local scp_opts="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR"
            for worker_vm in "${WORKER_VMS[@]}"; do
                local worker_ip=$(get_vm_ip $worker_vm)
                scp $scp_opts -i $SSH_KEY ./join-command.txt $SSH_USER@$worker_ip:/tmp/kubeadm-join-command.txt 2>/dev/null || true
            done
        fi
        
        # Join each worker node
        for worker_vm in "${WORKER_VMS[@]}"; do
            local worker_ip=$(get_vm_ip $worker_vm)
            local worker_name=$(get_vm_name $worker_vm)
            join_worker $worker_ip $worker_name
            sleep 30  # Wait between joins
        done
    fi
    
    # Verify cluster
    log "Phase 5: Verifying cluster..."
    sleep 60  # Wait for nodes to be ready
    verify_cluster $master_ip
    
    log "Kubernetes cluster setup completed successfully!"
    
    # Verify kubeconfig file exists and provide usage instructions
    if [ -f "./kubeconfig" ] && [ -s "./kubeconfig" ]; then
        log "✓ Kubeconfig saved to ./kubeconfig"
        
        # Check if kubectl is available on Proxmox host
        if command -v kubectl &> /dev/null; then
            log ""
            log "kubectl is available on this host. Usage:"
            log "  export KUBECONFIG=\$PWD/kubeconfig"
            log "  kubectl get nodes"
            log "  kubectl get pods -A"
        else
            log ""
            log "kubectl is not installed on this Proxmox host."
            log "Options:"
            log "  1. Install kubectl on Proxmox host (RECOMMENDED):"
            log "     curl -LO \"https://dl.k8s.io/release/\$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl\""
            log "     chmod +x kubectl && sudo mv kubectl /usr/local/bin/"
            log "     export KUBECONFIG=\$PWD/kubeconfig"
            log "     kubectl get nodes"
            log ""
            log "  2. Use kubectl on master node via SSH:"
            log "     ssh -i /root/.ssh/id_rsa ubuntu@$(get_vm_ip $MASTER_VM) 'sudo kubectl get nodes'"
            log ""
            log "  3. Use the cluster management script:"
            log "     ./setup-k8s-cluster.sh status"
        fi
    else
        warn "✗ Kubeconfig file is missing or empty!"
        log "Manual kubeconfig retrieval:"
        log "  ssh ubuntu@$(get_vm_ip $MASTER_VM) 'sudo cat /etc/kubernetes/admin.conf' > ./kubeconfig"
        log "  chmod 600 ./kubeconfig"
    fi
}

# Cluster management functions
cluster_status() {
    log "Checking Kubernetes cluster status..."
    local master_ip=$(get_vm_ip $(get_master_vm))
    
    if [ -z "$master_ip" ]; then
        error "No master VM found or master VM is skipped"
    fi
    
    log "Connecting to master node at $master_ip..."
    remote_exec $master_ip "
        export KUBECONFIG=/etc/kubernetes/admin.conf
        echo '=== Cluster Info ==='
        kubectl cluster-info
        echo ''
        echo '=== Node Status ==='
        kubectl get nodes -o wide
        echo ''
        echo '=== Pod Status ==='
        kubectl get pods -A -o wide
        echo ''
        echo '=== Service Status ==='
        kubectl get svc -A
    "
}

cluster_logs() {
    log "Fetching cluster logs..."
    local master_ip=$(get_vm_ip $(get_master_vm))
    
    if [ -z "$master_ip" ]; then
        error "No master VM found or master VM is skipped"
    fi
    
    log "Fetching logs from master node at $master_ip..."
    remote_exec $master_ip "
        echo '=== kubelet logs (last 50 lines) ==='
        journalctl -u kubelet -n 50 --no-pager
        echo ''
        echo '=== containerd logs (last 20 lines) ==='
        journalctl -u containerd -n 20 --no-pager
    "
}

show_usage() {
    echo "Usage: $0 [command]"
    echo ""
    echo "Commands:"
    echo "  (no args)  - Setup Kubernetes cluster (default)"
    echo "  status     - Show cluster status"
    echo "  logs       - Show cluster logs"
    echo "  help       - Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0              # Setup cluster"
    echo "  $0 status       # Check cluster status"
    echo "  $0 logs         # View logs"
}

# Parse command line arguments
case "${1:-}" in
    "status")
        cluster_status
        exit 0
        ;;
    "logs")
        cluster_logs
        exit 0
        ;;
    "help"|"--help"|"-h")
        show_usage
        exit 0
        ;;
    "")
        # Default: run main setup
        ;;
    *)
        echo "Unknown command: $1"
        show_usage
        exit 1
        ;;
esac

# Check if running as root (allow root in Proxmox environment)
if [[ $EUID -eq 0 ]]; then
   warn "Running as root user. Ensure SSH keys are properly configured."
fi

# Run main function
main "$@"
