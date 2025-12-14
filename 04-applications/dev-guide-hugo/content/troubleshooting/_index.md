---
title: "トラブルシューティング"
weight: 4
---

# トラブルシューティング

よくある問題と解決方法を説明します。

## 🔴 IP競合問題

自宅ネットワークでは、他のデバイスとIPアドレスが競合することがあります。

### 症状

- VMは起動しているが、Pingが通らない
- ARPテーブルに異なるMACアドレスが表示される

### 診断方法

```bash
# ARPテーブルを確認
ip neigh show | grep 192.168.10

# VMのMACアドレスを確認
qm config 101 | grep net

# 比較して競合を検出
# ARPのMACとVMのMACが異なれば競合！
```

### 解決方法

```bash
# 1. スクリプトの自動検出を使用（推奨）
./scripts/01-clone-vms.sh

# 2. 手動でIP変更
qm stop 101
qm set 101 --ipconfig0 ip=192.168.10.120/24,gw=192.168.10.1
qm start 101
```

### 予防策

- DHCPの範囲と重ならないIPを使用
- 192.168.10.110-130 をK8s用に予約

---

## 🔴 SSHに接続できない

### 症状

- Pingは通るがSSHに接続できない

### 診断

```bash
# ポート確認
nc -zv 192.168.10.111 22
```

### 解決

1. Cloud-init完了を待つ（2-3分）
2. VMコンソールから確認: `qm terminal 101`

---

## 🔴 Podが起動しない

### 診断

```bash
kubectl describe pod <pod-name>
kubectl logs <pod-name>
```

### よくある原因

1. **リソース不足**: ノードのCPU/メモリ不足
2. **イメージプル失敗**: ネットワーク問題
3. **PVC未作成**: 必要なボリュームがない

---

## 🛠️ 便利なデバッグコマンド

```bash
# Pod内でシェル実行
kubectl exec -it <pod-name> -- /bin/sh

# 一時的なデバッグPod
kubectl run debug --rm -it --image=busybox -- /bin/sh

# イベント確認
kubectl get events --sort-by='.lastTimestamp'
```

