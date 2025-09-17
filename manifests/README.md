# Kubernetes Manifests

このディレクトリには、Kubernetesクラスターにデプロイする追加コンポーネントのマニフェストファイルが含まれています。

## コンポーネントの概要

### 1. ArgoCD（`argocd/`）

GitOpsワークフローを実現するための継続的デリバリーツール。

```bash
# ArgoCDのインストール
kubectl apply -f argocd/bootstrap.yaml

# ArgoCD UIへのアクセス（デフォルトパスワードは初期admin podの名前）
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
kubectl port-forward svc/argocd-server -n argocd 8080:443
```

### 2. Istio（`istio/`）

サービスメッシュを提供し、マイクロサービス間の通信を管理します。

```bash
# Istioのインストール
kubectl apply -f istio/install.yaml

# Istioインジェクションの有効化（必要な名前空間で）
kubectl label namespace <namespace> istio-injection=enabled
```

### 3. アプリケーション（`apps/`）

クラスターにデプロイするアプリケーションのマニフェスト。

## デプロイ順序

1. ArgoCD
2. Istio
3. アプリケーション

各コンポーネントのデプロイ前に、対応するREADMEファイルを参照して詳細な手順を確認してください。

## 設定のカスタマイズ

必要に応じて、以下の設定をカスタマイズできます：

- ArgoCD: `argocd/bootstrap.yaml` 内のリソース制限
- Istio: `istio/install.yaml` 内のコンポーネントと設定
- アプリケーション: 各アプリケーションディレクトリ内の設定値