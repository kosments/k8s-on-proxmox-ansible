#!/bin/bash

# =============================================================================
# Kubernetes Cluster Configuration File
# =============================================================================
# 
# このファイルは、VM作成とKubernetesセットアップの共通設定を管理します。
# 
# 【設定項目】
# - VM構成（ID、名前、IP、役割）
# - スキップフラグ（個別VM の作成・セットアップをスキップ）
# - VM仕様（メモリ、CPU、ディスク）
# - ネットワーク設定
# - Kubernetes設定（バージョン、ネットワークCIDR）
# - SSH設定
# 
# 【カスタマイズ方法】
# このファイルを編集することで、以下が可能です：
# - VM数の増減
# - IPアドレス範囲の変更
# - VM仕様の調整
# - 個別VMのスキップ設定
# 
# 【注意事項】
# - VM_IDS、VM_NAMES、VM_IPS、VM_ROLESの要素数は一致させてください
# - IPアドレスは利用可能な範囲を指定してください
# - スキップフラグはtrue/falseで指定してください
# 
# =============================================================================

# VM Configuration
VM_IDS=(101 102 103 104)
VM_NAMES=("k8s-master" "k8s-node1" "k8s-node2" "k8s-node3")
VM_IPS=("192.168.10.101" "192.168.10.102" "192.168.10.103" "192.168.10.104")
VM_ROLES=("master" "worker" "worker" "worker")

# Skip flags - set to true to skip VM creation/setup
SKIP_VM_101=false
SKIP_VM_102=false   # VM 102 is now active
SKIP_VM_103=false
SKIP_VM_104=true    # VM 104 is temporarily skipped

# VM Specifications
VM_MEMORY=4096  # 4GB RAM
VM_CORES=2
VM_DISK_SIZE="100G"
VM_STORAGE="local-lvm"
BRIDGE="vmbr0"

# Network Configuration
SSH_USER="ubuntu"
SSH_KEY_PATH="/root/.ssh/id_rsa"

# Proxmox Configuration
CLOUD_IMAGE_URL="https://cloud-images.ubuntu.com/jammy/current/jammy-server-cloudimg-amd64.img"
CLOUD_IMAGE_PATH="/var/lib/vz/template/iso/ubuntu-22.04-cloudimg-amd64.img"

# Kubernetes Configuration
K8S_VERSION="1.28"
POD_NETWORK_CIDR="10.244.0.0/16"
CONTAINERD_VERSION="1.7.2"

# Helper function to check if VM should be skipped
should_skip_vm() {
    local vm_id=$1
    case $vm_id in
        101) [ "$SKIP_VM_101" = true ] && return 0 ;;
        102) [ "$SKIP_VM_102" = true ] && return 0 ;;
        103) [ "$SKIP_VM_103" = true ] && return 0 ;;
        104) [ "$SKIP_VM_104" = true ] && return 0 ;;
    esac
    return 1
}

# Helper function to get VM role
get_vm_role() {
    local vm_id=$1
    for i in "${!VM_IDS[@]}"; do
        if [ "${VM_IDS[$i]}" = "$vm_id" ]; then
            echo "${VM_ROLES[$i]}"
            return 0
        fi
    done
    echo "unknown"
}

# Helper function to get VM name
get_vm_name() {
    local vm_id=$1
    for i in "${!VM_IDS[@]}"; do
        if [ "${VM_IDS[$i]}" = "$vm_id" ]; then
            echo "${VM_NAMES[$i]}"
            return 0
        fi
    done
    echo "unknown"
}

# Helper function to get VM IP
get_vm_ip() {
    local vm_id=$1
    for i in "${!VM_IDS[@]}"; do
        if [ "${VM_IDS[$i]}" = "$vm_id" ]; then
            echo "${VM_IPS[$i]}"
            return 0
        fi
    done
    echo ""
}

# Get active (non-skipped) VMs
get_active_vms() {
    local active_vms=()
    for i in "${!VM_IDS[@]}"; do
        local vm_id=${VM_IDS[$i]}
        if ! should_skip_vm $vm_id; then
            active_vms+=($vm_id)
        fi
    done
    echo "${active_vms[@]}"
}

# Get master VM ID
get_master_vm() {
    for i in "${!VM_IDS[@]}"; do
        local vm_id=${VM_IDS[$i]}
        if [ "${VM_ROLES[$i]}" = "master" ] && ! should_skip_vm $vm_id; then
            echo "$vm_id"
            return 0
        fi
    done
    echo ""
}

# Get worker VM IDs
get_worker_vms() {
    local worker_vms=()
    for i in "${!VM_IDS[@]}"; do
        local vm_id=${VM_IDS[$i]}
        if [ "${VM_ROLES[$i]}" = "worker" ] && ! should_skip_vm $vm_id; then
            worker_vms+=($vm_id)
        fi
    done
    echo "${worker_vms[@]}"
}
