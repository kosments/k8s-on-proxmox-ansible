---
title: "CI/CDとイメージ管理"
weight: 3
---

# CI/CDとイメージ管理

アプリケーションのビルド、イメージ管理、デプロイの自動化について説明します。

## イメージリポジトリ構成

**推奨: GitHub Container Registry (ghcr.io)**

| 観点 | ghcr.io | ローカルレジストリ | DockerHub |
|------|---------|-------------------|-----------|
| クラスター障害時 | ✅ 独立 | ❌ アクセス不可 | ✅ 独立 |
| CI/CD連携 | ✅ GitHub統合 | △ 設定必要 | ○ 可能 |
| コスト | ✅ 無料枠大 | ✅ 無料 | △ 有料 |
| セキュリティ | ✅ プライベート可 | ○ 内部のみ | ○ プライベート可 |

### なぜghcr.ioを選択したか

1. **クラスター独立性**: クラスターがダウンしてもイメージは保持される
2. **GitHub統合**: GitHub Actionsとシームレスに連携
3. **セキュリティ**: プライベートリポジトリで安全に管理
4. **無料枠**: 個人利用では十分な無料枠

## CI/CDパイプライン

### GitHub Actions ワークフロー

```yaml
# .github/workflows/build-dev-guide.yaml
name: Build and Push Dev Guide

on:
  push:
    branches: [master]
    paths:
      - '04-applications/dev-guide-hugo/**'

jobs:
  build:
    runs-on: ubuntu-latest
    permissions:
      packages: write
    
    steps:
      - uses: actions/checkout@v4
      
      - name: Login to ghcr.io
        uses: docker/login-action@v3
        with:
          registry: ghcr.io
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}
      
      - name: Build and push
        uses: docker/build-push-action@v5
        with:
          context: ./04-applications/dev-guide-hugo
          push: true
          tags: ghcr.io/${{ github.repository }}/dev-guide:latest
```

## デプロイ手順

### 1. イメージビルド（ローカル開発時）

```bash
cd 04-applications/dev-guide-hugo
docker build -t dev-guide:latest .
```

### 2. k3sノードにイメージを転送

```bash
# イメージをtarに保存
docker save dev-guide:latest -o dev-guide.tar

# ノードに転送
scp dev-guide.tar ubuntu@192.168.10.111:/tmp/

# ノードでインポート
ssh ubuntu@192.168.10.111 "sudo ctr -n k8s.io images import /tmp/dev-guide.tar"
```

### 3. ghcr.ioからプル（本番）

```bash
# シークレット作成（初回のみ）
kubectl create secret docker-registry ghcr-secret \
  --docker-server=ghcr.io \
  --docker-username=YOUR_GITHUB_USERNAME \
  --docker-password=YOUR_GITHUB_PAT \
  -n dev-guide

# デプロイ
kubectl apply -f k8s/
```

## イメージタグ戦略

| 環境 | タグ | 説明 |
|------|-----|------|
| 開発 | `dev-guide:latest` | ローカルビルド |
| ステージング | `dev-guide:sha-abc123` | コミットSHA |
| 本番 | `dev-guide:v1.0.0` | セマンティックバージョン |

## ロールバック

```bash
# 前のバージョンに戻す
kubectl rollout undo deployment/dev-guide -n dev-guide

# 特定のバージョンに戻す
kubectl set image deployment/dev-guide \
  dev-guide=ghcr.io/kosments/k8s-on-proxmox-ansible/dev-guide:v1.0.0 \
  -n dev-guide
```

