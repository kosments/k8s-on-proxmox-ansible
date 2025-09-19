# Kubernetes Cluster Setup

このディレクトリには、ProxmoxVM上にKubernetesクラスターをセットアップするための2つのアプローチが含まれています。

## 🚀 アプローチ1: シェルスクリプト（推奨）

### 特徴
- シンプルで理解しやすい
- デバッグが容易
- SSH接続を1つずつ処理
- エラーハンドリングが充実

### 使用方法

```bash
# スクリプトに実行権限を付与
chmod +x setup-k8s-cluster.sh

# クラスター作成実行
./setup-k8s-cluster.sh
```

### 設定項目
スクリプト内の以下の変数を環境に合わせて調整してください：

```bash
MASTER_IP="192.168.10.101"
NODE1_IP="192.168.10.102"  
NODE2_IP="192.168.10.103"
SSH_USER="ubuntu"
SSH_KEY="~/.ssh/id_rsa"
K8S_VERSION="1.28.2-1.1"
POD_CIDR="10.244.0.0/16"
```

## 🎯 アプローチ2: シーケンシャルAnsible

### 特徴
- 各ノードを順番に設定
- SSH接続の競合を回避
- Ansibleの冪等性を活用
- より詳細な制御が可能

### 使用方法

```bash
# インベントリファイルを確認・調整
vim inventory.ini

# プレイブック実行
ansible-playbook -i inventory.ini sequential-playbook.yml
```

## 📋 前提条件

1. **SSH接続の設定**
   - すべてのVMにSSH鍵認証でアクセス可能
   - `~/.ssh/id_rsa`に秘密鍵が配置済み

2. **ネットワーク設定**
   - すべてのノードが相互通信可能
   - インターネット接続が利用可能

3. **システム要件**
   - Ubuntu 22.04 LTS
   - 最低2GB RAM、2CPU
   - スワップが無効化されていること

## 🔧 セットアップ手順

### 1. VM作成（事前に完了）
```bash
cd ../proxmox-vm-setup
ansible-playbook -i inventory.ini playbook.yml
```

### 2. Kubernetesクラスター構築
```bash
# 方法A: シェルスクリプト
./setup-k8s-cluster.sh

# 方法B: Ansibleプレイブック  
ansible-playbook -i inventory.ini sequential-playbook.yml
```

### 3. クラスター確認
```bash
# kubeconfigを設定
export KUBECONFIG=$PWD/kubeconfig

# ノード状態確認
kubectl get nodes

# Pod状態確認
kubectl get pods -A
```

## 🐛 トラブルシューティング

### SSH接続エラー
```bash
# SSH接続テスト
ssh -o ConnectTimeout=10 -i ~/.ssh/id_rsa ubuntu@192.168.10.101

# SSH Agent確認
ssh-add -l
```

### ネットワーク問題
```bash
# CNI Pod状態確認
kubectl get pods -n kube-flannel

# ネットワーク設定確認
kubectl get nodes -o wide
```

### ログ確認
```bash
# kubelet ログ
sudo journalctl -u kubelet -f

# containerd ログ
sudo journalctl -u containerd -f
```

## 📊 構成情報

| コンポーネント | バージョン | 説明 |
|---------------|------------|------|
| Kubernetes | 1.28.2 | メインのオーケストレーター |
| containerd | latest | コンテナランタイム |
| Flannel | latest | CNI（Container Network Interface） |
| Ubuntu | 22.04 LTS | ベースOS |

## 🎉 完了後の確認

クラスター構築完了後、以下のコマンドで状態を確認してください：

```bash
# ノード状態（すべてReadyになっている）
kubectl get nodes

# システムPod（すべてRunningになっている）
kubectl get pods -n kube-system

# Flannel Pod（各ノードで1つずつRunning）
kubectl get pods -n kube-flannel
```

正常に完了すると、3ノードのKubernetesクラスターが利用可能になります。
