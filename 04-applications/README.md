# 04 - アプリケーション

このディレクトリには、Kubernetesクラスターにデプロイするアプリケーションのマニフェストファイルが含まれています。

## 📱 アプリケーション概要

### サンプルアプリケーション（`sample-app.yaml`）

NGINXベースのシンプルなWebアプリケーション

```bash
kubectl apply -f sample-app.yaml
```

**アクセス方法:**

- NodePort: `http://<node-ip>:30080`
- Port Forward: `kubectl port-forward -n sample-apps svc/sample-app 8080:80`

## 🚀 デプロイ手順

### 前提条件

- Kubernetesクラスターが構築済み（`02-k8s-cluster`完了）
- `kubectl`コマンドが利用可能
- kubeconfigが設定済み

### 基本的なデプロイ

```bash
# kubeconfigの設定（必要に応じて）
export KUBECONFIG=../02-k8s-cluster/kubeconfig

# サンプルアプリケーションのデプロイ
kubectl apply -f sample-app.yaml

# デプロイ状況の確認
kubectl get pods -n sample-apps
kubectl get services -n sample-apps

# アプリケーションの動作確認
curl http://<node-ip>:30080
```

### アクセス方法の詳細

#### 1. NodePort経由（推奨）

```bash
# ノードのIPアドレスを確認
kubectl get nodes -o wide

# サービスのポート番号を確認
kubectl get svc -n sample-apps

# ブラウザまたはcurlでアクセス
curl http://192.168.10.101:30080
```

#### 2. Port Forward経由

```bash
# ローカルポート8080にフォワード
kubectl port-forward -n sample-apps svc/sample-app 8080:80

# 別ターミナルでアクセス
curl http://localhost:8080
```

## 🔍 トラブルシューティング

### ポッドが起動しない場合

```bash
# ポッドの状態を確認
kubectl get pods -n sample-apps -o wide

# ポッドの詳細情報を確認
kubectl describe pod <pod-name> -n sample-apps

# ログを確認
kubectl logs <pod-name> -n sample-apps
```

### サービスにアクセスできない場合

```bash
# サービスの状態を確認
kubectl get svc -n sample-apps

# エンドポイントを確認
kubectl get endpoints -n sample-apps

# ノードのファイアウォール設定を確認（Proxmoxホスト上で）
ssh ubuntu@192.168.10.101 'sudo ufw status'
```

### ネットワークの問題

```bash
# CNI（Flannel）の状態を確認
kubectl get pods -n kube-flannel

# ノードの状態を確認
kubectl get nodes

# ネットワークポリシーを確認
kubectl get networkpolicies -A
```

## 🛠️ カスタマイズ

### アプリケーションの設定変更

`sample-app.yaml`を編集してアプリケーションをカスタマイズできます：

```yaml
# レプリカ数の変更
spec:
  replicas: 3  # 1から3に変更

# リソース制限の設定
resources:
  requests:
    memory: "64Mi"
    cpu: "250m"
  limits:
    memory: "128Mi"
    cpu: "500m"

# NodePortの変更
spec:
  ports:
  - port: 80
    targetPort: 80
    nodePort: 30081  # 30080から30081に変更
```

### 新しいアプリケーションの追加

1. 新しいマニフェストファイルを作成
2. 適切な名前空間を設定
3. サービスタイプを選択（ClusterIP、NodePort、LoadBalancer）

## 📚 次のステップ

### より高度なアプリケーションデプロイ

1. **Helm Charts**: パッケージ管理
2. **Kustomize**: 設定の管理
3. **ArgoCD**: GitOpsによる自動デプロイ

### 監視とログ

基盤サービスが設定済みの場合：

```bash
# Grafanaでアプリケーションメトリクスを確認
# http://<node-ip>:30300

# Lokiでアプリケーションログを確認
kubectl logs -f deployment/sample-app -n sample-apps
```

### スケーリングとオートスケーリング

```bash
# 手動スケーリング
kubectl scale deployment sample-app --replicas=5 -n sample-apps

# Horizontal Pod Autoscaler（HPA）の設定
kubectl autoscale deployment sample-app --cpu-percent=50 --min=1 --max=10 -n sample-apps
```
