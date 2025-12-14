# k8s-on-proxmox-ansible

Proxmox VE上にk3s Kubernetesクラスターを構築するためのシンプルなツールセットです。

## 🎯 特徴

- **シンプル**: 3つのスクリプトで完結
- **確実**: テンプレートクローン方式で安定したVM作成
- **軽量**: k3sによる軽量Kubernetesクラスター
- **トラブルシューティングしやすい**: 各ステップが明確に分離

## 📁 構成

```
k8s-on-proxmox-ansible/
├── scripts/
│   ├── 01-clone-vms.sh      # Step 1: VMをクローン作成
│   ├── 02-setup-k3s.sh      # Step 2: k3sをインストール
│   └── 03-verify-cluster.sh # Step 3: クラスター確認
├── kubeconfig               # kubectl設定ファイル（生成される）
└── README.md
```

## 🚀 クイックスタート

### 前提条件

- Proxmox VE 7.x以上
- テンプレートVM（ID: 9000）が作成済み
- SSH鍵が設定済み（`/root/.ssh/id_rsa`）

### Step 1: VMをクローン作成

```bash
# Proxmoxホスト上で実行
cd /root/k8s-on-proxmox-ansible/scripts
chmod +x *.sh
./01-clone-vms.sh
```

作成されるVM:
- VM 101: k8s-master (192.168.10.111)
- VM 102: k8s-worker1 (192.168.10.112)
- VM 103: k8s-worker2 (192.168.10.113)

### Step 2: k3sをインストール

```bash
./02-setup-k3s.sh
```

### Step 3: クラスター確認

```bash
./03-verify-cluster.sh
```

## 📋 システム要件

### Proxmox環境

- CPU: 4コア以上
- メモリ: 16GB以上
- ストレージ: 200GB以上

### 作成されるVM仕様

| 項目 | 値 |
|------|-----|
| OS | Ubuntu 22.04 LTS |
| メモリ | 4GB / VM |
| CPU | 2コア / VM |
| ディスク | 50GB / VM |
| ネットワーク | 192.168.10.111-113 |

## 🔧 kubectl の使用方法

### Proxmoxホストから

```bash
export KUBECONFIG=/root/k8s-on-proxmox-ansible/kubeconfig
kubectl get nodes
```

### ローカルPC（Mac/Linux）から

```bash
# kubeconfigをコピー
scp root@192.168.10.108:/root/k8s-on-proxmox-ansible/kubeconfig ~/.kube/config-k3s

# 使用
export KUBECONFIG=~/.kube/config-k3s
kubectl get nodes
```

## 🔍 トラブルシューティング

### VMにSSH接続できない

```bash
# Ping確認
ping 192.168.10.101

# SSH確認
nc -zv 192.168.10.101 22

# VMコンソールを確認
qm terminal 101
```

### k3sが起動しない

```bash
# マスターノードで確認
ssh ubuntu@192.168.10.101
sudo systemctl status k3s
sudo journalctl -u k3s -f
```

### ワーカーがクラスターに参加しない

```bash
# ワーカーノードで確認
ssh ubuntu@192.168.10.102
sudo systemctl status k3s-agent
sudo journalctl -u k3s-agent -f

# トークン再取得
ssh ubuntu@192.168.10.101 "sudo cat /var/lib/rancher/k3s/server/node-token"
```

## 🔄 クラスター再構築

```bash
# 全VM削除
for id in 101 102 103; do
    qm stop $id --skiplock
    qm destroy $id --purge
done

# 再構築
./scripts/01-clone-vms.sh
./scripts/02-setup-k3s.sh
```

## 📊 構成図

```
┌─────────────────────────────────────────────────────┐
│                  Proxmox Host                       │
│                 192.168.10.108                      │
│  ┌─────────────────────────────────────────────┐   │
│  │              vmbr0 (Bridge)                  │   │
│  └─────────────────────────────────────────────┘   │
│         │              │              │            │
│  ┌──────┴─────┐ ┌──────┴─────┐ ┌──────┴─────┐     │
│  │ k8s-master │ │k8s-worker1 │ │k8s-worker2 │     │
│  │   VM 101   │ │   VM 102   │ │   VM 103   │     │
│  │192.168.10  │ │192.168.10  │ │192.168.10  │     │
│  │   .111     │ │   .112     │ │   .113     │     │
│  │            │ │            │ │            │     │
│  │  k3s       │ │ k3s-agent  │ │ k3s-agent  │     │
│  │  server    │ │            │ │            │     │
│  └────────────┘ └────────────┘ └────────────┘     │
└─────────────────────────────────────────────────────┘
```

## 📚 参考資料

- [Proxmox VE公式ドキュメント](https://pve.proxmox.com/pve-docs/)
- [k3s公式ドキュメント](https://docs.k3s.io/)
- [Kubernetes公式ドキュメント](https://kubernetes.io/ja/docs/home/)

## SSH接続情報

```bash
# Proxmoxホスト
ssh root@192.168.10.108

# k8s-master
ssh ubuntu@192.168.10.111

# k8s-worker1
ssh ubuntu@192.168.10.112

# k8s-worker2
ssh ubuntu@192.168.10.113
```
