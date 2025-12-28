#!/bin/bash

# VM状態確認スクリプト
# Proxmox上で実行してVMの状態を確認

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="$SCRIPT_DIR/../config.sh"

if [ -f "$CONFIG_FILE" ]; then
    source "$CONFIG_FILE"
else
    echo "ERROR: Configuration file not found: $CONFIG_FILE"
    exit 1
fi

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if running on Proxmox
if ! command -v qm &> /dev/null; then
    error "This script must be run on a Proxmox VE host (qm command not found)"
    exit 1
fi

echo "=========================================="
echo "VM状態確認"
echo "=========================================="
echo ""

# Check each VM
for i in "${!VM_IDS[@]}"; do
    vm_id=${VM_IDS[$i]}
    vm_name=${VM_NAMES[$i]}
    vm_ip=${VM_IPS[$i]}
    
    echo "--- VM $vm_id ($vm_name) - IP: $vm_ip ---"
    
    # Check VM status
    if qm status $vm_id &>/dev/null; then
        status=$(qm status $vm_id | awk '{print $2}')
        log "VM存在: はい"
        log "状態: $status"
        
        # Get VM config
        echo "設定:"
        qm config $vm_id | grep -E "(net0|ipconfig0)" || echo "  ネットワーク設定が見つかりません"
        
        # Check if VM is running
        if [ "$status" = "running" ]; then
            # Try to ping
            echo -n "  Ping: "
            if ping -c 1 -W 2 $vm_ip &>/dev/null; then
                echo -e "${GREEN}OK${NC}"
            else
                echo -e "${RED}FAILED${NC}"
            fi
            
            # Check ARP
            echo -n "  ARP: "
            if arp -n $vm_ip 2>/dev/null | grep -q "$vm_ip"; then
                arp_entry=$(arp -n $vm_ip | grep "$vm_ip")
                echo -e "${GREEN}Found${NC} - $arp_entry"
            else
                echo -e "${RED}Not found${NC}"
            fi
            
            # Try SSH
            echo -n "  SSH: "
            if timeout 5 ssh -o ConnectTimeout=3 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null $SSH_USER@$vm_ip "echo OK" &>/dev/null 2>&1; then
                echo -e "${GREEN}OK${NC}"
            else
                echo -e "${RED}FAILED${NC}"
            fi
        else
            warn "VMは停止中です"
        fi
    else
        error "VM存在: いいえ"
    fi
    echo ""
done

echo "=========================================="
echo "完了"
echo "=========================================="
