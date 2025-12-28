# VM再作成とクラスター構築実行計画

## 📋 実行タスクリスト

### ✅ 完了済み

- [x] 作業ルールと設計をdocsにまとめる
- [x] 不要・古いスクリプトを整理・削除
  - 削除: `scripts/get-kubeconfig-from-master.sh`
  - 削除: `01-vm-creation/setup-vm-ssh-after-boot.sh`

### 🔄 実行中・予定

- [ ] VM再作成スクリプトの動作確認とテスト
- [ ] VM再作成を実行
- [ ] SSH接続とk3sクラスター構築を確認
- [ ] kubectlでクラスター情報を取得できることを確認

## 🚀 実行手順

### ステップ1: VM再作成スクリプトの確認

```bash
cd /Users/kosments/dev/personal-dev/life-mng-repo/k8s-on-proxmox-ansible/01-vm-creation

# スクリプトの構文チェック
bash -n create-vms.sh

# cloud-initファイルの確認
cat cloud-init-user-data.yaml
```

### ステップ2: Proxmoxホストへの準備

```bash
# ProxmoxホストにSSH接続
ssh root@192.168.10.108

# スクリプトをProxmoxホストに転送（必要に応じて）
# または、既にProxmoxホストにある場合はそのまま使用
```

### ステップ3: VM再作成の実行

```bash
# Proxmoxホストで実行
cd /root/k8s-on-proxmox-ansible/01-vm-creation

# 現在のVM状態を確認
qm list | grep -E "101|102|103"

# VM再作成を実行
./create-vms.sh
```

### ステップ4: SSH接続の確認

```bash
# VM起動を待つ（約2-3分）
sleep 180

# SSH接続テスト
sshpass -p 'ubuntu' ssh -o StrictHostKeyChecking=no ubuntu@192.168.10.111 "hostname"
sshpass -p 'ubuntu' ssh -o StrictHostKeyChecking=no ubuntu@192.168.10.112 "hostname"
sshpass -p 'ubuntu' ssh -o StrictHostKeyChecking=no ubuntu@192.168.10.113 "hostname"
```

### ステップ5: k3sクラスター構築

```bash
cd /root/k8s-on-proxmox-ansible/scripts

# k3sクラスター構築
./02-setup-k3s.sh
```

### ステップ6: kubectlでクラスター確認

```bash
cd /root/k8s-on-proxmox-ansible/02-k8s-cluster

# kubeconfigを取得
./setup-kubeconfig.sh

# kubectlで確認
export KUBECONFIG=$(pwd)/kubeconfig
kubectl get nodes -o wide
kubectl get pods -A
```

## ⚠️ 注意事項

- VM再作成時は既存のVMデータが削除されます
- 実行前にVMの状態を確認してください
- cloud-initの設定が正しく適用されるまで数分かかる場合があります

## 🔍 トラブルシューティング

### VM作成に失敗した場合

```bash
# VM状態を確認
qm status 101
qm status 102
qm status 103

# ログを確認
journalctl -xe
```

### SSH接続できない場合

```bash
# VMコンソールから確認
# ProxmoxのWeb UIからVMコンソールにアクセス
# VM内で以下を実行:
sudo systemctl status ssh
sudo cat /var/log/cloud-init.log
```

### k3sインストールに失敗した場合

```bash
# VM内で確認
sudo systemctl status k3s
sudo journalctl -u k3s -f
```
