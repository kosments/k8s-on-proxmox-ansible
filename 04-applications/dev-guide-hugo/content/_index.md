---
title: "Home K8s 開発ガイド"
type: docs
---

# 🏠 Home Kubernetes 開発ガイド

Proxmox + k3s で構築した自宅 Kubernetes 環境の統合ドキュメントです。

## 🚀 クイックスタート

{{< columns >}}
### 開発者向け

アプリケーションのデプロイ方法、CI/CD設定など

[はじめる →]({{< ref "/getting-started" >}})

<--->

### インフラ管理者向け

クラスター運用、トラブルシューティングなど

[運用ガイド →]({{< ref "/operations" >}})

{{< /columns >}}

## 📊 クラスター情報

| ノード | IPアドレス | 役割 |
|--------|------------|------|
| k8s-master | 192.168.10.111 | Control Plane |
| k8s-worker1 | 192.168.10.112 | Worker |
| k8s-worker2 | 192.168.10.113 | Worker |

## 📚 ドキュメント

- [**はじめに**]({{< ref "/getting-started" >}}) - 環境構築からデプロイまで
- [**アーキテクチャ**]({{< ref "/architecture" >}}) - システム構成の解説
- [**運用ガイド**]({{< ref "/operations" >}}) - 日常的な運用手順
- [**トラブルシューティング**]({{< ref "/troubleshooting" >}}) - 問題解決ガイド

