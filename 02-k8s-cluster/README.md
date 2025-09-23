# 02-k8s-cluster - Kubernetesクラスター構築

## 📋 概要

このディレクトリには、Kubernetesクラスターの構築と管理に関する資材が含まれています。

## 🚀 クイックスタート

### 1. クラスター構築（初回のみ）

```bash
cd 02-k8s-cluster
./setup-k8s-cluster.sh
```

### 2. kubeconfigセットアップ（毎回）

```bash
cd 02-k8s-cluster
./setup-kubeconfig.sh
export KUBECONFIG=./kubeconfig
kubectl get nodes
```

## 📁 ファイル構成

```
02-k8s-cluster/
├── README.md                    # このファイル
├── setup-k8s-cluster.sh        # K8sクラスター構築スクリプト
├── setup-kubeconfig.sh         # kubeconfigセットアップスクリプト
├── alternative-ansible-setup/  # Ansible版（代替手段）
└── kubeconfig                  # K8s接続設定（gitignore対象）
```

## 🔧 使用方法

### クラスター構築

```bash
# 初回のみ実行
./setup-k8s-cluster.sh

# クラスター状態確認
./setup-k8s-cluster.sh status

# ログ確認
./setup-k8s-cluster.sh logs
```

### kubeconfig管理

```bash
# kubeconfigセットアップ
./setup-kubeconfig.sh

# クラスター状態確認
./setup-kubeconfig.sh status

# 接続テスト
./setup-kubeconfig.sh test
```

### kubectl使用

```bash
# 環境変数設定
export KUBECONFIG=./kubeconfig

# ノード確認
kubectl get nodes

# Pod確認
kubectl get pods -A

# アプリケーションデプロイ
kubectl apply -f ../04-applications/sample-app/
```

## ⚠️ 重要な注意事項

### kubeconfigファイルについて

- **kubeconfigファイルは機密情報を含むため、Gitにコミットしません**
- `.gitignore`で除外されています
- 毎回`./setup-kubeconfig.sh`で再生成してください

### セキュリティ

- kubeconfigには管理者権限の証明書が含まれています
- ファイル権限は600に設定されています
- 不要になったら削除してください

## 🔄 日常的な運用フロー

### 1. 初回セットアップ

```bash
# Step 1: VM作成
cd ../01-vm-creation
./create-vms.sh

# Step 2: K8sクラスター構築
cd ../02-k8s-cluster
./setup-k8s-cluster.sh

# Step 3: kubeconfigセットアップ
./setup-kubeconfig.sh
```

### 2. 日常的な使用

```bash
# VM再起動後や新しいセッションで
cd 02-k8s-cluster
./setup-kubeconfig.sh
export KUBECONFIG=./kubeconfig

# アプリケーションデプロイ
kubectl apply -f ../04-applications/sample-app/
```

### 3. アプリケーション更新

```bash
# 設定変更
vim ../04-applications/sample-app/deployment.yaml

# 更新適用
kubectl apply -f ../04-applications/sample-app/
```

## 🛠️ トラブルシューティング

### kubeconfigが見つからない

```bash
# 再生成
./setup-kubeconfig.sh
```

### クラスターに接続できない

```bash
# クラスター状態確認
./setup-k8s-cluster.sh status

# 接続テスト
./setup-kubeconfig.sh test
```

### Podが起動しない

```bash
# Pod詳細確認
kubectl describe pod <pod-name> -n <namespace>

# ログ確認
kubectl logs <pod-name> -n <namespace>
```

## 📚 参考情報

- [Kubernetes Documentation](https://kubernetes.io/docs/)
- [kubectl Cheat Sheet](https://kubernetes.io/docs/reference/kubectl/cheatsheet/)
- [kubeadm Documentation](https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/)
