#!/bin/bash
# =============================================================================
# Kubernetes Cluster Configuration
# =============================================================================
#
# このファイルは共通設定を管理します。
# スクリプトから source されて使用されます。
#
# =============================================================================

# VM構成
TEMPLATE_ID=9000
VM_IDS=(201 202 203)
VM_NAMES=("k8s-master" "k8s-worker1" "k8s-worker2")
VM_IPS=("192.168.10.201" "192.168.10.202" "192.168.10.203")

# ネットワーク
GATEWAY="192.168.10.1"
NAMESERVER="8.8.8.8"

# SSH設定
SSH_USER="ubuntu"
SSH_PASSWORD="ubuntu"
SSH_KEY_PATH="/root/.ssh/id_rsa"

# VM仕様
VM_MEMORY=4096  # 4GB
VM_CORES=2
VM_DISK_SIZE="50G"

# Proxmox設定
STORAGE="local-lvm"
BRIDGE="vmbr0"
