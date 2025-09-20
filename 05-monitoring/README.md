# 05 - 監視・運用基盤

このディレクトリには、Kubernetesクラスターの監視・運用基盤を構築するためのツールが含まれています。

## 🎯 監視戦略

### 多層監視アプローチ

1. **Infrastructure Monitoring**: New Relic（外部SaaS）
2. **Application Performance**: New Relic APM
3. **Cluster Monitoring**: Prometheus + Grafana（内部）
4. **Log Aggregation**: Grafana Loki
5. **Alerting**: New Relic Alerts + Grafana Alerts

## 🚀 セットアップ手順

### Phase 1: New Relic セットアップ

#### 前提条件

- New Relic アカウント（無料プランで開始可能）
- ライセンスキーの取得

#### 1. 運用ネームスペース作成

```bash
kubectl create namespace ops
kubectl label namespace ops name=ops
```

#### 2. New Relic Kubernetes Integration

```bash
# Helm リポジトリ追加
helm repo add newrelic https://helm-charts.newrelic.com
helm repo update

# ライセンスキー設定（環境変数）
export NEW_RELIC_LICENSE_KEY="your-license-key"

# New Relic インストール
helm install newrelic-bundle newrelic/nri-bundle \
  --namespace ops \
  --set global.licenseKey=$NEW_RELIC_LICENSE_KEY \
  --set global.cluster=k8s-proxmox-cluster \
  --set infrastructure.enabled=true \
  --set prometheus.enabled=true \
  --set webhook.enabled=true \
  --set ksm.enabled=true \
  --set kubeEvents.enabled=true \
  --set logging.enabled=true
```

#### 3. 動作確認

```bash
# Pod 状態確認
kubectl get pods -n ops

# New Relic Agent ログ確認
kubectl logs -n ops -l app.kubernetes.io/name=newrelic-infrastructure

# メトリクス確認
kubectl top nodes
kubectl top pods -A
```

### Phase 2: Prometheus + Grafana（内部監視）

#### Prometheus セットアップ

```bash
# Prometheus Operator インストール
kubectl create -f https://raw.githubusercontent.com/prometheus-operator/prometheus-operator/main/bundle.yaml

# Prometheus インスタンス作成
kubectl apply -f prometheus-config.yaml -n ops
```

#### Grafana セットアップ

```bash
# Grafana インストール
helm repo add grafana https://grafana.github.io/helm-charts
helm install grafana grafana/grafana \
  --namespace ops \
  --set persistence.enabled=true \
  --set adminPassword=admin123 \
  --set service.type=NodePort \
  --set service.nodePort=30300
```

### Phase 3: ログ集約（Loki）

```bash
# Loki インストール
helm repo add grafana https://grafana.github.io/helm-charts
helm install loki grafana/loki-stack \
  --namespace ops \
  --set grafana.enabled=false \
  --set prometheus.enabled=false
```

## 📊 ダッシュボード設定

### New Relic ダッシュボード

- **Kubernetes Cluster Overview**: クラスター全体の状況
- **Node Performance**: ノードレベルのメトリクス
- **Pod Performance**: Pod/Container レベル
- **Application Performance**: APM連携

### Grafana ダッシュボード

推奨ダッシュボードID:

- `315`: Kubernetes cluster monitoring
- `6417`: Kubernetes Pods monitoring  
- `7249`: Kubernetes Deployment monitoring
- `10000`: Cluster monitoring for Kubernetes

### アクセス方法

```bash
# Grafana (内部)
http://192.168.10.101:30300
# Username: admin, Password: admin123

# New Relic (外部)
https://one.newrelic.com/
```

## 🔔 アラート設定

### New Relic Alerts

- **High CPU Usage**: CPU > 80% for 5 minutes
- **High Memory Usage**: Memory > 85% for 5 minutes  
- **Pod Restart**: Pod restart count > 5 in 10 minutes
- **Node Down**: Node unavailable for 2 minutes

### Grafana Alerts

- **Disk Usage**: Disk usage > 90%
- **Network Issues**: High packet loss
- **Application Errors**: Error rate > 5%

## 🛠️ 運用手順

### 日常監視チェックリスト

- [ ] クラスター全体のヘルス状況
- [ ] ノードのリソース使用状況
- [ ] Podの稼働状況
- [ ] ストレージ使用量
- [ ] ネットワーク状況
- [ ] アプリケーションパフォーマンス

### 障害対応手順

1. **アラート受信** → New Relic/Grafana
2. **初期調査** → ダッシュボード確認
3. **詳細調査** → ログ確認、kubectl コマンド
4. **対応実施** → 復旧作業
5. **事後確認** → 正常性確認
6. **報告・改善** → インシデントレポート

### 定期メンテナンス

```bash
# 週次メンテナンス
kubectl get nodes -o wide
kubectl get pods -A | grep -v Running
kubectl top nodes
kubectl top pods -A

# 月次メンテナンス  
kubectl get events --sort-by=.metadata.creationTimestamp
kubectl describe nodes
```

## 📈 パフォーマンス最適化

### リソース最適化

- **CPU制限**: requests/limits設定
- **メモリ制限**: OOMKiller回避
- **ストレージ**: PV/PVC最適化
- **ネットワーク**: Service/Ingress最適化

### 監視データ保持期間

```yaml
# Prometheus
retention: 15d
storage: 50Gi

# Loki  
retention_period: 30d
storage: 100Gi

# New Relic
data_retention: 8d (Free Plan)
```

## 🔍 トラブルシューティング

### New Relic Agent が起動しない

```bash
# ライセンスキー確認
kubectl get secret -n ops newrelic-bundle-nri-metadata -o yaml

# Agent ログ確認
kubectl logs -n ops -l app=newrelic-infrastructure

# 設定確認
kubectl describe configmap -n ops newrelic-bundle-nri-metadata
```

### Grafana にアクセスできない

```bash
# Service 確認
kubectl get svc -n ops grafana

# Pod 状態確認
kubectl get pods -n ops -l app.kubernetes.io/name=grafana

# ログ確認
kubectl logs -n ops -l app.kubernetes.io/name=grafana
```

### メトリクスが表示されない

```bash
# Prometheus Target 確認
kubectl port-forward -n ops svc/prometheus 9090:9090
# http://localhost:9090/targets

# メトリクス エンドポイント確認
kubectl get servicemonitor -A
kubectl get podmonitor -A
```

## 📚 参考情報

- [New Relic Kubernetes Documentation](https://docs.newrelic.com/docs/kubernetes-pixie/)
- [Prometheus Operator Documentation](https://prometheus-operator.dev/)
- [Grafana Documentation](https://grafana.com/docs/grafana/latest/)
- [Loki Documentation](https://grafana.com/docs/loki/latest/)

## 🔄 次のステップ

監視基盤の構築完了後:

1. **GitOps VM構築** → `../06-gitops/`
2. **LB/Gateway VM構築** → `../07-infrastructure/`
3. **本格的なアプリケーションデプロイ** → `../04-applications/`
