#!/bin/bash

# SSH接続問題の修復スクリプト

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
}

# VM IPs
VMS=("192.168.10.101" "192.168.10.102" "192.168.10.103")
VM_IDS=(101 102 103)

log "Starting SSH connection troubleshooting..."

# 1. Clear old host keys
log "Step 1: Clearing old SSH host keys..."
for ip in "${VMS[@]}"; do
    log "Removing host key for $ip"
    ssh-keygen -f "/root/.ssh/known_hosts" -R "$ip" 2>/dev/null || true
done

# 2. Check VM status
log "Step 2: Checking VM status..."
for i in "${!VM_IDS[@]}"; do
    vm_id=${VM_IDS[$i]}
    ip=${VMS[$i]}
    
    log "Checking VM $vm_id ($ip)..."
    
    # Check if VM exists and is running
    vm_status=$(qm status $vm_id 2>/dev/null || echo "not found")
    log "VM $vm_id status: $vm_status"
    
    if [[ "$vm_status" == *"stopped"* ]]; then
        warn "VM $vm_id is stopped. Starting..."
        qm start $vm_id
        log "Waiting 30 seconds for VM to boot..."
        sleep 30
    elif [[ "$vm_status" == "not found" ]]; then
        error "VM $vm_id does not exist!"
        continue
    fi
done

# 3. Test SSH connectivity
log "Step 3: Testing SSH connectivity..."
for ip in "${VMS[@]}"; do
    log "Testing SSH to $ip..."
    
    # Test SSH connection with timeout
    if timeout 10 ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null ubuntu@$ip "echo 'SSH OK'" 2>/dev/null; then
        log "SSH to $ip: SUCCESS"
    else
        warn "SSH to $ip: FAILED"
        
        # Check if port 22 is open
        if timeout 5 nc -z $ip 22 2>/dev/null; then
            log "Port 22 is open on $ip, but SSH authentication failed"
        else
            warn "Port 22 is not reachable on $ip"
            
            # Try to check VM console
            log "Checking VM console for SSH service status..."
        fi
    fi
done

# 4. Show SSH troubleshooting commands
log "Step 4: Manual troubleshooting commands:"
echo "
If SSH still fails, try these commands:

1. Check VM console:
   qm monitor 102
   info network

2. Reset VM network (if needed):
   qm stop 102
   qm start 102

3. Connect via VNC to check SSH service:
   - Open Proxmox web interface
   - Go to VM 102 > Console
   - Login and run: sudo systemctl status ssh

4. Test SSH without key:
   ssh -o PasswordAuthentication=yes ubuntu@192.168.10.102

5. Check VM cloud-init logs:
   qm monitor 102
   info status
"

log "SSH troubleshooting completed!"
