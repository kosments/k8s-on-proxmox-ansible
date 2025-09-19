#!/bin/bash

# Kubernetes Cluster Setup Script
# This script sets up a 3-node Kubernetes cluster on Proxmox VMs

set -e

# Configuration
MASTER_IP="192.168.10.101"
NODE1_IP="192.168.10.102"
NODE2_IP="192.168.10.103"
SSH_USER="ubuntu"
SSH_KEY="/root/.ssh/id_rsa"
K8S_VERSION="1.28.2-1.1"
POD_CIDR="10.244.0.0/16"

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

# Clear SSH host keys for all VMs (to avoid host key conflicts on VM recreation)
clear_ssh_host_keys() {
    log "Clearing SSH host keys to avoid conflicts..."
    
    # Remove host keys for all VM IPs
    for ip in $MASTER_IP $NODE1_IP $NODE2_IP; do
        ssh-keygen -f "/root/.ssh/known_hosts" -R "$ip" 2>/dev/null || true
    done
    
    log "SSH host keys cleared"
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
        warn "SSH to $host: FAILED - attempting to setup SSH key..."
        setup_ssh_key $host
        
        # Wait a moment for SSH service to be ready
        sleep 5
        
        # Test again after key setup
        if ssh $ssh_opts -i $SSH_KEY $SSH_USER@$host "echo 'SSH OK'" >/dev/null 2>&1; then
            log "SSH to $host: OK (after key setup)"
            return 0
        else
            error "SSH to $host: STILL FAILED after key setup"
            return 1
        fi
    fi
}

# Setup SSH key for a host
setup_ssh_key() {
    local host=$1
    log "Setting up SSH key for $host..."
    
    # Try password authentication to copy the key
    if command -v sshpass &> /dev/null; then
        log "Using sshpass to copy SSH key..."
        sshpass -p "ubuntu" ssh-copy-id -o StrictHostKeyChecking=no -i ${SSH_KEY}.pub $SSH_USER@$host 2>/dev/null || true
    else
        warn "sshpass not available. Manual SSH key setup may be required."
        log "Please run: ssh-copy-id -i ${SSH_KEY}.pub $SSH_USER@$host"
        log "Or ensure the VMs were created with the SSH key already installed."
    fi
}

# Execute command on remote host
remote_exec() {
    local host=$1
    local cmd=$2
    log "Executing on $host: $cmd"
    
    # Use consistent SSH options across all connections
    local ssh_opts="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR"
    
    if ssh $ssh_opts -i $SSH_KEY $SSH_USER@$host "sudo bash -c '$cmd'"; then
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
        sed -i 's/^[^#]*swap.*$/#&/' /etc/fstab || true
        
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
    
    log "Initializing Kubernetes master on $host..."
    
    remote_exec $host "
        # Check if cluster is already initialized (idempotent)
        if [ ! -f /etc/kubernetes/admin.conf ]; then
            log 'Initializing Kubernetes cluster...'
            kubeadm init --pod-network-cidr=$POD_CIDR --apiserver-advertise-address=$host --control-plane-endpoint=$host:6443 --upload-certs
        else
            log 'Kubernetes cluster already initialized'
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
    scp $scp_opts -i $SSH_KEY $SSH_USER@$host:/etc/kubernetes/admin.conf ./kubeconfig 2>/dev/null || true
    scp $scp_opts -i $SSH_KEY $SSH_USER@$host:/tmp/kubeadm-join-command.txt ./join-command.txt 2>/dev/null || true
    
    log "Master node setup completed"
}

# Install CNI (Flannel)
install_cni() {
    local host=$1
    
    log "Installing Flannel CNI on master..."
    
    remote_exec $host "
        export KUBECONFIG=/etc/kubernetes/admin.conf
        # Check if Flannel is already installed (idempotent)
        if ! kubectl get pods -n kube-flannel &>/dev/null; then
            log 'Installing Flannel CNI...'
            kubectl apply -f https://github.com/flannel-io/flannel/releases/latest/download/kube-flannel.yml
        else
            log 'Flannel CNI already installed'
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
            log 'Node $hostname already joined to cluster'
        else
            if [ ! -f '/tmp/kubeadm-join-command.txt' ]; then
                log 'Join command not found, copying from controller...'
            fi
            # Execute join command
            if [ -f '/tmp/kubeadm-join-command.txt' ]; then
                bash /tmp/kubeadm-join-command.txt
            else
                log 'Warning: Could not join node - join command missing'
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
        kubectl get nodes
        kubectl get pods -A
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
    
    # Test SSH connectivity to all nodes
    test_ssh $MASTER_IP
    test_ssh $NODE1_IP
    test_ssh $NODE2_IP
    
    # Check disk space on all nodes
    log "Phase 0: Checking and cleaning up disk space..."
    check_disk_space $MASTER_IP "k8s-master"
    check_disk_space $NODE1_IP "k8s-node1" 
    check_disk_space $NODE2_IP "k8s-node2"
    
    # Setup common components on all nodes
    log "Phase 1: Setting up common components..."
    setup_common $MASTER_IP "k8s-master"
    setup_common $NODE1_IP "k8s-node1" 
    setup_common $NODE2_IP "k8s-node2"
    
    # Initialize master node
    log "Phase 2: Initializing master node..."
    setup_master $MASTER_IP
    
    # Install CNI
    log "Phase 3: Installing CNI..."
    sleep 30  # Wait for master to be ready
    install_cni $MASTER_IP
    
    # Join worker nodes
    log "Phase 4: Joining worker nodes..."
    sleep 60  # Wait for CNI to be ready
    
    # Copy join command to worker nodes first
    if [ -f "./join-command.txt" ]; then
        log "Copying join command to worker nodes..."
        local scp_opts="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR"
        scp $scp_opts -i $SSH_KEY ./join-command.txt $SSH_USER@$NODE1_IP:/tmp/kubeadm-join-command.txt 2>/dev/null || true
        scp $scp_opts -i $SSH_KEY ./join-command.txt $SSH_USER@$NODE2_IP:/tmp/kubeadm-join-command.txt 2>/dev/null || true
    fi
    
    join_worker $NODE1_IP "k8s-node1"
    sleep 30
    join_worker $NODE2_IP "k8s-node2"
    
    # Verify cluster
    log "Phase 5: Verifying cluster..."
    sleep 60  # Wait for nodes to be ready
    verify_cluster $MASTER_IP
    
    log "Kubernetes cluster setup completed successfully!"
    log "Kubeconfig saved to ./kubeconfig"
    log "To use kubectl: export KUBECONFIG=\$PWD/kubeconfig"
}

# Check if running as root (allow root in Proxmox environment)
if [[ $EUID -eq 0 ]]; then
   warn "Running as root user. Ensure SSH keys are properly configured."
fi

# Run main function
main "$@"
