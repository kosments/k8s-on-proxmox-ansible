# クイックスタート: VM再作成からクラスター構築まで

## 📋 事前準備

### 1. リポジトリのデプロイ

**重要**: まず、リポジトリをProxmoxホストにデプロイする必要があります。

詳細は [DEPLOYMENT.md](./DEPLOYMENT.md) を参照してください。

#### クイックデプロイ（Git Cloneの場合）

```bash
# ProxmoxホストにSSH接続
ssh root@192.168.10.108
# パスワード: 環境変数PROXMOX_PASSを設定、またはproxmox_access.mdを参照

# リポジトリをclone（初回のみ）
cd /root
git clone <リポジトリURL> k8s-on-proxmox-ansible

# または、既に存在する場合は更新
cd /root/k8s-on-proxmox-ansible
git pull origin main

# スクリプトに実行権限を付与
find . -name "*.sh" -type f -exec chmod +x {} \;
```

#### ファイル転送の場合

```bash
# ローカルPCで実行
cd /Users/kosments/dev/personal-dev/life-mng-repo/k8s-on-proxmox-ansible
./deploy-to-proxmox.sh
```

### 2. ドキュメントの確認

- [WORKFLOW.md](./WORKFLOW.md) - 作業フローと設計方針
- [EXECUTION-PLAN.md](./EXECUTION-PLAN.md) - 実行計画
- [DEPLOYMENT.md](./DEPLOYMENT.md) - デプロイメント手順

## 🚀 実行手順

### Step 1: VM再作成

```bash
# Proxmoxホストで実行
cd /root/k8s-on-proxmox-ansible/01-vm-creation

# 現在のVM状態を確認
qm list | grep -E "101|102|103"

# VM再作成を実行（確認プロンプトが表示されます）
./create-vms.sh
```

**実行時間**: 約5-10分（VM作成と起動待ちを含む）

**期待される結果**:

- VM 201 (k8s-master) が作成され、192.168.10.201で起動
- VM 202 (k8s-worker1) が作成され、192.168.10.202で起動
- VM 203 (k8s-worker2) が作成され、192.168.10.203で起動

### Step 2: SSH接続確認（VM起動後、約2-3分待機）

```bash
# Proxmoxホストまたは管理PCから実行
sshpass -p 'ubuntu' ssh -o StrictHostKeyChecking=no ubuntu@192.168.10.201 "hostname"
sshpass -p 'ubuntu' ssh -o StrictHostKeyChecking=no ubuntu@192.168.10.202 "hostname"
sshpass -p 'ubuntu' ssh -o StrictHostKeyChecking=no ubuntu@192.168.10.203 "hostname"
```

**確認ポイント**:

- ✅ 各VMにSSH接続できること
- ✅ cloud-initでSSHサービスが起動していること

### Step 3: k3sクラスター構築

```bash
# Proxmoxホストで実行
cd /root/k8s-on-proxmox-ansible/scripts

# k3sクラスター構築
./02-setup-k3s.sh
```

**実行時間**: 約5分

**期待される結果**:

- マスターノードにk3sがインストールされる
- ワーカーノードがクラスターに参加する
- すべてのノードが`Ready`状態になる

### Step 4: kubectlでクラスター確認

```bash
# Proxmoxホストで実行
cd /root/k8s-on-proxmox-ansible/02-k8s-cluster

# kubeconfigを取得
./setup-kubeconfig.sh

# kubectlで確認
export KUBECONFIG=$(pwd)/kubeconfig
kubectl get nodes -o wide
kubectl get pods -A
kubectl get svc -A
```

**確認ポイント**:

- ✅ すべてのノードが`Ready`状態
- ✅ システムPodが正常に動作していること

## ✅ 完了確認

以下のコマンドが正常に実行できれば完了です：

```bash
export KUBECONFIG=/root/k8s-on-proxmox-ansible/02-k8s-cluster/kubeconfig

# ノード確認
kubectl get nodes

# 出力例:
# NAME           STATUS   ROLES                  AGE   VERSION
# k8s-master     Ready    control-plane,master   5m    v1.28.x
# k8s-worker1    Ready    <none>                 4m    v1.28.x
# k8s-worker2    Ready    <none>                 4m    v1.28.x

# クラスター情報
kubectl cluster-info
```

## 🆘 トラブルシューティング

### VM作成に失敗した場合

```bash
# VM状態を確認
qm status 101
qm status 102
qm status 103

# ログを確認
tail -f /var/log/pve/tasks/active
```

### SSH接続できない場合

```bash
# VMコンソールから確認（ProxmoxのWeb UI経由）
# VM内で以下を実行:
sudo systemctl status ssh
sudo cat /var/log/cloud-init.log
```

### k3sインストールに失敗した場合

```bash
# VM内で確認
ssh ubuntu@192.168.10.201
sudo systemctl status k3s
sudo journalctl -u k3s -f
```

詳細は [TROUBLESHOOTING.md](../docs/TROUBLESHOOTING.md) を参照してください。
