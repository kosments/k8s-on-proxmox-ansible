# k8s-on-proxmox-ansible

ProxmoxVE上にKubernetesクラスターを自動構築するためのツールセットです。

## 🚀 クイックスタート

### 必要な手順（2ステップのみ）

1. **VM作成**: `proxmox-vm-setup/create-vms.sh`
2. **Kubernetes構築**: `k8s-setup/setup-k8s-cluster.sh`

```bash
# 1. VM作成（Proxmoxホスト上で実行）
cd proxmox-vm-setup
./create-vms.sh

# 2. Kubernetesクラスター構築（Proxmoxホスト上で実行）
cd ../k8s-setup
./setup-k8s-cluster.sh
```

### 構築されるクラスター

- **Master**: 1台（VM 101）
- **Worker**: 2台（VM 103, 104）
- **VM 102**: 一時的にスキップ（設定で変更可能）
- **合計**: 3ノードクラスター

## 📁 プロジェクト構成

```
k8s-on-proxmox-ansible/
├── config.sh                    # 共通設定ファイル
├── proxmox-vm-setup/            # VM作成関連
│   ├── create-vms.sh            # VMの作成・管理
│   └── README.md                # VM作成の詳細手順
├── k8s-setup/                   # Kubernetes構築関連
│   ├── setup-k8s-cluster.sh     # Kubernetesクラスター構築
│   └── README.md                # K8s構築の詳細手順
└── README.md                    # このファイル
```

## ⚙️ 設定のカスタマイズ

`config.sh`を編集することで、VM構成やスキップ設定を変更できます：

```bash
# VM構成
VM_IDS=(101 102 103 104)
VM_NAMES=("k8s-master" "k8s-node1" "k8s-node2" "k8s-node3")
VM_IPS=("192.168.10.101" "192.168.10.102" "192.168.10.103" "192.168.10.104")

# スキップ設定
SKIP_VM_101=false  # マスターノード
SKIP_VM_102=false  # ワーカーノード1
SKIP_VM_103=false  # ワーカーノード2
SKIP_VM_104=true   # ワーカーノード3（デフォルトでスキップ）
```

## 📋 システム要件

### Proxmox VE環境
- ProxmoxVE 7.x以上
- 利用可能ストレージ: 350GB以上
- ネットワーク: 192.168.10.0/24

### 作成されるVM仕様
- **OS**: Ubuntu 22.04 LTS
- **メモリ**: 4GB/VM
- **CPU**: 2コア/VM
- **ディスク**: 100GB/VM

## 🚀 **次のステップ: 監視・サンプルアプリ・Service Mesh**

基本的なKubernetesクラスターが完成しました！以下の手順で本格的な環境を構築できます：

### 📊 **1. 監視スタック（Prometheus + Grafana）**
```bash
cd manifests/monitoring
chmod +x setup-monitoring.sh
./setup-monitoring.sh
```

**アクセス方法:**
- Grafana: `http://<node-ip>:30300` (admin/admin123)
- 人気ダッシュボード: 315, 6417, 7249, 10000

### 📝 **2. ログ集約（Grafana Loki）**
```bash
cd manifests/logging
chmod +x setup-logging.sh
./setup-logging.sh
```

**LogQLクエリ例:**
- `{namespace="default"}` - 名前空間のログ
- `{app="nginx"} |= "error"` - エラーログ
- `rate({namespace="default"}[5m])` - ログレート

### 🎯 **3. サンプルアプリケーション**
```bash
kubectl apply -f manifests/apps/sample-app.yaml
```

**アクセス方法:**
- `http://<node-ip>:30080`
- Port Forward: `kubectl port-forward -n sample-apps svc/sample-app 8080:80`

### 🕸️ **4. Service Mesh（Istio）**
```bash
cd manifests/istio
chmod +x setup-istio.sh
./setup-istio.sh
```

**主要コンポーネント:**
- Kiali: Service Mesh可視化
- Jaeger: 分散トレーシング
- Ingress Gateway: 外部アクセス

### 🔄 **5. 統合セットアップ（推奨順序）**
```bash
# 1. 基本クラスター（完了済み）
cd k8s-setup && ./setup-k8s-cluster.sh

# 2. 監視システム
cd ../manifests/monitoring && ./setup-monitoring.sh

# 3. ログ集約
cd ../logging && ./setup-logging.sh

# 4. サンプルアプリ
kubectl apply -f ../apps/sample-app.yaml

# 5. Service Mesh
cd ../istio && ./setup-istio.sh
```

## 🛠️ トラブルシューティング

### kubectl が使用できない場合

Proxmoxホストでkubectlが使用できない場合の対処法：

