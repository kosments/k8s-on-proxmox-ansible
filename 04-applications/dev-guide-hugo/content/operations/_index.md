---
title: "運用ガイド"
weight: 3
---

# 運用ガイド

クラスターの日常的な運用手順を説明します。

## 日常的な確認コマンド

```bash
# ノード状態
kubectl get nodes -o wide

# 全Pod確認
kubectl get pods -A

# リソース使用状況
kubectl top nodes
kubectl top pods -A
```

## VM操作（Proxmox）

```bash
# SSH接続
ssh root@192.168.10.108

# VM一覧
qm list

# VM停止/起動
qm stop 101
qm start 101

# VM再起動
qm reboot 101
```

## クラスター再起動後の確認

```bash
# 1. 全ノードがReadyか確認
kubectl get nodes

# 2. システムPodが正常か確認
kubectl get pods -n kube-system

# 3. サービス確認
kubectl get svc -A
```

## バックアップ

### kubeconfig バックアップ

```bash
cp /root/k8s-on-proxmox-ansible/kubeconfig ~/backup/kubeconfig-$(date +%Y%m%d)
```

### etcd バックアップ（k3s）

```bash
# マスターノードで実行
sudo k3s etcd-snapshot save --name backup-$(date +%Y%m%d)
```

