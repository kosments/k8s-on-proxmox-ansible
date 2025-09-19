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

# Test SSH connectivity
test_ssh() {
    local host=$1
    log "Testing SSH connectivity to $host..."
    if ssh -o ConnectTimeout=10 -o StrictHostKeyChecking=no -i $SSH_KEY $SSH_USER@$host "echo 'SSH OK'" >/dev/null 2>&1; then
        log "SSH to $host: OK"
        return 0
    else
        warn "SSH to $host: FAILED - attempting to setup SSH key..."
        setup_ssh_key $host
        # Test again after key setup
        if ssh -o ConnectTimeout=10 -o StrictHostKeyChecking=no -i $SSH_KEY $SSH_USER@$host "echo 'SSH OK'" >/dev/null 2>&1; then
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
    ssh -o StrictHostKeyChecking=no -i $SSH_KEY $SSH_USER@$host "sudo bash -c '$cmd'"
}

# Setup common components on a node
setup_common() {
    local host=$1
    local hostname=$2
    
    log "Setting up common components on $hostname ($host)..."
    
    # Update system and set hostname
    remote_exec $host "
        hostnamectl set-hostname $hostname
        apt-get update && apt-get upgrade -y
        
        # Install required packages
        apt-get install -y apt-transport-https ca-certificates curl gnupg lsb-release
        
        # Disable swap
        swapoff -a
        sed -i '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab
        
        # Load kernel modules
        modprobe overlay
        modprobe br_netfilter
        
        # Setup kernel modules to load at boot
        cat <<EOF > /etc/modules-load.d/containerd.conf
overlay
br_netfilter
EOF

        # Setup sysctl params
        cat <<EOF > /etc/sysctl.d/99-kubernetes-cri.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF
        sysctl --system
        
        # Install containerd
        curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
        echo \"deb [arch=amd64 signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu \$(lsb_release -cs) stable\" > /etc/apt/sources.list.d/docker.list
        apt-get update
        apt-get install -y containerd.io
        
        # Configure containerd
        mkdir -p /etc/containerd
        containerd config default > /etc/containerd/config.toml
        sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
        systemctl restart containerd
        systemctl enable containerd
        
        # Add Kubernetes repository
        curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.28/deb/Release.key | gpg --dearmor -o /usr/share/keyrings/kubernetes-archive-keyring.gpg
        echo \"deb [signed-by=/usr/share/keyrings/kubernetes-archive-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.28/deb/ /\" > /etc/apt/sources.list.d/kubernetes.list
        
        # Install Kubernetes components
        apt-get update
        apt-get install -y kubelet=$K8S_VERSION kubeadm=$K8S_VERSION kubectl=$K8S_VERSION
        apt-mark hold kubelet kubeadm kubectl
        
        # Enable kubelet
        systemctl enable kubelet
    "
    
    log "Common setup completed on $hostname"
}

# Initialize master node
setup_master() {
    local host=$1
    
    log "Initializing Kubernetes master on $host..."
    
    remote_exec $host "
        # Initialize cluster
        kubeadm init --pod-network-cidr=$POD_CIDR --apiserver-advertise-address=$host --control-plane-endpoint=$host:6443 --upload-certs
        
        # Setup kubectl for ubuntu user
        mkdir -p /home/ubuntu/.kube
        cp /etc/kubernetes/admin.conf /home/ubuntu/.kube/config
        chown ubuntu:ubuntu /home/ubuntu/.kube/config
        
        # Generate join command for worker nodes
        kubeadm token create --print-join-command > /tmp/kubeadm-join-command.txt
    "
    
    # Copy kubeconfig and join command locally
    scp -o StrictHostKeyChecking=no -i $SSH_KEY $SSH_USER@$host:/etc/kubernetes/admin.conf ./kubeconfig
    scp -o StrictHostKeyChecking=no -i $SSH_KEY $SSH_USER@$host:/tmp/kubeadm-join-command.txt ./join-command.txt
    
    log "Master node initialized successfully"
}

# Install CNI (Flannel)
install_cni() {
    local host=$1
    
    log "Installing Flannel CNI on master..."
    
    remote_exec $host "
        export KUBECONFIG=/etc/kubernetes/admin.conf
        kubectl apply -f https://github.com/flannel-io/flannel/releases/latest/download/kube-flannel.yml
    "
    
    log "CNI installation completed"
}

# Join worker node to cluster
join_worker() {
    local host=$1
    local hostname=$2
    
    log "Joining worker node $hostname ($host) to cluster..."
    
    if [ ! -f "./join-command.txt" ]; then
        error "Join command file not found. Master setup might have failed."
    fi
    
    local join_cmd=$(cat ./join-command.txt)
    remote_exec $host "$join_cmd"
    
    log "Worker node $hostname joined successfully"
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
    
    # Test SSH connectivity to all nodes
    test_ssh $MASTER_IP
    test_ssh $NODE1_IP
    test_ssh $NODE2_IP
    
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