```bash
# kubectl をProxmoxホストにインストール
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
chmod +x kubectl && sudo mv kubectl /usr/local/bin/

# kubeconfigを設定
cd k8s-setup
export KUBECONFIG=$PWD/kubeconfig
kubectl get nodes
```

### 詳細なトラブルシューティング

詳細なトラブルシューティング情報は各ディレクトリのREADMEを参照してください：
- [VM作成のトラブルシューティング](proxmox-vm-setup/README.md#トラブルシューティング)
- [K8s構築のトラブルシューティング](k8s-setup/README.md#トラブルシューティング)

---

## Proxmox 基本用語

### 仮想化関連
- **VM (Virtual Machine)**: 完全仮想化された仮想マシン。KVMを使用。
- **CT (Container)**: LXCベースのコンテナ。VMより軽量。
- **Template**: VMやCTのテンプレート。新規作成時のベースとなる。
- **Clone**: テンプレートから作成されたVMやCTのコピー。
  - **Full Clone**: 完全なコピー。元のディスクと独立。
  - **Linked Clone**: 差分のみを保存。元のディスクに依存。

### ストレージ関連
- **local**: ノードのローカルディレクトリ（/var/lib/proxmox）
- **local-lvm**: ノードのLVMストレージ。デフォルトのVM用ストレージ。
- **ZFS**: より高度なファイルシステム。スナップショットやRAID機能。

### ネットワーク関連
- **vmbr0**: デフォルトの仮想ブリッジ。通常、物理NICと接続。
- **VLAN**: 仮想LANによるネットワークの分離。
- **Cloud-Init**: VM初期設定用のツール（IPアドレス、SSHキーなど）。

### システム関連
- **Node**: Proxmoxをインストールした物理サーバー。
- **Cluster**: 複数のノードをまとめた集合。
- **Pool**: VMやCTを論理的にグループ化する単位。
- **DC (Datacenter)**: クラスタ全体の設定を管理する単位。

### ID体系
- **VMID**: VMやCTを識別する番号（100-999999）
  - 100-999: ユーザー用
  - 1000-999999: システム用推奨

## SSH

```sh
# ssh to host vm
ssh root@192.168.10.108

# ssh to k8s-master
ssh ubuntu@192.168.10.101

# ssh to k8s-node1
ssh ubuntu@192.168.10.102

# ssh to k8s-node2
ssh ubuntu@192.168.10.103
```

## 同ネットワーク内の VM 宛に 22番ポートが空いているか確認する方法

`lsof` は自分のローカルマシン上のソケットを確認するコマンドなので、リモート VM のポート確認には使えない。 
リモートのポート確認には以下の方法を使用。

### 1. `nc` (netcat) で確認

```bash
nc -zv <VM_IP> 22
# 例:
nc -zv 192.168.10.101 22
nc -zv 192.168.10.102 22
nc -zv 192.168.10.103 22
# -z : ポートスキャンモード（データ送信なし）
# -v : 詳細出力
# 成功すれば succeeded! と表示されます。
```

### 2. telnet で確認

```bash
telnet <VM_IP> 22
# 成功すると SSH のバナーが返ることがあります
# 失敗すると接続拒否やタイムアウトになります
```

### 3. ssh で接続テスト

```bash
ssh -v <user>@<VM_IP>
# -v オプションで詳細な接続情報を表示
# 「Connection refused」 → ポート閉じている
# 「Timed out」 → ネットワーク到達不可
```

### 4. ping でネットワーク到達確認

```bash
ping <VM_IP>
# まず ICMP が通るか確認すると SSH の接続可否の判断がしやすくなります
```

## ホストキーの管理

VMを再作成した場合や、SSHホストキーが変更された場合の対処方法：

### 1. 特定のホストキーの削除

```bash
# 特定のIPアドレスのホストキーを削除
ssh-keygen -f "~/.ssh/known_hosts" -R "192.168.10.101"
ssh-keygen -f "~/.ssh/known_hosts" -R "192.168.10.102"
ssh-keygen -f "~/.ssh/known_hosts" -R "192.168.10.103"
```

### 2. 既知のホストキーをすべて削除

```bash
# すべてのホストキーを削除（注意: すべてのホストの情報が削除されます）
rm ~/.ssh/known_hosts
```

### 3. SSHの初回接続時に自動的にホストキーを受け入れる

```bash
# StrictHostKeyCheckingをnoに設定して接続
ssh -o StrictHostKeyChecking=no ubuntu@192.168.10.101
```

### 4. 現在のホストキーの確認

```bash
# ホストキーのフィンガープリントを表示
ssh-keygen -l -f /etc/ssh/ssh_host_ed25519_key.pub
```
