# 代替セットアップ（Ansible）

このディレクトリには、Ansibleを使用したKubernetesクラスター構築の代替手順が含まれています。

## 📋 概要

Shell Scriptによるセットアップが推奨されていますが、以下の場合にAnsible方式が有用です：

- **大規模環境**: 多数のノードを管理する場合
- **冪等性**: 同じ状態を繰り返し保証したい場合
- **設定管理**: YAML形式での設定管理を好む場合
- **企業環境**: Ansibleが標準化されている環境

## 🏗️ 構成内容

```
alternative-ansible-setup/
├── ansible/                    # Ansibleロールとプレイブック
│   ├── ansible.cfg             # Ansible設定
│   ├── inventory.ini           # インベントリファイル
│   ├── playbook.yml            # メインプレイブック
│   └── roles/                  # ロール定義
│       ├── common/             # 共通設定
│       ├── master/             # マスターノード設定
│       └── node/               # ワーカーノード設定
├── sequential-playbook.yml     # K8s構築用順次実行プレイブック
├── inventory.ini               # K8s用インベントリ
└── README.md                   # このファイル
```

## 🚀 使用方法

### 前提条件

```bash
# Ansibleのインストール（Proxmoxホスト上で）
apt update
apt install -y ansible sshpass

# VMが作成済みであること
cd ../../01-vm-creation
./create-vms.sh
```

### 方法1: Ansibleロールを使用（推奨）

```bash
cd ansible

# インベントリファイルの確認・編集
vim inventory.ini

# プレイブックの実行
ansible-playbook -i inventory.ini playbook.yml
```

### 方法2: 順次実行プレイブックを使用

```bash
# インベントリファイルの確認・編集
vim inventory.ini

# K8s構築プレイブックの実行
ansible-playbook -i inventory.ini sequential-playbook.yml
```

## ⚙️ 設定のカスタマイズ

### インベントリファイル（`ansible/inventory.ini`）

```ini
[masters]
k8s-master ansible_host=192.168.10.101 ansible_user=ubuntu ansible_ssh_private_key_file=~/.ssh/id_rsa

[workers]
k8s-node1 ansible_host=192.168.10.102 ansible_user=ubuntu ansible_ssh_private_key_file=~/.ssh/id_rsa
k8s-node2 ansible_host=192.168.10.103 ansible_user=ubuntu ansible_ssh_private_key_file=~/.ssh/id_rsa

[k8s_cluster:children]
masters
workers

[all:vars]
ansible_ssh_common_args='-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null'
```

### 共通設定（`ansible/roles/common/tasks/main.yml`）

- Docker/containerdのインストール
- Kubernetesコンポーネントの導入
- システム設定（swap無効化など）

### マスターノード設定（`ansible/roles/master/tasks/main.yml`）

- kubeadm initの実行
- CNI（Flannel）の導入
- kubeconfigの設定

### ワーカーノード設定（`ansible/roles/node/tasks/main.yml`）

- クラスターへの参加
- ノードの設定

## 🔍 トラブルシューティング

### Ansible接続エラー

```bash
# SSH接続テスト
ansible -i inventory.ini all -m ping

# SSH鍵の問題
ssh-keygen -f "/root/.ssh/known_hosts" -R "192.168.10.101"
ssh-keygen -f "/root/.ssh/known_hosts" -R "192.168.10.102"
ssh-keygen -f "/root/.ssh/known_hosts" -R "192.168.10.103"

# パスワード認証の使用
ansible-playbook -i inventory.ini playbook.yml --ask-pass
```

### プレイブック実行エラー

```bash
# 詳細ログで実行
ansible-playbook -i inventory.ini playbook.yml -vvv

# 特定のタスクから再開
ansible-playbook -i inventory.ini playbook.yml --start-at-task="Install kubeadm"

# ドライランで確認
ansible-playbook -i inventory.ini playbook.yml --check
```

### クラスター状態の確認

```bash
# マスターノードでkubectl実行
ansible -i inventory.ini masters -m shell -a "sudo kubectl get nodes"

# ワーカーノードの状態確認
ansible -i inventory.ini workers -m shell -a "sudo systemctl status kubelet"
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

## 🛠️ メンテナンス

### プレイブックの更新

```bash
# ロールの更新
vim ansible/roles/common/tasks/main.yml

# 設定の反映
ansible-playbook -i inventory.ini playbook.yml --tags="common"
```

### ノードの追加

```bash
# インベントリにノードを追加
vim ansible/inventory.ini

# 新しいノードのみセットアップ
ansible-playbook -i inventory.ini playbook.yml --limit="new-node"
```

## 📚 参考情報

- [Ansible公式ドキュメント](https://docs.ansible.com/)
- [Kubernetes Ansible Collection](https://github.com/kubernetes-sigs/kubespray)
- [Ansible Best Practices](https://docs.ansible.com/ansible/latest/user_guide/playbooks_best_practices.html)

## 🔄 Shell Script方式への切り替え

Ansible方式で問題が発生した場合、いつでもShell Script方式に切り替えできます：

```bash
# VMのリセット（必要に応じて）
ansible -i inventory.ini all -m shell -a "sudo kubeadm reset -f"

# Shell Script方式で再構築
cd ..
./setup-k8s-cluster.sh
```
