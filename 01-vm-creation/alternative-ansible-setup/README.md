# 代替セットアップ（Ansible）- VM作成

このディレクトリには、AnsibleでProxmoxVMを作成する代替手順が含まれています。

## 📋 概要

Shell Scriptによるセットアップが推奨されていますが、以下の場合にAnsible方式が有用です：

- **大規模環境**: 多数のVMを管理する場合
- **冪等性**: 同じ状態を繰り返し保証したい場合
- **設定管理**: YAML形式での設定管理を好む場合
- **企業環境**: Ansibleが標準化されている環境

## 🏗️ 構成内容

```
alternative-ansible-setup/
├── create_vm.yml         # VM作成用プレイブック
├── playbook.yml          # メインプレイブック
├── inventory.ini         # インベントリファイル
├── vars.yml              # 変数定義
└── README.md             # このファイル
```

## 🚀 使用方法

### 前提条件

```bash
# Ansibleのインストール（Proxmoxホスト上で）
apt update
apt install -y ansible

# ProxmoxホストへのSSHアクセス権限
# 適切なProxmoxユーザー権限
```

### 基本的な実行

```bash
cd 01-vm-creation/alternative-ansible-setup

# 設定ファイルの編集
vim vars.yml
vim inventory.ini

# プレイブックの実行
ansible-playbook -i inventory.ini playbook.yml
```

## ⚙️ 設定のカスタマイズ

### インベントリファイル（`inventory.ini`）

```ini
[proxmox]
proxmox-host ansible_host=your-proxmox-host ansible_user=root
```

### 変数ファイル（`vars.yml`）

```yaml
proxmox_host: "your-proxmox-host"
proxmox_user: "root@pam"
proxmox_password: "your-password"

# VMの基本設定
vm_template: "ubuntu-2204-cloudinit-template"
vm_storage: "local-lvm"
vm_network_bridge: "vmbr0"

# Kubernetesノード設定
master_node:
  name: "k8s-master"
  id: 101
  cpu: 2
  memory: 4096
  disk: "100G"
  ip: "192.168.10.101"

worker_nodes:
  - name: "k8s-worker1"
    id: 102
    cpu: 2
    memory: 4096
    disk: "100G"
    ip: "192.168.10.102"
  - name: "k8s-worker2"
    id: 103
    cpu: 2
    memory: 4096
    disk: "100G"
    ip: "192.168.10.103"
```

## 📊 Shell Script方式との比較

| 項目 | Shell Script | Ansible |
|------|-------------|---------|
| **学習コスト** | 低い | 中程度 |
| **実行速度** | 高速 | 中程度 |
| **デバッグ** | 簡単 | 中程度 |
| **冪等性** | 手動実装 | 自動保証 |
| **スケーラビリティ** | 限定的 | 高い |
| **設定管理** | Shell変数 | YAML |
| **依存関係** | なし | Ansible必須 |

## 🔍 トラブルシューティング

### Ansible接続エラー

```bash
# Proxmoxホストへの接続テスト
ansible -i inventory.ini proxmox -m ping

# SSH接続の問題
ssh-keygen -f "/root/.ssh/known_hosts" -R "your-proxmox-host"

# パスワード認証の使用
ansible-playbook -i inventory.ini playbook.yml --ask-pass
```

### プレイブック実行エラー

```bash
# 詳細ログで実行
ansible-playbook -i inventory.ini playbook.yml -vvv

# ドライランで確認
ansible-playbook -i inventory.ini playbook.yml --check

# 特定のタスクから再開
ansible-playbook -i inventory.ini playbook.yml --start-at-task="Create VMs"
```

### VM作成エラー

```bash
# Proxmoxホストでの確認
ssh root@your-proxmox-host 'qm list'

# ストレージ容量の確認
ssh root@your-proxmox-host 'pvs && lvs'

# テンプレートの確認
ssh root@your-proxmox-host 'qm list | grep template'
```

## 🛠️ メンテナンス

### プレイブックの更新

```bash
# 変数の更新
vim vars.yml

# 設定の反映
ansible-playbook -i inventory.ini playbook.yml --tags="vm-config"
```

### VMの追加

```bash
# vars.ymlでworker_nodesに追加
vim vars.yml

# 新しいVMのみ作成
ansible-playbook -i inventory.ini playbook.yml --limit="new-vm"
```

## 📚 参考情報

- [Ansible公式ドキュメント](https://docs.ansible.com/)
- [Proxmox Ansible Collection](https://github.com/community-general/ansible.posix)
- [Ansible Best Practices](https://docs.ansible.com/ansible/latest/user_guide/playbooks_best_practices.html)

## 🔄 Shell Script方式への切り替え

Ansible方式で問題が発生した場合、いつでもShell Script方式に切り替えできます：

```bash
# VMの削除（必要に応じて）
ssh root@your-proxmox-host 'qm stop 101 102 103 && qm destroy 101 102 103'

# Shell Script方式で再作成
cd ..
./create-vms.sh
```

## 📝 次のステップ

VMの作成が完了したら、Kubernetesクラスターのセットアップを開始してください：

```bash
cd ../../02-k8s-cluster
./setup-k8s-cluster.sh

# または、Ansible方式を使用
cd ../../02-k8s-cluster/alternative-ansible-setup
ansible-playbook -i inventory.ini sequential-playbook.yml
```
