# Sample Web Application

このディレクトリには、KubernetesクラスターにデプロイするサンプルWebアプリケーションのマニフェストファイルが含まれています。

## 📱 アプリケーション概要

### 機能

- **Web UI**: モダンなレスポンシブデザイン
- **ヘルスチェック**: `/health` エンドポイント
- **メトリクス**: `/metrics` エンドポイント（Prometheus対応）
- **環境情報表示**: Pod/Node情報の表示
- **高可用性**: 3レプリカでの冗長構成

### 技術スタック

- **コンテナ**: Nginx 1.25 Alpine
- **フロントエンド**: HTML5 + CSS3 + JavaScript
- **監視**: Prometheus メトリクス対応
- **ロードバランシング**: Kubernetes Service + Ingress

## 🚀 デプロイ手順

### 前提条件

- Kubernetesクラスターが構築済み
- `kubectl` コマンドが利用可能
- kubeconfigが設定済み

### 1. ネームスペース作成

```bash
kubectl apply -f namespace.yaml
```

### 2. アプリケーション設定

```bash
kubectl apply -f configmap.yaml
```

### 3. アプリケーションデプロイ

```bash
kubectl apply -f deployment.yaml
kubectl apply -f service.yaml
```

### 4. イングレス設定（オプション）

```bash
# Ingress Controllerが必要
kubectl apply -f ingress.yaml
```

### 5. デプロイ状況確認

```bash
# ネームスペース確認
kubectl get namespace sample-app

# Pod確認
kubectl get pods -n sample-app -o wide

# サービス確認
kubectl get svc -n sample-app

# イングレス確認
kubectl get ingress -n sample-app
```

## 🌐 アクセス方法

### 1. NodePort経由（推奨）

```bash
# ノードのIPアドレスを確認
kubectl get nodes -o wide

# ブラウザでアクセス
http://192.168.10.101:30080
http://192.168.10.102:30080
http://192.168.10.103:30080
```

### 2. Port Forward経由

```bash
# ローカルポート8080にフォワード
kubectl port-forward -n sample-app svc/sample-web-app-service 8080:80

# ブラウザでアクセス
http://localhost:8080
```

### 3. Ingress経由（設定済みの場合）

```bash
# ドメイン設定が必要
http://sampleapp.com
http://sampleapp.local
```

## 🔍 エンドポイント

### メインアプリケーション

- **URL**: `/`
- **説明**: メインのWebアプリケーション
- **レスポンス**: HTMLページ

### ヘルスチェック

- **URL**: `/health`
- **説明**: アプリケーションの健全性確認
- **レスポンス**: `200 OK` + `healthy`

### メトリクス

- **URL**: `/metrics`
- **説明**: Prometheus用メトリクス
- **レスポンス**: Prometheus形式のメトリクス

## 🛠️ カスタマイズ

### レプリカ数の変更

```yaml
# deployment.yaml
spec:
  replicas: 5  # 3から5に変更
```

### リソース制限の調整

```yaml
# deployment.yaml
resources:
  requests:
    memory: "128Mi"  # 64Miから128Miに変更
    cpu: "200m"      # 100mから200mに変更
  limits:
    memory: "256Mi"  # 128Miから256Miに変更
    cpu: "400m"      # 200mから400mに変更
```

### 環境変数の追加

```yaml
# deployment.yaml
env:
- name: CUSTOM_VAR
  value: "custom-value"
- name: DATABASE_URL
  valueFrom:
    secretKeyRef:
      name: app-secrets
      key: database-url
```

## 📊 監視・ログ

### Prometheus メトリクス

```bash
# メトリクス確認
curl http://192.168.10.101:30080/metrics
```

### アプリケーションログ

```bash
# Pod ログ確認
kubectl logs -n sample-app -l app=sample-web-app

# リアルタイムログ
kubectl logs -n sample-app -l app=sample-web-app -f
```

### リソース使用量

```bash
# Pod リソース使用量
kubectl top pods -n sample-app

# 詳細情報
kubectl describe pods -n sample-app
```

## 🔧 トラブルシューティング

### Podが起動しない

```bash
# Pod 詳細情報
kubectl describe pod -n sample-app <pod-name>

# イベント確認
kubectl get events -n sample-app --sort-by=.metadata.creationTimestamp
```

### サービスにアクセスできない

```bash
# サービス詳細
kubectl describe svc -n sample-app sample-web-app-service

# エンドポイント確認
kubectl get endpoints -n sample-app
```

### イングレスが動作しない

```bash
# Ingress Controller確認
kubectl get pods -n ingress-nginx

# Ingress詳細
kubectl describe ingress -n sample-app sample-web-app-ingress
```

## 📚 次のステップ

1. **Istio Service Mesh統合** → `../03-manifests/istio/`
2. **監視システム連携** → `../05-monitoring/`
3. **CI/CD パイプライン** → `../07-gitops/`
4. **本格的なアプリケーション開発**

## 🔗 関連リンク

- [Kubernetes Deployment Documentation](https://kubernetes.io/docs/concepts/workloads/controllers/deployment/)
- [Kubernetes Service Documentation](https://kubernetes.io/docs/concepts/services-networking/service/)
- [Kubernetes Ingress Documentation](https://kubernetes.io/docs/concepts/services-networking/ingress/)
- [Nginx Documentation](https://nginx.org/en/docs/)
