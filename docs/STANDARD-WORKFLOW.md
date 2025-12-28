# 標準ワークフロー

## 📋 基本的な構築フロー

### 1. VM作成

```bash
cd /root/k8s-on-proxmox-ansible/01-vm-creation
./create-vms.sh
```

**このスクリプトが行うこと**:
- Ubuntu 22.04 LTS Cloud Imageのダウンロード（未取得の場合）
- SSH鍵の生成（未生成の場合）
- VMの作成（101, 102, 103）
- Cloud-initによる初期設定（SSH、パスワード認証）
- VMの起動とSSH接続確認

### 2. k3sクラスター構築

```bash
cd /root/k8s-on-proxmox-ansible/scripts
./02-setup-k3s.sh
```

**このスクリプトが行うこと**:
- マスターノード（VM 201）にk3sをインストール
- クラスター参加トークンを取得
- ワーカーノード（VM 202, 103）をクラスターに参加
- クラスター状態の確認
- kubeconfigファイルの生成

### 3. kubeconfig取得（管理PCから操作する場合）

```bash
cd /root/k8s-on-proxmox-ansible/scripts
./get-kubeconfig-from-master.sh
export KUBECONFIG=~/.kube/config-k3s
```

または、プロジェクトルートで：

```bash
cd /root/k8s-on-proxmox-ansible/02-k8s-cluster
./setup-kubeconfig.sh setup
export KUBECONFIG=$(pwd)/kubeconfig
```

### 4. クラスター確認

```bash
kubectl get nodes -o wide
kubectl get pods -A
kubectl cluster-info
```

または、スクリプトを使用：

```bash
cd /root/k8s-on-proxmox-ansible/scripts
./03-verify-cluster.sh
```

## 🔄 再起動時の自動セットアップ

### systemdサービスを有効化

```bash
cd /root/k8s-on-proxmox-ansible/scripts
sudo cp proxmox-post-boot.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable proxmox-post-boot.service
```

これにより、Proxmoxホストの再起動後に自動的に：
- VMが起動していない場合は起動
- SSHサービスが起動していない場合は起動・設定
- SSH接続の確認

## 🛠️ トラブルシューティング

### VMにSSH接続できない場合

```bash
# VM状態確認
cd /root/k8s-on-proxmox-ansible/scripts
./check-vm-status.sh

# 再起動時セットアップスクリプトを手動実行
./proxmox-post-boot-setup.sh
```

### k3sが起動しない場合

```bash
# マスターノードで確認
ssh ubuntu@192.168.10.201
sudo systemctl status k3s
sudo journalctl -u k3s -f
```

### kubectl接続できない場合

```bash
# kubeconfigを再取得
cd /root/k8s-on-proxmox-ansible/scripts
./get-kubeconfig-from-master.sh

# 接続確認
export KUBECONFIG=~/.kube/config-k3s
kubectl get nodes
```

## 📝 スクリプトの責務

| スクリプト | 責務 | 実行場所 |
|----------|------|---------|
| `01-vm-creation/create-vms.sh` | VM作成 | Proxmoxホスト |
| `scripts/02-setup-k3s.sh` | k3s構築 | Proxmoxホスト |
| `scripts/get-kubeconfig-from-master.sh` | kubeconfig取得 | 管理PC |
| `scripts/03-verify-cluster.sh` | クラスター確認 | 管理PC/Proxmoxホスト |
| `scripts/proxmox-post-boot-setup.sh` | 再起動時セットアップ | Proxmoxホスト（自動） |
| `scripts/check-vm-status.sh` | VM状態確認 | Proxmoxホスト |

## 🔍 詳細ドキュメント

- ワークフローと設計ルール: `docs/WORKFLOW-AND-DESIGN.md`
- スクリプト整理計画: `docs/SCRIPTS-CLEANUP.md`
- トラブルシューティング: `docs/TROUBLESHOOTING.md`

