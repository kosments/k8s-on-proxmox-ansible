# k8s-on-proxmox-ansible

Proxmox VE上にk3s Kubernetesクラスターを構築するためのシンプルなツールセットです。

## 🎯 特徴

- **シンプル**: 3つのスクリプトで完結
- **確実**: テンプレートクローン方式で安定したVM作成
- **軽量**: k3sによる軽量Kubernetesクラスター
- **トラブルシューティングしやすい**: 各ステップが明確に分離
- **ARP固定を回避**: MACアドレス自動生成でネットワーク問題を防止

## 📁 構成

```
k8s-on-proxmox-ansible/
├── 01-vm-creation/
│   └── create-vms.sh        # Step 1: VM作成
├── scripts/
│   ├── 02-setup-k3s.sh      # Step 2: k3sをインストール
│   └── 03-verify-cluster.sh # Step 3: クラスター確認
├── 02-k8s-cluster/
│   ├── setup-kubeconfig.sh  # kubeconfig設定
│   └── quick-kubeconfig.sh  # 簡易kubeconfig取得
├── docs/                    # 詳細ドキュメント
└── README.md
```

## 🚀 クイックスタート

### 前提条件

- Proxmox VE 7.x以上
- SSH鍵が設定済み、またはパスワード認証が可能（環境変数`PROXMOX_PASS`を設定、または`proxmox_access.md`を参照）
- 十分なストレージ容量（VM 3台 × 50GB = 約150GB）
- リポジトリがGitHubにpushされている

### Step 0: リポジトリをProxmoxホストにデプロイ

**重要**: まず、リポジトリをProxmoxホストにcloneまたは転送する必要があります。

詳細は [docs/DEPLOYMENT.md](docs/DEPLOYMENT.md) または [docs/FULL-DEPLOYMENT-GUIDE.md](docs/FULL-DEPLOYMENT-GUIDE.md) を参照してください。

#### 方法1: デプロイスクリプトを使用（推奨）

```bash
# ローカルPCで実行
cd /path/to/k8s-on-proxmox-ansible

# 変更をpush
git push origin master

# 環境変数を設定（必要に応じて）
export PROXMOX_PASS="your-password"

# Proxmoxホストにclone
./deploy-to-proxmox.sh clone
```

#### 方法2: Proxmoxホストで直接clone

```bash
# Proxmoxホストで実行
ssh root@192.168.10.108
# パスワード: 環境変数PROXMOX_PASSを設定、またはproxmox_access.mdを参照
cd /root
git clone https://github.com/kosments/k8s-on-proxmox-ansible.git
cd k8s-on-proxmox-ansible
find . -name "*.sh" -type f -exec chmod +x {} \;
```

### Step 1: VMを作成

```bash
# Proxmoxホスト上で実行
cd /root/k8s-on-proxmox-ansible/01-vm-creation
./create-vms.sh
```

作成されるVM:

- VM 201: k8s-master (192.168.10.201)
- VM 202: k8s-worker1 (192.168.10.202)
- VM 203: k8s-worker2 (192.168.10.203)

**注意**: VM IDは201-203、IPアドレスは192.168.10.201-203を使用します。ARP固定を避けるため、MACアドレスは自動生成されます。

### Step 2: k3sをインストール

```bash
# Proxmoxホスト上で実行
cd /root/k8s-on-proxmox-ansible/scripts
./02-setup-k3s.sh
```

### Step 3: kubectl設定とクラスター確認

```bash
# Proxmoxホスト上で実行
cd /root/k8s-on-proxmox-ansible/02-k8s-cluster
./setup-kubeconfig.sh
export KUBECONFIG=$(pwd)/kubeconfig

# クラスター確認
kubectl get nodes -o wide
kubectl get pods -A

# 詳細確認スクリプト
cd /root/k8s-on-proxmox-ansible/scripts
./03-verify-cluster.sh
```

## 📋 システム要件

### Proxmox環境

- CPU: 4コア以上
- メモリ: 16GB以上
- ストレージ: 200GB以上

### 作成されるVM仕様

| 項目 | 値 |
|------|-----|
| OS | Ubuntu 22.04 LTS |
| メモリ | 4GB / VM |
| CPU | 2コア / VM |
| ディスク | 50GB / VM |
| ネットワーク | 192.168.10.201-203 |
| VM ID | 201-203 |

## 🔧 kubectl の使用方法

### Proxmoxホストから

```bash
export KUBECONFIG=/root/k8s-on-proxmox-ansible/02-k8s-cluster/kubeconfig
kubectl get nodes
```

### ローカルPC（Mac/Linux）から

```bash
# kubeconfigをコピー
scp root@192.168.10.108:/root/k8s-on-proxmox-ansible/02-k8s-cluster/kubeconfig ~/.kube/config-k3s

# kubectlを使用
export KUBECONFIG=~/.kube/config-k3s
kubectl get nodes
```

## 🔄 再起動時の対応

Proxmoxホストが再起動した場合、以下を実行してください：

```bash
# VMが起動していることを確認
qm list | grep -E "201|202|203"

# kubeconfigを再取得
cd /root/k8s-on-proxmox-ansible/02-k8s-cluster
./setup-kubeconfig.sh
export KUBECONFIG=$(pwd)/kubeconfig
kubectl get nodes
```

詳細は [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md) を参照してください。

## 🛠️ トラブルシューティング

### VMにSSH接続できない

```bash
# ProxmoxのWeb UIからVMコンソールにアクセス
# VM内で以下を実行:
sudo systemctl start ssh
sudo systemctl enable ssh
sudo passwd ubuntu  # パスワードを設定
```

### IPアドレス競合

VM IDを201-203、IPアドレスを192.168.10.201-203に設定しています。ARP固定を避けるため、MACアドレスは自動生成されます。

### クラスターに接続できない

```bash
# kubeconfigを再取得
cd /root/k8s-on-proxmox-ansible/02-k8s-cluster
./setup-kubeconfig.sh
export KUBECONFIG=$(pwd)/kubeconfig
kubectl get nodes
```

詳細は [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md) を参照してください。

## 📚 ドキュメント

- [docs/FULL-DEPLOYMENT-GUIDE.md](docs/FULL-DEPLOYMENT-GUIDE.md) - 完全デプロイメントガイド
- [docs/DEPLOYMENT.md](docs/DEPLOYMENT.md) - デプロイメント手順
- [docs/WORKFLOW.md](docs/WORKFLOW.md) - 作業フローと設計方針
- [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md) - トラブルシューティングガイド

## 🔐 セキュリティ

- パスワード情報は環境変数`PROXMOX_PASS`で管理、または`proxmox_access.md`（git管理外）を参照
- kubeconfigファイルは機密情報を含むため、Gitにコミットされません

## 📝 ライセンス

MIT License

## 🤝 コントリビューション

プルリクエストを歓迎します！
