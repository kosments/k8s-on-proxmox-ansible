# デプロイメント検証手順

## 📋 検証フロー

### Step 1: ローカルでリポジトリをpush

```bash
# ローカルPCで実行
cd /Users/kosments/dev/personal-dev/life-mng-repo/k8s-on-proxmox-ansible

# 変更をcommit & push
git add .
git commit -m "Update scripts"
git push origin master
```

### Step 2: Proxmoxホストでリポジトリをclone

**方法A: deployスクリプトを使用（推奨）**

```bash
# ローカルPCで実行
cd /Users/kosments/dev/personal-dev/life-mng-repo/k8s-on-proxmox-ansible

# デプロイスクリプトでclone
./deploy-to-proxmox.sh clone
```

**方法B: Proxmoxホストに直接SSH接続してclone**

```bash
# ProxmoxホストにSSH接続
ssh root@192.168.10.108
# パスワード: Bassa627

# リポジトリをclone
cd /root
rm -rf k8s-on-proxmox-ansible  # 既存の場合は削除（バックアップ推奨）
git clone https://github.com/kosments/k8s-on-proxmox-ansible.git

# スクリプトに実行権限を付与
cd k8s-on-proxmox-ansible
find . -name "*.sh" -type f -exec chmod +x {} \;
```

### Step 3: VM再作成

```bash
# Proxmoxホストで実行
cd /root/k8s-on-proxmox-ansible/01-vm-creation

# VM再作成を実行
./create-vms.sh
```

**実行時間**: 約5-10分

### Step 4: SSH接続確認

```bash
# Proxmoxホストで実行（VM起動後、約2-3分待機）
sleep 180

# SSH接続テスト
sshpass -p 'ubuntu' ssh -o StrictHostKeyChecking=no ubuntu@192.168.10.111 "hostname"
sshpass -p 'ubuntu' ssh -o StrictHostKeyChecking=no ubuntu@192.168.10.112 "hostname"
sshpass -p 'ubuntu' ssh -o StrictHostKeyChecking=no ubuntu@192.168.10.113 "hostname"
```

**期待される結果**: 各VMのホスト名が表示される

### Step 5: k3sクラスター構築

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

### Step 6: kubectlでクラスター確認

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
```

**期待される出力例**:

```
NAME           STATUS   ROLES                  AGE   VERSION
k8s-master     Ready    control-plane,master   5m    v1.28.x
k8s-worker1    Ready    <none>                 4m    v1.28.x
k8s-worker2    Ready    <none>                 4m    v1.28.x
```

## ✅ 検証完了条件

以下の条件がすべて満たされれば検証完了：

1. ✅ リポジトリがProxmoxホストにcloneされている
2. ✅ VMが正常に作成され、起動している
3. ✅ すべてのVMにSSH接続できる
4. ✅ k3sクラスターが構築され、すべてのノードがReady状態
5. ✅ kubectlでクラスター情報を取得できる
6. ✅ `kubectl get nodes`で3つのノードが表示される
7. ✅ `kubectl get pods -A`でシステムPodが正常に動作している

## 🛠️ トラブルシューティング

### ProxmoxホストにSSH接続できない

```bash
# ProxmoxのWeb UIから確認
# または、コンソールからSSHサービスを起動
systemctl start ssh
systemctl enable ssh
```

### Git cloneに失敗する

```bash
# Proxmoxホストにgitがインストールされているか確認
which git || apt-get update && apt-get install -y git

# 手動でclone
cd /root
git clone https://github.com/kosments/k8s-on-proxmox-ansible.git
```

### VM作成に失敗する

```bash
# VM状態を確認
qm list | grep -E "101|102|103"

# ログを確認
tail -f /var/log/pve/tasks/active
```

詳細は [TROUBLESHOOTING.md](./TROUBLESHOOTING.md) を参照してください。

