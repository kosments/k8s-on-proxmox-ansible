#!/bin/bash

# Proxmox VM Creation Script
# Creates 3 VMs for Kubernetes cluster sequentially to avoid conflicts

set -e

# Configuration
VM_IDS=(101 102 103)
VM_NAMES=("k8s-master" "k8s-node1" "k8s-node2")
VM_IPS=("192.168.10.101" "192.168.10.102" "192.168.10.103")
VM_MEMORY=2048
VM_CORES=2
VM_STORAGE="local-lvm"
BRIDGE="vmbr0"
GATEWAY="192.168.10.1"
NAMESERVER="8.8.8.8"
SSH_USER="ubuntu"
SSH_PASSWORD="ubuntu"
CLOUD_IMAGE_URL="https://cloud-images.ubuntu.com/releases/22.04/release/ubuntu-22.04-server-cloudimg-amd64.img"
CLOUD_IMAGE_PATH="/var/lib/vz/template/iso/ubuntu-22.04-server-cloudimg-amd64.img"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

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

# Check if running on Proxmox
check_proxmox() {
    if ! command -v qm &> /dev/null; then
        error "This script must be run on a Proxmox VE host (qm command not found)"
    fi
    
    if ! command -v pvesm &> /dev/null; then
        error "This script must be run on a Proxmox VE host (pvesm command not found)"
    fi
    
    log "Proxmox VE environment detected"
}

# Download cloud image if not exists
download_cloud_image() {
    log "Checking Ubuntu cloud image..."
    
    if [ ! -f "$CLOUD_IMAGE_PATH" ]; then
        log "Downloading Ubuntu 22.04 cloud image..."
        wget -O "$CLOUD_IMAGE_PATH" "$CLOUD_IMAGE_URL"
        chmod 644 "$CLOUD_IMAGE_PATH"
        log "Cloud image downloaded successfully"
    else
        log "Cloud image already exists"
    fi
}

# Generate SSH key if not exists
setup_ssh_key() {
    if [ ! -f "/root/.ssh/id_rsa" ]; then
        log "Generating SSH key pair..."
        ssh-keygen -t rsa -b 2048 -f "/root/.ssh/id_rsa" -N "" -q
        log "SSH key generated"
    else
        log "SSH key already exists"
    fi
}

# Stop and destroy VM if exists
cleanup_vm() {
    local vm_id=$1
    local vm_name=$2
    
    log "Checking if VM $vm_id ($vm_name) exists..."
    
    if qm status $vm_id &>/dev/null; then
        log "VM $vm_id exists, cleaning up..."
        
        # Stop VM if running
        if qm status $vm_id | grep -q "running"; then
            log "Stopping VM $vm_id..."
            qm stop $vm_id
            sleep 5
        fi
        
        # Destroy VM
        log "Destroying VM $vm_id..."
        qm destroy $vm_id
        sleep 2
    else
        log "VM $vm_id does not exist, skipping cleanup"
    fi
}

# Create a single VM
create_vm() {
    local vm_id=$1
    local vm_name=$2
    local vm_ip=$3
    
    log "Creating VM $vm_id ($vm_name) with IP $vm_ip..."
    
    # Create VM
    log "Creating VM $vm_id..."
    qm create $vm_id \
        --name $vm_name \
        --memory $VM_MEMORY \
        --cores $VM_CORES \
        --net0 virtio,bridge=$BRIDGE \
        --ostype l26
    
    # Import disk
    log "Importing disk for VM $vm_id..."
    qm importdisk $vm_id "$CLOUD_IMAGE_PATH" $VM_STORAGE
    
    # Configure VM
    log "Configuring VM $vm_id..."
    qm set $vm_id \
        --scsihw virtio-scsi-pci \
        --scsi0 ${VM_STORAGE}:vm-${vm_id}-disk-0 \
        --boot c \
        --bootdisk scsi0 \
        --ide2 ${VM_STORAGE}:cloudinit \
        --serial0 socket \
        --vga serial0 \
        --ciuser $SSH_USER \
        --cipassword $SSH_PASSWORD \
        --sshkeys /root/.ssh/id_rsa.pub \
        --ipconfig0 ip=${vm_ip}/24,gw=$GATEWAY \
        --nameserver $NAMESERVER
    
    # Start VM
    log "Starting VM $vm_id..."
    qm start $vm_id
    
    # Wait for VM to be accessible
    log "Waiting for VM $vm_id to be ready..."
    local max_attempts=30
    local attempt=1
    
    while [ $attempt -le $max_attempts ]; do
        log "Attempt $attempt/$max_attempts: Testing SSH connectivity to $vm_ip..."
        
        if timeout 10 ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o PasswordAuthentication=no $SSH_USER@$vm_ip "echo 'SSH OK'" &>/dev/null; then
            log "VM $vm_id ($vm_name) is ready and accessible via SSH!"
            return 0
        fi
        
        log "VM not ready yet, waiting 10 seconds..."
        sleep 10
        ((attempt++))
    done
    
    warn "VM $vm_id may not be fully ready, but continuing..."
    return 0
}

# Verify all VMs are accessible
verify_vms() {
    log "Verifying all VMs are accessible..."
    
    for i in "${!VM_IDS[@]}"; do
        local vm_id=${VM_IDS[$i]}
        local vm_name=${VM_NAMES[$i]}
        local vm_ip=${VM_IPS[$i]}
        
        log "Testing VM $vm_id ($vm_name) at $vm_ip..."
        
        if timeout 10 ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o PasswordAuthentication=no $SSH_USER@$vm_ip "echo 'SSH OK'" &>/dev/null; then
            log "✓ VM $vm_id ($vm_name): SSH OK"
        else
            warn "✗ VM $vm_id ($vm_name): SSH FAILED"
        fi
    done
}

# Main execution
main() {
    log "Starting Proxmox VM creation for Kubernetes cluster..."
    
    # Check environment
    check_proxmox
    
    # Setup prerequisites
    download_cloud_image
    setup_ssh_key
    
    # Clean up existing VMs
    log "Phase 1: Cleaning up existing VMs..."
    for i in "${!VM_IDS[@]}"; do
        cleanup_vm ${VM_IDS[$i]} ${VM_NAMES[$i]}
    done
    
    log "Waiting 10 seconds for cleanup to complete..."
    sleep 10
    
    # Create VMs sequentially
    log "Phase 2: Creating VMs sequentially..."
    for i in "${!VM_IDS[@]}"; do
        create_vm ${VM_IDS[$i]} ${VM_NAMES[$i]} ${VM_IPS[$i]}
        log "Waiting 5 seconds before creating next VM..."
        sleep 5
    done
    
    # Verify all VMs
    log "Phase 3: Verifying VM accessibility..."
    sleep 30  # Give VMs time to fully boot
    verify_vms
    
    log "VM creation completed successfully!"
    log ""
    log "Summary:"
    for i in "${!VM_IDS[@]}"; do
        log "  ${VM_NAMES[$i]} (ID: ${VM_IDS[$i]}) - IP: ${VM_IPS[$i]}"
    done
    log ""
    log "You can now proceed with Kubernetes cluster setup:"
    log "  cd ../k8s-setup"
    log "  ./setup-k8s-cluster.sh"
}

# Run main function
main "$@"
