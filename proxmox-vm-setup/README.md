# Proxmox VM Setup

このディレクトリには、ProxmoxでKubernetesクラスター用のVMを作成するためのAnsibleプレイブックが含まれています。

## 前提条件

- Proxmoxサーバーへのアクセス権限（root権限または管理者権限）
- Ansibleがインストールされたマシン（バージョン2.9以上）
- SSHキーがProxmoxサーバーに登録済み

## セットアップ手順

1. `vars.yml` を編集して環境に合わせて設定を行います：

```yaml
proxmox_host: "your-proxmox-host"
proxmox_user: "root@pam"
proxmox_password: "your-password"

# VMの基本設定
vm_template: "ubuntu-2204-cloudinit-template"  # 使用するテンプレート名
vm_storage: "local-lvm"    # VMを格納するストレージ
vm_network_bridge: "vmbr0" # 使用するネットワークブリッジ

# Kubernetesノード設定
master_node:
  name: "k8s-master"
  id: 100              # VM ID
  cpu: 2               # CPU数
  memory: 4096         # メモリ (MB)
  disk: "32G"          # ディスクサイズ
  ip: "192.168.1.100"  # 固定IP

worker_nodes:
  - name: "k8s-worker1"
    id: 101
    cpu: 2
    memory: 4096
    disk: "32G"
    ip: "192.168.1.101"
  - name: "k8s-worker2"
    id: 102
    cpu: 2
    memory: 4096
    disk: "32G"
    ip: "192.168.1.102"
```

2. インベントリファイルを編集します：

```ini
[proxmox]
proxmox-host ansible_host=your-proxmox-host ansible_user=root
```

3. プレイブックを実行してVMを作成：

```bash
ansible-playbook -i inventory.ini playbook.yml
```

## 作成されるVM

- Masterノード: 1台（2CPU, 4GB RAM）
- Workerノード: 2台（各2CPU, 4GB RAM）

すべてのノードには以下が設定されます：
- Ubuntu 22.04 LTS
- Cloud-initによる初期設定
- 固定IPアドレス
- SSHキーによるアクセス

## 次のステップ

VMの作成が完了したら、`k8s-on-proxmox-ansible` ディレクトリに移動して、Kubernetesクラスターのセットアップを開始してください。