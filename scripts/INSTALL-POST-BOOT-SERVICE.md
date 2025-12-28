# Proxmoxホスト再起動時の自動セットアップ

## 概要

Proxmoxホストの再起動時に、VMのSSH設定を自動的に確認・修正するsystemdサービスを設定します。

## インストール方法

### ステップ1: スクリプトをProxmoxホストに配置

```bash
# Proxmoxホストで実行
cd /root/k8s-on-proxmox-ansible/scripts

# スクリプトに実行権限を付与
chmod +x proxmox-post-boot-setup.sh
chmod +x vm-post-boot-setup.sh
```

### ステップ2: systemdサービスをインストール

```bash
# systemdサービスファイルをコピー
sudo cp proxmox-post-boot.service /etc/systemd/system/

# systemdをリロード
sudo systemctl daemon-reload

# サービスを有効化
sudo systemctl enable proxmox-post-boot.service

# サービスを開始（テスト実行）
sudo systemctl start proxmox-post-boot.service

# 状態を確認
sudo systemctl status proxmox-post-boot.service

# ログを確認
sudo journalctl -u proxmox-post-boot.service -f
```

### ステップ3: 動作確認

```bash
# サービスが有効化されているか確認
sudo systemctl is-enabled proxmox-post-boot.service

# 手動で実行してテスト
sudo /root/k8s-on-proxmox-ansible/scripts/proxmox-post-boot-setup.sh

# ログファイルを確認
tail -f /var/log/proxmox-post-boot-setup.log
```

## 代替方法: cronを使用

systemdサービスが使えない場合、cronを使用できます：

```bash
# crontabを編集
sudo crontab -e

# 以下を追加（再起動後5分後に実行）
@reboot sleep 300 && /root/k8s-on-proxmox-ansible/scripts/proxmox-post-boot-setup.sh >> /var/log/proxmox-post-boot-setup.log 2>&1
```

## トラブルシューティング

### サービスが起動しない場合

```bash
# サービスの状態を確認
sudo systemctl status proxmox-post-boot.service

# ログを確認
sudo journalctl -u proxmox-post-boot.service -n 50

# スクリプトを手動で実行してエラーを確認
sudo /root/k8s-on-proxmox-ansible/scripts/proxmox-post-boot-setup.sh
```

### VMに接続できない場合

```bash
# VMの状態を確認
qm status 101
qm status 102
qm status 103

# VMを手動で起動
qm start 101
qm start 102
qm start 103

# SSH接続を試みる
ssh ubuntu@192.168.10.111
```

### ログファイルの確認

```bash
# ログファイルを確認
tail -f /var/log/proxmox-post-boot-setup.log

# ログを検索
grep -i error /var/log/proxmox-post-boot-setup.log
grep -i "VM" /var/log/proxmox-post-boot-setup.log
```

## サービスを無効化する場合

```bash
# サービスを無効化
sudo systemctl disable proxmox-post-boot.service

# サービスを停止
sudo systemctl stop proxmox-post-boot.service

# サービスファイルを削除
sudo rm /etc/systemd/system/proxmox-post-boot.service
sudo systemctl daemon-reload
```

