---
title: "デプロイワークフロー"
weight: 2
---

# デプロイワークフロー

開発者がアプリケーションをデプロイするまでの流れを説明します。

## ワークフロー概要

```
1. コード変更 → 2. GitHub Push → 3. CI/CDビルド → 4. K8sデプロイ
```

## 手動デプロイ（開発時）

### 1. マニフェスト作成

```yaml
# deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: my-app
spec:
  replicas: 2
  selector:
    matchLabels:
      app: my-app
  template:
    metadata:
      labels:
        app: my-app
    spec:
      containers:
      - name: my-app
        image: my-app:latest
        ports:
        - containerPort: 8080
```

### 2. デプロイ実行

```bash
kubectl apply -f deployment.yaml
kubectl apply -f service.yaml

# 状態確認
kubectl get pods -w
```

### 3. 動作確認

```bash
# ログ確認
kubectl logs -f deployment/my-app

# ポートフォワード
kubectl port-forward svc/my-app 8080:80
```

## CI/CDパイプライン（本番向け）

### GitHub Actions 例

```yaml
# .github/workflows/deploy.yaml
name: Deploy to K8s

on:
  push:
    branches: [main]

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      
      - name: Build and Push Image
        run: |
          docker build -t my-app:${{ github.sha }} .
          docker push my-app:${{ github.sha }}
      
      - name: Deploy to K8s
        run: |
          kubectl set image deployment/my-app my-app=my-app:${{ github.sha }}
```

## ロールバック

```bash
# デプロイ履歴確認
kubectl rollout history deployment/my-app

# 前のバージョンに戻す
kubectl rollout undo deployment/my-app

# 特定のリビジョンに戻す
kubectl rollout undo deployment/my-app --to-revision=2
```

