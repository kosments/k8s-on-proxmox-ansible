# デプロイメント手順

## 📋 概要

このドキュメントでは、リポジトリをProxmoxホストにデプロイし、VM作成からクラスター構築まで実行する手順を説明します。

## 🚀 デプロイメント方法

### 方法1: Git Clone（推奨）

リポジトリがGitで管理されている場合、Proxmoxホストでcloneします。

#### ステップ1: リポジトリをpush（ローカルPCで実行）

```bash
# ローカルPCで実行
cd /Users/kosments/dev/personal-dev/life-mng-repo/k8s-on-proxmox-ansible

# 変更をcommit
git add .
git commit -m "Update VM creation scripts and add cloud-init support"

# push（リモートリポジトリがある場合）
git push origin main
# または
git push origin master
```

**または、デプロイスクリプトで自動clone（推奨）**:

```bash
# ローカルPCで実行
cd /Users/kosments/dev/personal-dev/life-mng-repo/k8s-on-proxmox-ansible

# まず変更をpushしてから
git add .
git commit -m "Update scripts"
git push origin main

# デプロイスクリプトでcloneを実行
./deploy-to-proxmox.sh clone
```

#### ステップ2: Proxmoxホストでclone

```bash
# ProxmoxホストにSSH接続
ssh root@192.168.10.108
# パスワード: Bassa627

# リポジトリをclone
cd /root
git clone <リポジトリURL> k8s-on-proxmox-ansible
# または、既に存在する場合はpull
cd /root/k8s-on-proxmox-ansible
git pull origin main

# スクリプトに実行権限を付与
cd /root/k8s-on-proxmox-ansible
find . -name "*.sh" -type f -exec chmod +x {} \;
```

### 方法2: ファイル転送（Gitが使えない場合）

`deploy-to-proxmox.sh`スクリプトを使用してファイルを転送します。

```bash
# ローカルPCで実行
cd /Users/kosments/dev/personal-dev/life-mng-repo/k8s-on-proxmox-ansible

# デプロイスクリプトを実行
./deploy-to-proxmox.sh
```

## ✅ デプロイ後の確認

Proxmoxホストで以下を確認：

```bash
# ディレクトリ構成を確認
cd /root/k8s-on-proxmox-ansible
ls -la

# 主要スクリプトの確認
ls -la 01-vm-creation/create-vms.sh
ls -la scripts/02-setup-k3s.sh
ls -la 02-k8s-cluster/setup-kubeconfig.sh

# config.shの確認
cat config.sh
```

## 🎯 実行手順

デプロイが完了したら、[QUICK-START.md](./QUICK-START.md)の手順に従って実行してください。

### クイック実行

```bash
# 1. VM作成
cd /root/k8s-on-proxmox-ansible/01-vm-creation
./create-vms.sh

# 2. k3sクラスター構築
cd /root/k8s-on-proxmox-ansible/scripts
./02-setup-k3s.sh

# 3. kubectl設定と確認
cd /root/k8s-on-proxmox-ansible/02-k8s-cluster
./setup-kubeconfig.sh
export KUBECONFIG=$(pwd)/kubeconfig
kubectl get nodes -o wide
```

## 🔄 更新手順

リポジトリが更新された場合：

### Gitを使用している場合

```bash
# Proxmoxホストで実行
cd /root/k8s-on-proxmox-ansible
git pull origin main
```

### ファイル転送を使用している場合

```bash
# ローカルPCで実行
cd /Users/kosments/dev/personal-dev/life-mng-repo/k8s-on-proxmox-ansible
./deploy-to-proxmox.sh
```

## 🛠️ トラブルシューティング

### Git cloneに失敗する場合

```bash
# SSH鍵を確認
ssh-keygen -t rsa -b 2048

# GitHubにSSH鍵を登録（必要に応じて）
cat ~/.ssh/id_rsa.pub
```

### ファイル転送に失敗する場合

```bash
# SSH接続を確認
ssh root@192.168.10.108

# 手動でscpを使用
scp -r /path/to/k8s-on-proxmox-ansible root@192.168.10.108:/root/
```

## 📝 注意事項

- リポジトリのURLは実際のリポジトリに合わせて変更してください
- `.gitignore`で除外されているファイル（kubeconfigなど）は転送されません
- 機密情報（パスワードなど）は`config.sh`に含まれないように注意してください

