# VM再作成と再起動時の自動セットアップ

## 📋 概要

Proxmoxホストの再起動時にVM設定がリセットされる問題を解決するため、以下の仕組みを提供します：

1. **VM作成時にcloud-initでSSH設定を自動適用**
2. **Proxmoxホスト再起動時に自動的にVM設定を確認・修正**

## 🚀 使用方法

### VMを再作成する場合

```bash
cd /Users/kosments/dev/personal-dev/life-mng-repo/k8s-on-proxmox-ansible/01-vm-creation

# VM作成スクリプトを実行
./create-vms.sh
```

このスクリプトは：

- `cloud-init-user-data.yaml`を使用してSSHサービスとパスワード認証を自動的に有効化
- 各VMに固定IPアドレスを設定
- ubuntuユーザーにパスワード（ubuntu）を設定

### 再起動時の自動セットアップを有効化

Proxmoxホストで以下を実行：

```bash
# スクリプトをProxmoxホストにコピー（必要に応じて）
# または、既にProxmoxホストにある場合は以下を実行

cd /root/k8s-on-proxmox-ansible/scripts

# systemdサービスをインストール
sudo cp proxmox-post-boot.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable proxmox-post-boot.service
sudo systemctl start proxmox-post-boot.service

# 状態を確認
sudo systemctl status proxmox-post-boot.service
```

詳細は `scripts/INSTALL-POST-BOOT-SERVICE.md` を参照してください。

## 📁 ファイル構成

```
01-vm-creation/
├── create-vms.sh                    # VM作成スクリプト（修正済み）
├── cloud-init-user-data.yaml       # cloud-init設定ファイル（新規作成）
└── README-VM-RECREATE.md           # このファイル

scripts/
├── proxmox-post-boot-setup.sh      # 再起動時セットアップスクリプト（新規作成）
├── vm-post-boot-setup.sh           # VM起動後セットアップスクリプト（新規作成）
├── proxmox-post-boot.service       # systemdサービスファイル（新規作成）
└── INSTALL-POST-BOOT-SERVICE.md    # インストール手順（新規作成）
```

## 🔧 cloud-init設定の内容

`cloud-init-user-data.yaml` は以下の設定を行います：

- ✅ openssh-serverのインストール
- ✅ SSHサービスの自動起動
- ✅ パスワード認証の有効化
- ✅ rootログインの許可

## 🔄 再起動時の動作

`proxmox-post-boot-setup.sh` は以下の処理を実行します：

1. **VMの起動確認**: 停止中のVMを自動的に起動
2. **SSH接続確認**: 各VMにSSH接続できるか確認
3. **SSH設定修正**: SSHサービスが起動していない場合、自動的に起動・設定

## 🛠️ トラブルシューティング

### VM作成後にSSH接続できない場合

```bash
# VMの状態を確認
qm status 101
qm status 102
qm status 103

# VMを再起動
qm reboot 101

# SSH接続を試す（パスワード: ubuntu）
sshpass -p 'ubuntu' ssh ubuntu@192.168.10.111
```

### 再起動後にVM設定がリセットされる場合

```bash
# セットアップスクリプトを手動で実行
sudo /root/k8s-on-proxmox-ansible/scripts/proxmox-post-boot-setup.sh

# ログを確認
tail -f /var/log/proxmox-post-boot-setup.log
```

### cloud-initが動作しない場合

```bash
# VM内でcloud-initのログを確認
sudo cat /var/log/cloud-init.log
sudo cat /var/log/cloud-init-output.log

# cloud-initを再実行（VM内で）
sudo cloud-init clean
sudo cloud-init init
```

## 📝 注意事項

- VMを再作成すると、既存のデータは削除されます
- k8sクラスターが構築済みの場合、VM再作成後は再構築が必要です
- パスワードは `ubuntu` に設定されています（本番環境では変更してください）

## 🔐 セキュリティ

本番環境では以下を推奨します：

1. **パスワードを変更**: `ubuntu`以外の強力なパスワードを使用
2. **SSH鍵認証のみ**: パスワード認証を無効化し、SSH鍵のみ使用
3. **ファイアウォール設定**: 必要最小限のポートのみ開放
