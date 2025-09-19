# k8s proxmox 

## Proxmox 基本用語

### 仮想化関連
- **VM (Virtual Machine)**: 完全仮想化された仮想マシン。KVMを使用。
- **CT (Container)**: LXCベースのコンテナ。VMより軽量。
- **Template**: VMやCTのテンプレート。新規作成時のベースとなる。
- **Clone**: テンプレートから作成されたVMやCTのコピー。
  - **Full Clone**: 完全なコピー。元のディスクと独立。
  - **Linked Clone**: 差分のみを保存。元のディスクに依存。

### ストレージ関連
- **local**: ノードのローカルディレクトリ（/var/lib/proxmox）
- **local-lvm**: ノードのLVMストレージ。デフォルトのVM用ストレージ。
- **ZFS**: より高度なファイルシステム。スナップショットやRAID機能。

### ネットワーク関連
- **vmbr0**: デフォルトの仮想ブリッジ。通常、物理NICと接続。
- **VLAN**: 仮想LANによるネットワークの分離。
- **Cloud-Init**: VM初期設定用のツール（IPアドレス、SSHキーなど）。

### システム関連
- **Node**: Proxmoxをインストールした物理サーバー。
- **Cluster**: 複数のノードをまとめた集合。
- **Pool**: VMやCTを論理的にグループ化する単位。
- **DC (Datacenter)**: クラスタ全体の設定を管理する単位。

### ID体系
- **VMID**: VMやCTを識別する番号（100-999999）
  - 100-999: ユーザー用
  - 1000-999999: システム用推奨

## SSH

```sh
# ssh to host vm
ssh root@192.168.10.108

# ssh to k8s-master
ssh ubuntu@192.168.10.101

# ssh to k8s-node1
ssh ubuntu@192.168.10.102

# ssh to k8s-node2
ssh ubuntu@192.168.10.103
```

## 同ネットワーク内の VM 宛に 22番ポートが空いているか確認する方法

`lsof` は自分のローカルマシン上のソケットを確認するコマンドなので、リモート VM のポート確認には使えない。 
リモートのポート確認には以下の方法を使用。

### 1. `nc` (netcat) で確認

```bash
nc -zv <VM_IP> 22
# 例:
nc -zv 192.168.10.101 22
nc -zv 192.168.10.102 22
nc -zv 192.168.10.103 22
# -z : ポートスキャンモード（データ送信なし）
# -v : 詳細出力
# 成功すれば succeeded! と表示されます。
```

### 2. telnet で確認

```bash
telnet <VM_IP> 22
# 成功すると SSH のバナーが返ることがあります
# 失敗すると接続拒否やタイムアウトになります
```

### 3. ssh で接続テスト

```bash
ssh -v <user>@<VM_IP>
# -v オプションで詳細な接続情報を表示
# 「Connection refused」 → ポート閉じている
# 「Timed out」 → ネットワーク到達不可
```

### 4. ping でネットワーク到達確認

```bash
ping <VM_IP>
# まず ICMP が通るか確認すると SSH の接続可否の判断がしやすくなります
```

## ホストキーの管理

VMを再作成した場合や、SSHホストキーが変更された場合の対処方法：

### 1. 特定のホストキーの削除

```bash
# 特定のIPアドレスのホストキーを削除
ssh-keygen -f "~/.ssh/known_hosts" -R "192.168.10.101"
ssh-keygen -f "~/.ssh/known_hosts" -R "192.168.10.102"
ssh-keygen -f "~/.ssh/known_hosts" -R "192.168.10.103"
```

### 2. 既知のホストキーをすべて削除

```bash
# すべてのホストキーを削除（注意: すべてのホストの情報が削除されます）
rm ~/.ssh/known_hosts
```

### 3. SSHの初回接続時に自動的にホストキーを受け入れる

```bash
# StrictHostKeyCheckingをnoに設定して接続
ssh -o StrictHostKeyChecking=no ubuntu@192.168.10.101
```

### 4. 現在のホストキーの確認

```bash
# ホストキーのフィンガープリントを表示
ssh-keygen -l -f /etc/ssh/ssh_host_ed25519_key.pub
```
