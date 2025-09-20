# 01 - VM作成

このディレクトリには、ProxmoxでKubernetesクラスター用のVMを作成するためのツールが含まれています。

## 🛠️ セットアップ方法の選択

### 推奨：Shell Script方式

- **簡単**: 依存関係なし、すぐに実行可能
- **高速**: 直接SSH実行で効率的
- **デバッグしやすい**: ログが見やすい

### 代替：Ansible方式

- **冪等性**: 同じ状態を保証
- **スケーラブル**: 大規模環境向け
- **設定管理**: YAML形式での管理

## 🚀 Shell Script方式（推奨）

### 前提条件

- Proxmoxサーバーへのアクセス権限（root権限または管理者権限）
- ProxmoxホストでSSHキーが設定済み
- 十分なストレージ容量（VM 3台 × 100GB + 50GB バッファ = 約350GB）

### 基本的な使用方法

```bash
# スクリプトに実行権限を付与
chmod +x create-vms.sh

# 全VM作成（ファイアウォール設定込み）
./create-vms.sh

# ヘルプ表示
./create-vms.sh --help
```

### 高度な使用方法

```bash
# 既存VMにファイアウォール設定のみ適用
./create-vms.sh firewall

# 既存VM削除後、新規作成
qm stop 101 102 103
qm destroy 101 102 103
./create-vms.sh
```

### 作成されるVM仕様

| 項目 | 値 |
|------|-----|
| VM数 | 3台 (Master×1, Worker×2) |
| メモリ | 4GB RAM / VM |
| CPU | 2コア / VM |
| ディスク | 100GB / VM |
| OS | Ubuntu 22.04 LTS |
| ネットワーク | 192.168.10.101-103 |

### ファイアウォール設定

各VMには以下のファイアウォール設定が自動適用されます：

- SSH (ポート22) の全許可
- UFWファイアウォールの有効化

## 🔄 Ansible方式（代替）

大規模環境や冪等性を重視する場合は、Ansible方式を使用できます。

### 前提条件

```bash
# Ansibleのインストール（Proxmoxホスト上で）
apt update
apt install -y ansible
```

### 使用方法

```bash
cd 01-vm-creation/alternative-ansible-setup

# 設定ファイルの編集
vim vars.yml
vim inventory.ini

# プレイブックの実行
ansible-playbook -i inventory.ini playbook.yml
```

### 設定ファイル

- `alternative-ansible-setup/vars.yml`: VM設定とProxmox接続情報
- `alternative-ansible-setup/inventory.ini`: ホスト定義
- `alternative-ansible-setup/playbook.yml`: メインプレイブック

### Shell Script方式との比較

| 項目 | Shell Script | Ansible |
|------|-------------|---------|
| **学習コスト** | 低い | 中程度 |
| **実行速度** | 高速 | 中程度 |
| **デバッグ** | 簡単 | 中程度 |
| **冪等性** | 手動実装 | 自動保証 |
| **スケーラビリティ** | 限定的 | 高い |
| **設定管理** | Shell変数 | YAML |
| **依存関係** | なし | Ansible必須 |

詳細は `alternative-ansible-setup/README.md` を参照してください。

## トラブルシューティング

### SSH接続の問題

```bash
# SSH接続テスト
ssh ubuntu@192.168.10.101
ssh ubuntu@192.168.10.102
ssh ubuntu@192.168.10.103

# ポート確認
nc -zv 192.168.10.101 22
nc -zv 192.168.10.102 22
nc -zv 192.168.10.103 22
```

### ファイアウォールの問題

```bash
# 既存VMにファイアウォール設定を適用
./create-vms.sh firewall
```

### VM状態確認

```bash
# VM状態確認
qm status 101
qm status 102  
qm status 103

# VM再起動
qm stop <vm_id>
qm start <vm_id>
```

## 次のステップ

VMの作成が完了したら、Kubernetesクラスターのセットアップを開始してください：

```bash
cd ../02-k8s-cluster
./setup-k8s-cluster.sh
```

## 📚 参考情報

- [Proxmox VE公式ドキュメント](https://pve.proxmox.com/pve-docs/)
- [Cloud-init公式ドキュメント](https://cloud-init.io/)
- [Ansible公式ドキュメント](https://docs.ansible.com/) （Ansible方式使用時）
