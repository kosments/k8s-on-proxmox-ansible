# 03 - 基盤サービス（Manifests）

このディレクトリには、Kubernetesクラスターにデプロイする基盤サービスのマニフェストファイルとセットアップスクリプトが含まれています。

## 🏗️ 基盤サービス概要

### 1. 監視システム（`monitoring/`）

Prometheus + Grafanaによる監視スタック

```bash
cd monitoring
chmod +x setup-monitoring.sh
./setup-monitoring.sh

# アクセス: http://<node-ip>:30300 (admin/admin123)
```

### 2. ログ集約（`logging/`）

Grafana Lokiによるログ管理

```bash
cd logging
chmod +x setup-logging.sh
./setup-logging.sh
```

### 3. Service Mesh（`istio/`）

Istioによるマイクロサービス通信管理

```bash
cd istio
chmod +x setup-istio.sh
./setup-istio.sh
```

### 4. GitOps（`argocd/`）

ArgoCDによる継続的デリバリー

```bash
kubectl apply -f argocd/bootstrap.yaml

# パスワード取得
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
kubectl port-forward svc/argocd-server -n argocd 8080:443
```

## 🔄 推奨デプロイ順序

1. **監視システム** - クラスターの状態監視
2. **ログ集約** - アプリケーションログの収集
3. **Service Mesh** - マイクロサービス通信の管理
4. **GitOps** - 継続的デリバリーの自動化

```bash
# 全体セットアップ
cd monitoring && ./setup-monitoring.sh && cd ..
cd logging && ./setup-logging.sh && cd ..
cd istio && ./setup-istio.sh && cd ..
kubectl apply -f argocd/bootstrap.yaml
```

## ⚙️ 設定のカスタマイズ

必要に応じて、以下の設定をカスタマイズできます：

- **監視**: `monitoring/setup-monitoring.sh` 内のリソース制限
- **ログ**: `logging/setup-logging.sh` 内のストレージ設定
- **Istio**: `istio/install.yaml` 内のコンポーネント設定
- **ArgoCD**: `argocd/bootstrap.yaml` 内のリソース制限

## 📚 次のステップ

基盤サービスの設定が完了したら、アプリケーションをデプロイしてください：

```bash
cd ../04-applications
kubectl apply -f sample-app.yaml
```
