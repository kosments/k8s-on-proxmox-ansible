# 完全デプロイメントガイド

## 📋 概要

このガイドでは、リポジトリをProxmoxホストにデプロイし、VM作成からKubernetesクラスター構築まで、すべての手順を段階的に実行します。

## 🎯 前提条件

- ✅ ローカルPCでリポジトリが準備されている
- ✅ リポジトリがGitHubにpushされている
- ✅ Proxmoxホスト（192.168.10.108）が起動している
- ✅ ProxmoxホストにSSH接続できる（環境変数`PROXMOX_PASS`を設定、または`proxmox_access.md`を参照）

## 🚀 実行手順

### Phase 1: ローカルでの準備

#### 1.1 変更をcommit & push

```bash
# ローカルPCで実行
cd /Users/kosments/dev/personal-dev/life-mng-repo/k8s-on-proxmox-ansible

# 変更を確認
git status

# 変更をcommit
git add .
git commit -m "Update scripts and documentation"

# push
git push origin master
```

### Phase 2: Proxmoxホストへのデプロイ

#### 2.1 デプロイスクリプトを使用（推奨）

```bash
# ローカルPCで実行
cd /Users/kosments/dev/personal-dev/life-mng-repo/k8s-on-proxmox-ansible

# Proxmoxホストにリポジトリをclone
./deploy-to-proxmox.sh clone
```

#### 2.2 手動でclone（代替方法）

```bash
# ProxmoxホストにSSH接続
ssh root@192.168.10.108
# パスワード: 環境変数PROXMOX_PASSを設定、またはproxmox_access.mdを参照

# リポジトリをclone
cd /root
rm -rf k8s-on-proxmox-ansible  # 既存の場合は削除
git clone https://github.com/kosments/k8s-on-proxmox-ansible.git

# スクリプトに実行権限を付与
cd k8s-on-proxmox-ansible
find . -name "*.sh" -type f -exec chmod +x {} \;
```

### Phase 3: VM作成

```bash
# Proxmoxホストで実行
cd /root/k8s-on-proxmox-ansible/01-vm-creation

# VM再作成を実行
./create-vms.sh
```

**実行時間**: 約5-10分

**確認ポイント**:

- ✅ 3つのVM（101, 102, 103）が作成される
- ✅ 各VMが起動する
- ✅ 固定IPアドレスが設定される（201, 202, 203）

### Phase 4: SSH接続確認

```bash
# Proxmoxホストで実行（VM起動後、約2-3分待機）
sleep 180

# SSH接続テスト
for ip in 192.168.10.201 192.168.10.202 192.168.10.203; do
    echo "Testing $ip..."
    sshpass -p 'ubuntu' ssh -o StrictHostKeyChecking=no ubuntu@${ip} "hostname" && echo "✅ OK" || echo "❌ FAILED"
done
```

**期待される結果**: すべてのVMで`✅ OK`が表示される

### Phase 5: k3sクラスター構築

```bash
# Proxmoxホストで実行
cd /root/k8s-on-proxmox-ansible/scripts

# k3sクラスター構築
./02-setup-k3s.sh
```

**実行時間**: 約5分

**確認ポイント**:

- ✅ マスターノードにk3sがインストールされる
- ✅ ワーカーノードがクラスターに参加する
- ✅ すべてのノードが`Ready`状態になる

### Phase 6: kubectl設定と検証

```bash
# Proxmoxホストで実行
cd /root/k8s-on-proxmox-ansible/02-k8s-cluster

# kubeconfigを取得
./setup-kubeconfig.sh

# kubectlで確認
export KUBECONFIG=$(pwd)/kubeconfig

# ノード確認
kubectl get nodes -o wide

# Pod確認
kubectl get pods -A

# サービス確認
kubectl get svc -A

# クラスター情報
kubectl cluster-info
```

**期待される結果**:

```
NAME           STATUS   ROLES                  AGE   VERSION
k8s-master     Ready    control-plane,master   5m    v1.28.x
k8s-worker1    Ready    <none>                 4m    v1.28.x
k8s-worker2    Ready    <none>                 4m    v1.28.x
```

## ✅ 検証完了チェックリスト

- [ ] リポジトリがProxmoxホストにcloneされている
- [ ] VM 201, 102, 103が正常に作成され、起動している
- [ ] すべてのVMにSSH接続できる（ubuntu/ubuntu）
- [ ] k3sクラスターが構築されている
- [ ] すべてのノードがReady状態
- [ ] `kubectl get nodes`で3つのノードが表示される
- [ ] `kubectl get pods -A`でシステムPodが正常に動作している
- [ ] `kubectl cluster-info`でクラスター情報が表示される

## 🔄 更新手順

リポジトリが更新された場合：

```bash
# Proxmoxホストで実行
cd /root/k8s-on-proxmox-ansible
git pull origin master
```

## 📚 関連ドキュメント

- [DEPLOYMENT.md](./DEPLOYMENT.md) - デプロイメント方法の詳細
- [DEPLOYMENT-VERIFICATION.md](./DEPLOYMENT-VERIFICATION.md) - 検証手順
- [QUICK-START.md](./QUICK-START.md) - クイックスタート
- [WORKFLOW.md](./WORKFLOW.md) - 作業フローと設計方針
- [TROUBLESHOOTING.md](./TROUBLESHOOTING.md) - トラブルシューティング
