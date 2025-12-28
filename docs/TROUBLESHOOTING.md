# トラブルシューティングガイド

## 🔴 IP競合問題

自宅ネットワークでは、他のデバイス（PC、スマートフォン、IoTデバイスなど）がIPアドレスを使用している場合があります。

### 症状

- VMは起動しているが、Pingが通らない
- ARPテーブルに異なるMACアドレスが表示される
- SSH接続がタイムアウトする

### 診断方法

```bash
# 1. ARPテーブルを確認
ip neigh show | grep 192.168.10

# 2. VMのMACアドレスを確認
qm config 101 | grep net

# 3. 比較して競合を検出
# ARPのMACとVMのMACが異なれば競合
```

### 例：競合の検出

```bash
# ARPテーブル
192.168.10.101 dev vmbr0 lladdr 7c:ed:c6:b4:d3:50 REACHABLE

# VMのMAC
net0: virtio=BC:24:11:B4:23:DE,bridge=vmbr0

# → MACアドレスが異なる = IP競合！
```

### 解決方法

#### 方法1: 自動IP選択（推奨）

`01-clone-vms.sh` は自動的に空いているIPを検出して選択します。

```bash
./01-clone-vms.sh

# 出力例:
# [INFO] === IP競合チェック開始 ===
# [INFO] 範囲: 192.168.10.201 - 192.168.10.130
# [WARN] 192.168.10.201 は使用中 - スキップ
# [INFO] VM 1: 192.168.10.115 (空き確認済み)
```

#### 方法2: 手動でIP変更

```bash
# VMを停止
qm stop 101

# IPアドレスを変更
qm set 101 --ipconfig0 ip=192.168.10.120/24,gw=192.168.10.1

# VMを起動
qm start 101
```

#### 方法3: ARPキャッシュをクリア

```bash
# 古いARPエントリを削除
ip neigh del 192.168.10.101 dev vmbr0

# 再度Ping
ping 192.168.10.101
```

### 予防策

1. **DHCPの範囲を確認**: ルーターのDHCP範囲と重ならないIPを使用
2. **固定IP範囲を決める**: 例：192.168.10.110-130 をK8s用に予約
3. **スクリプトの自動チェック**: `01-clone-vms.sh` の自動検出を使用

---

## 🔴 SSHに接続できない

### 症状

- Pingは通るがSSHに接続できない
- `Connection refused` または `Connection timed out`

### 診断方法

```bash
# ポート22が開いているか確認
nc -zv 192.168.10.201 22

# SSHバナーを確認
echo | nc 192.168.10.201 22
```

### 解決方法

1. **Cloud-init完了を待つ**: 初回起動時は2-3分かかることがある

2. **VMコンソールから確認**:
```bash
qm terminal 101
# ログインして確認
sudo systemctl status ssh
```

3. **SSHサービス再起動**:
```bash
sudo systemctl restart ssh
```

---

## 🔴 k3sが起動しない

### 症状

- `kubectl get nodes` がタイムアウト
- k3sサービスがfailed状態

### 診断方法

```bash
# マスターノードで実行
sudo systemctl status k3s
sudo journalctl -u k3s -f
```

### 解決方法

1. **k3sを再起動**:
```bash
sudo systemctl restart k3s
```

2. **k3sを再インストール**:
```bash
/usr/local/bin/k3s-uninstall.sh
curl -sfL https://get.k3s.io | sh -
```

---

## 🔴 ワーカーノードが参加しない

### 症状

- `kubectl get nodes` にワーカーが表示されない
- k3s-agentがエラー

### 診断方法

```bash
# ワーカーノードで実行
sudo systemctl status k3s-agent
sudo journalctl -u k3s-agent -f
```

### 解決方法

1. **マスターへの接続確認**:
```bash
nc -zv 192.168.10.201 6443
```

2. **トークンを再取得して参加**:
```bash
# マスターでトークン取得
sudo cat /var/lib/rancher/k3s/server/node-token

# ワーカーで再参加
/usr/local/bin/k3s-agent-uninstall.sh
curl -sfL https://get.k3s.io | K3S_URL=https://192.168.10.201:6443 K3S_TOKEN=<token> sh -
```

---

## 🔴 Podが起動しない

### 症状

- Podが`Pending`や`CrashLoopBackOff`状態

### 診断方法

```bash
kubectl describe pod <pod-name>
kubectl logs <pod-name>
```

### よくある原因

1. **リソース不足**: ノードのCPU/メモリが不足
2. **イメージプル失敗**: ネットワーク問題またはイメージ名の誤り
3. **PVC未作成**: 必要なPersistentVolumeClaimが存在しない

---

## 🛠️ 便利なコマンド

### クラスター状態確認

```bash
export KUBECONFIG=/root/k8s-on-proxmox-ansible/kubeconfig
kubectl get nodes -o wide
kubectl get pods -A
kubectl cluster-info
```

### VM操作

```bash
# VM一覧
qm list

# VM停止/起動
qm stop 101
qm start 101

# VM削除
qm destroy 101 --purge

# VM設定確認
qm config 101
```

### ネットワーク診断

```bash
# ARPテーブル
ip neigh show

# ネットワークスキャン
for i in $(seq 110 130); do ping -c 1 -W 1 192.168.10.$i & done; wait
```

