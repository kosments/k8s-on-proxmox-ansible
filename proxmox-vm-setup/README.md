# Proxmox VM Setup

このディレクトリには、ProxmoxでKubernetesクラスター用のVMを作成するためのツールが含まれています。

## 前提条件

- Proxmoxサーバーへのアクセス権限（root権限または管理者権限）
- ProxmoxホストでSSHキーが設定済み
- 十分なストレージ容量（VM 3台 × 100GB + 50GB バッファ = 約350GB）

## 推奨セットアップ手順（シェルスクリプト利用）

### 基本的な使用方法

```bash
# スクリプトに実行権限を付与
chmod +x create-vms.sh

# 全VM作成（ファイアウォール設定込み）
./create-vms.sh

# ヘルプ表示
./create-vms.sh --help
```

### 高度な使用方法

```bash
# 既存VMにファイアウォール設定のみ適用
./create-vms.sh firewall

# 既存VM削除後、新規作成
qm stop 101 102 103
qm destroy 101 102 103
./create-vms.sh
```

### 作成されるVM仕様

| 項目 | 値 |
|------|-----|
| VM数 | 3台 (Master×1, Worker×2) |
| メモリ | 4GB RAM / VM |
| CPU | 2コア / VM |
| ディスク | 100GB / VM |
| OS | Ubuntu 22.04 LTS |
| ネットワーク | 192.168.10.101-103 |

### ファイアウォール設定

各VMには以下のファイアウォール設定が自動適用されます：
- SSH (ポート22) の全許可
- UFWファイアウォールの有効化

## セットアップ手順（ansible利用）

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

## トラブルシューティング

### SSH接続の問題
```bash
# SSH接続テスト
ssh ubuntu@192.168.10.101
ssh ubuntu@192.168.10.102
ssh ubuntu@192.168.10.103

# ポート確認
nc -zv 192.168.10.101 22
nc -zv 192.168.10.102 22
nc -zv 192.168.10.103 22
```

### ファイアウォールの問題
```bash
# 既存VMにファイアウォール設定を適用
./create-vms.sh firewall
```

### VM状態確認
```bash
# VM状態確認
qm status 101
qm status 102  
qm status 103

# VM再起動
qm stop <vm_id>
qm start <vm_id>
```

## 次のステップ

VMの作成が完了したら、Kubernetesクラスターのセットアップを開始してください：

```bash
cd ../k8s-setup
./setup-k8s-cluster.sh
```

## 作成されるVM詳細（Ansible使用時）

- Masterノード: 1台（2CPU, 4GB RAM）
- Workerノード: 2台（各2CPU, 4GB RAM）

すべてのノードには以下が設定されます：
- Ubuntu 22.04 LTS
- Cloud-initによる初期設定
- 固定IPアドレス
- SSHキーによるアクセス