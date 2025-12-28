# Proxmoxホストでのスクリプト実行手順

Proxmoxホスト（192.168.10.108）に直接アクセスしてスクリプトを実行する手順です。

## 方法1: Proxmox Web UIのシェルから実行

1. Proxmox Web UIにアクセス: `https://192.168.10.108:8006`
2. 左側のメニューから「Shell」を選択
3. 以下のコマンドを実行

## 方法2: 直接Proxmoxホストにログイン

Proxmoxホストのコンソールに直接アクセスできる場合：

```bash
# Proxmoxホストにログイン
# （物理コンソールまたはKVM経由）

# ディレクトリを作成
mkdir -p /root/k8s-on-proxmox-ansible/scripts
cd /root/k8s-on-proxmox-ansible/scripts
```

## スクリプトの作成

以下のコマンドでスクリプトを作成します：

### 1. recreate-master.sh の作成

```bash
cat > /root/k8s-on-proxmox-ansible/scripts/recreate-master.sh << 'SCRIPT_END'
#!/bin/bash

# =============================================================================
# マスターノード再作成スクリプト
# =============================================================================

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
if ! command -v qm &> /dev/null; then
    error "This script must be run on a Proxmox VE host (qm command not found)"
fi

# IP競合チェック関数
check_ip_in_use() {
    local ip=$1
    
    if ip neigh show | grep -q "$ip "; then
        return 0
    fi
    
    if ping -c 1 -W 1 $ip >/dev/null 2>&1; then
        return 0
    fi
    
    return 1
}

# マスターノードの設定
MASTER_VM_ID=101
MASTER_VM_NAME="k8s-master"
MASTER_VM_IP="192.168.10.111"
VM_STORAGE=${STORAGE:-"local-lvm"}
CLOUD_IMAGE_PATH="/var/lib/vz/template/iso/ubuntu-22.04-server-cloudimg-amd64.img"
CLOUD_IMAGE_URL="https://cloud-images.ubuntu.com/releases/22.04/release/ubuntu-22.04-server-cloudimg-amd64.img"

vm_exists() {
    local vm_id=$1
    if qm status $vm_id &>/dev/null; then
        return 0
    else
        return 1
    fi
}

cleanup_vm() {
    local vm_id=$1
    local vm_name=$2
    
    log "Checking if VM $vm_id ($vm_name) exists..."
    
    if vm_exists $vm_id; then
        log "VM $vm_id exists, cleaning up..."
        
        if qm status $vm_id | grep -q "running"; then
            log "Stopping VM $vm_id..."
            qm stop $vm_id
            sleep 5
        fi
        
        log "Destroying VM $vm_id..."
        qm destroy $vm_id
        sleep 2
        log "VM $vm_id destroyed"
    else
        log "VM $vm_id does not exist, skipping cleanup"
    fi
}

download_cloud_image() {
    log "Checking Ubuntu cloud image..."
    
    if [ ! -f "$CLOUD_IMAGE_PATH" ]; then
        log "Downloading Ubuntu 22.04 cloud image..."
        mkdir -p "$(dirname "$CLOUD_IMAGE_PATH")"
        wget -O "$CLOUD_IMAGE_PATH" "$CLOUD_IMAGE_URL"
        chmod 644 "$CLOUD_IMAGE_PATH"
        log "Cloud image downloaded successfully"
    else
        log "Cloud image already exists"
    fi
}

setup_ssh_key() {
    if [ ! -f "/root/.ssh/id_rsa" ]; then
        log "Generating SSH key pair..."
        ssh-keygen -t rsa -b 2048 -f "/root/.ssh/id_rsa" -N "" -q
        log "SSH key generated"
    else
        log "SSH key already exists"
    fi
}

create_vm() {
    local vm_id=$1
    local vm_name=$2
    local vm_ip=$3
    
    log "Creating VM $vm_id ($vm_name) with IP $vm_ip..."
    
    if vm_exists $vm_id; then
        log "VM $vm_id ($vm_name) already exists, skipping creation"
        return 0
    fi
    
    log "Creating VM $vm_id with ${VM_MEMORY}MB RAM, ${VM_CORES} cores..."
    qm create $vm_id \
        --name $vm_name \
        --memory $VM_MEMORY \
        --cores $VM_CORES \
        --net0 virtio,bridge=$BRIDGE \
        --ostype l26
    
    log "Importing disk for VM $vm_id..."
    qm importdisk $vm_id "$CLOUD_IMAGE_PATH" $VM_STORAGE
    
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
    
    log "Resizing disk to $VM_DISK_SIZE for VM $vm_id..."
    qm resize $vm_id scsi0 $VM_DISK_SIZE
    
    log "Starting VM $vm_id..."
    qm start $vm_id
    
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

main() {
    log "=========================================="
    log "マスターノード再作成スクリプト"
    log "=========================================="
    log ""
    log "対象VM:"
    log "  ID: $MASTER_VM_ID"
    log "  名前: $MASTER_VM_NAME"
    log "  IP: $MASTER_VM_IP"
    log ""
    
    log "=== IP競合チェック ==="
    log "IPアドレス: $MASTER_VM_IP"
    
    log "ネットワークをスキャン中..."
    ping -c 1 -W 1 $MASTER_VM_IP >/dev/null 2>&1 || true
    sleep 2
    
    log "ARPテーブルの確認:"
    if ip neigh show | grep -q "$MASTER_VM_IP "; then
        arp_entry=$(ip neigh show | grep "$MASTER_VM_IP ")
        warn "ARPエントリが見つかりました: $arp_entry"
        
        if vm_exists $MASTER_VM_ID; then
            vm_mac=$(qm config $MASTER_VM_ID | grep "net0" | grep -oP 'virtio=\K[^,]+' || echo "")
            arp_mac=$(echo "$arp_entry" | awk '{print $5}')
            
            if [ -n "$vm_mac" ] && [ -n "$arp_mac" ] && [ "$vm_mac" != "$arp_mac" ]; then
                warn "MACアドレスが一致しません - IP競合の可能性があります"
                warn "  VM MAC: $vm_mac"
                warn "  ARP MAC: $arp_mac"
            fi
        fi
    else
        log "ARPエントリが見つかりません（IPは未使用の可能性）"
    fi
    
    if check_ip_in_use $MASTER_VM_IP; then
        warn "IP $MASTER_VM_IP は使用中の可能性があります"
        warn "続行しますか？ (y/N)"
        read -n 1 -r
        echo ""
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log "操作をキャンセルしました"
            exit 0
        fi
    else
        log "IP $MASTER_VM_IP は使用されていないようです"
    fi
    log ""
    
    log "この操作は以下を実行します:"
    log "  1. 既存のVM $MASTER_VM_ID を停止・削除"
    log "  2. 新しいVM $MASTER_VM_ID を作成"
    log "  3. IPアドレス: $MASTER_VM_IP で設定"
    log ""
    read -p "続行しますか？ (y/N): " -n 1 -r
    echo ""
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log "操作をキャンセルしました"
        exit 0
    fi
    log ""
    
    download_cloud_image
    setup_ssh_key
    
    log "=== Phase 1: 既存VMのクリーンアップ ==="
    cleanup_vm $MASTER_VM_ID $MASTER_VM_NAME
    log "Waiting 10 seconds for cleanup to complete..."
    sleep 10
    
    log "=== Phase 2: 新しいVMの作成 ==="
    create_vm $MASTER_VM_ID $MASTER_VM_NAME $MASTER_VM_IP
    
    log "=== Phase 3: VM検証 ==="
    sleep 30
    
    if timeout 10 ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null $SSH_USER@$MASTER_VM_IP "echo 'SSH OK'" &>/dev/null; then
        log "✓ VM $MASTER_VM_ID ($MASTER_VM_NAME) は正常に作成され、アクセス可能です"
    else
        warn "VMは作成されましたが、SSH接続がまだ確立できていません"
    fi
    
    log ""
    log "=========================================="
    log "完了"
    log "=========================================="
}

main "$@"
SCRIPT_END

chmod +x /root/k8s-on-proxmox-ansible/scripts/recreate-master.sh
```

### 2. config.sh の確認・作成

```bash
# config.shが存在するか確認
if [ ! -f /root/k8s-on-proxmox-ansible/config.sh ]; then
    cat > /root/k8s-on-proxmox-ansible/config.sh << 'CONFIG_END'
#!/bin/bash
TEMPLATE_ID=9000
VM_IDS=(101 102 103)
VM_NAMES=("k8s-master" "k8s-worker1" "k8s-worker2")
VM_IPS=("192.168.10.111" "192.168.10.112" "192.168.10.113")
GATEWAY="192.168.10.1"
NAMESERVER="8.8.8.8"
SSH_USER="ubuntu"
SSH_PASSWORD="ubuntu"
SSH_KEY_PATH="/root/.ssh/id_rsa"
VM_MEMORY=4096
VM_CORES=2
VM_DISK_SIZE="50G"
STORAGE="local-lvm"
BRIDGE="vmbr0"
CONFIG_END
fi
```

## 実行

```bash
cd /root/k8s-on-proxmox-ansible/scripts
./recreate-master.sh
```

