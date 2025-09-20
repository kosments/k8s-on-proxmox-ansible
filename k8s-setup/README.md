# Kubernetes Cluster Setup

このディレクトリには、ProxmoxVE上のVMにKubernetesクラスターを構築するためのスクリプトが含まれています。

## 📋 概要

`setup-k8s-cluster.sh`は、以下の処理を自動化します：

1. **環境チェック**: SSH接続、ディスク容量の確認
2. **共通セットアップ**: 全ノードへのKubernetes共通コンポーネントの導入
3. **マスター初期化**: kubeadmによるクラスター初期化
4. **CNI導入**: Flannelネットワークプラグインのインストール
5. **ワーカー参加**: ワーカーノードのクラスター参加
6. **検証**: クラスター状態の確認

## 🚀 使用方法

### 基本的な実行

```bash
cd k8s-setup
./setup-k8s-cluster.sh
```

### 前提条件

- `proxmox-vm-setup/create-vms.sh`でVMが作成済み
- 全VMが起動中
- ProxmoxホストからVMへのSSH接続が可能

## 📊 実行フェーズ詳細

### Phase 0: 事前チェック
- SSH接続テスト
- ディスク容量確認
- 必要に応じてクリーンアップ実行

### Phase 1: 共通セットアップ
- ホスト名設定
- パッケージ更新
- Dockerランタイム（containerd）インストール
- Kubernetesコンポーネント（kubelet、kubeadm、kubectl）インストール
- システム設定（swap無効化、カーネルモジュール）

### Phase 2: マスターノード初期化
- `kubeadm init`によるクラスター初期化
- kubeconfigの設定
- join-commandの生成

### Phase 3: CNIインストール
- Flannelネットワークプラグインの導入
- ポッドネットワークの有効化

### Phase 4: ワーカーノード参加
- join-commandの配布
- 各ワーカーノードのクラスター参加

### Phase 5: 検証
- ノード状態の確認
- ポッド状態の確認

## 📁 出力ファイル

### kubeconfig
- kubectl用の設定ファイル
- Kubernetesクラスターへの接続情報

```bash
# 使用方法
export KUBECONFIG=$PWD/kubeconfig
kubectl get nodes
```

### join-command.txt
- ワーカーノード参加用のコマンド
- 手動でワーカーノードを追加する際に使用

## ⚙️ 設定のカスタマイズ

`../config.sh`を編集することで設定を変更できます：

### VM構成の変更
```bash
# VM数の増減
VM_IDS=(101 102 103 104 105)  # VM追加
VM_NAMES=("k8s-master" "k8s-node1" "k8s-node2" "k8s-node3" "k8s-node4")
VM_IPS=("192.168.10.101" "192.168.10.102" "192.168.10.103" "192.168.10.104" "192.168.10.105")
VM_ROLES=("master" "worker" "worker" "worker" "worker")
```

### スキップ設定
```bash
# 特定のVMをスキップ
SKIP_VM_102=true   # VM 102をスキップ
SKIP_VM_104=false  # VM 104を有効化
```

### Kubernetesバージョン
```bash
K8S_VERSION="1.28"
POD_NETWORK_CIDR="10.244.0.0/16"
```

## 🛠️ トラブルシューティング

### kubectl が使用できない場合

Proxmoxホストにkubectlがインストールされていない場合の対処法：

#### 方法1: Proxmoxホストにkubectlをインストール（推奨）

```bash
# 最新バージョンのkubectlをダウンロード・インストール
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
chmod +x kubectl && mv kubectl /usr/local/bin/

# kubeconfigを設定してクラスターにアクセス
cd k8s-setup
export KUBECONFIG=$PWD/kubeconfig
kubectl get nodes
kubectl get pods -A
```

#### 方法2: マスターノード経由でkubectlを実行

```bash
# マスターノード上で直接kubectl実行
ssh -i /root/.ssh/id_rsa ubuntu@192.168.10.101 'sudo kubectl get nodes'
ssh -i /root/.ssh/id_rsa ubuntu@192.168.10.101 'sudo kubectl get pods -A'
```

#### 方法3: スクリプトの管理機能を使用

```bash
# クラスター状態の確認
./setup-k8s-cluster.sh status

# ログの確認
./setup-k8s-cluster.sh logs
```

### kubeconfigファイルの手動取得

スクリプトでkubeconfigの取得に失敗した場合：

```bash
cd k8s-setup
ssh -i /root/.ssh/id_rsa ubuntu@192.168.10.101 'sudo cat /etc/kubernetes/admin.conf' > ./kubeconfig
chmod 600 ./kubeconfig
export KUBECONFIG=$PWD/kubeconfig
```

### SSH接続エラー
```bash
# ホストキーの問題
ssh-keygen -f "/root/.ssh/known_hosts" -R "192.168.10.101"

# 手動でSSH接続テスト
ssh -o StrictHostKeyChecking=no ubuntu@192.168.10.101
```

### ディスク容量不足
```bash
# VM内でのクリーンアップ
sudo apt-get clean
sudo apt-get autoremove
sudo journalctl --vacuum-time=1d
```

### クラスター初期化エラー
```bash
# マスターノードでのリセット
sudo kubeadm reset
sudo rm -rf /etc/kubernetes/

# 再実行
./setup-k8s-cluster.sh
```

### ワーカーノード参加エラー
```bash
# ワーカーノードでのリセット
sudo kubeadm reset

# 手動参加
sudo bash /tmp/kubeadm-join-command.txt
```

### CNI（Flannel）の問題

#### ノードが NotReady 状態の場合

**症状**: `kubectl get nodes` で全ノードが `NotReady` 状態
**原因**: CNIプラグインが正しくインストールされていない

```bash
# Flannelの状態確認
kubectl get pods -n kube-flannel -o wide

# kube-flannelネームスペースが空の場合
kubectl apply -f https://github.com/flannel-io/flannel/releases/latest/download/kube-flannel.yml

# Flannelポッドの起動確認（2-3分待つ）
kubectl get pods -n kube-flannel -w

# ノードの状態確認
kubectl get nodes
```

#### Flannel再インストール

```bash
# 既存のFlannel削除
kubectl delete -f https://github.com/flannel-io/flannel/releases/latest/download/kube-flannel.yml

# 少し待ってから再インストール
sleep 30
kubectl apply -f https://github.com/flannel-io/flannel/releases/latest/download/kube-flannel.yml

# ポッドの起動を確認
kubectl get pods -n kube-flannel -w
```

#### ネットワーク問題の診断

```bash
# ノードの詳細情報確認
kubectl describe nodes

# CNIエラーの確認
kubectl describe node <node-name> | grep -i network

# kubeletログの確認
ssh ubuntu@192.168.10.101 'sudo journalctl -u kubelet -f'
```

## 🔍 クラスター状態の確認

### ノード状態
```bash
export KUBECONFIG=$PWD/kubeconfig
kubectl get nodes -o wide
```

### ポッド状態
```bash
kubectl get pods -A
```

### クラスター情報
```bash
kubectl cluster-info
```

### ログの確認
```bash
# kubelet ログ
journalctl -u kubelet -f

# コンテナランタイムログ
journalctl -u containerd -f
```

## 📚 参考情報

- [Kubernetes公式ドキュメント](https://kubernetes.io/docs/)
- [kubeadm公式ガイド](https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/)
- [Flannel CNI](https://github.com/flannel-io/flannel)
- [containerd](https://containerd.io/)