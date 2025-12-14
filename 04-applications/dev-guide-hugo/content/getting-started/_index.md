---
title: "はじめに"
weight: 1
---

# はじめに

このセクションでは、自宅 Kubernetes 環境の基本的な使い方を説明します。

## 前提条件

- kubectl がインストールされていること
- kubeconfigファイルへのアクセス

## kubeconfigの設定

```bash
# kubeconfigをローカルにコピー
scp root@192.168.10.108:/root/k8s-on-proxmox-ansible/kubeconfig ~/.kube/config-home

# 環境変数を設定
export KUBECONFIG=~/.kube/config-home

# 接続確認
kubectl get nodes
```

## 最初のアプリケーションデプロイ

```bash
# サンプルアプリをデプロイ
kubectl create deployment hello --image=nginx:alpine
kubectl expose deployment hello --port=80 --type=NodePort

# アクセス
kubectl get svc hello
# http://192.168.10.111:<NodePort>
```

