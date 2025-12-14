---
title: "コード管理とGitHub連携"
weight: 2
---

# コード管理とGitHub連携

アプリケーションコードとインフラコードの管理方法を説明します。

## リポジトリ構成

```
kosments/
├── k8s-on-proxmox-ansible/     # インフラ管理
│   ├── scripts/                # クラスター構築スクリプト
│   ├── 04-applications/        # アプリケーションマニフェスト
│   └── docs/                   # ドキュメント
│
└── my-app/                     # アプリケーションコード
    ├── src/
    ├── Dockerfile
    └── k8s/                    # アプリ専用マニフェスト
```

## ブランチ戦略

```
main (production)
  │
  ├── develop (staging)
  │     │
  │     ├── feature/xxx
  │     └── feature/yyy
  │
  └── hotfix/xxx
```

## コード変更からデプロイまで

### 1. ローカルで変更

```bash
git checkout -b feature/new-feature
# 変更を実施
git add .
git commit -m "feat: 新機能追加"
```

### 2. GitHub Push

```bash
git push origin feature/new-feature
# Pull Request作成
```

### 3. レビュー & マージ

```bash
# mainにマージ後、自動デプロイ
# または手動デプロイ
kubectl apply -f k8s/
```

## マニフェスト変更時の手順

```bash
# 1. ローカルで変更
vim 04-applications/my-app/deployment.yaml

# 2. 差分確認
kubectl diff -f 04-applications/my-app/

# 3. 適用
kubectl apply -f 04-applications/my-app/

# 4. 確認
kubectl get pods -w

# 5. コミット
git add .
git commit -m "chore: レプリカ数を3に変更"
git push
```

## GitOps（将来計画）

ArgoCD を使用した GitOps の導入を検討中。

```yaml
# argocd-application.yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: my-app
spec:
  source:
    repoURL: https://github.com/kosments/k8s-on-proxmox-ansible
    path: 04-applications/my-app
  destination:
    server: https://kubernetes.default.svc
    namespace: default
```

