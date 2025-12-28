# Local LLM (Ollama + Open WebUI)

ローカルLLMを使った対話型チャットシステムです。

## 構成

```
┌─────────────────────────────────────────────────────────┐
│                    Kubernetes Cluster                    │
│                                                          │
│  ┌──────────────┐      ┌──────────────┐                │
│  │  Open WebUI  │──────│    Ollama    │                │
│  │  (Chat UI)   │      │  (LLM Engine)│                │
│  │  Port: 8080  │      │  Port: 11434 │                │
│  └──────┬───────┘      └──────────────┘                │
│         │                                                │
│  ┌──────┴───────┐                                       │
│  │   Ingress    │ ←── chat.k8s.local                   │
│  └──────────────┘                                       │
└─────────────────────────────────────────────────────────┘
```

## コンポーネント

| コンポーネント | 説明 |
|---------------|------|
| **Ollama** | ローカルLLMエンジン。様々なモデル（Llama3, Mistral等）を実行 |
| **Open WebUI** | ChatGPT風のWebインターフェース |

## デプロイ

```bash
# 1. Namespaceとリソースをデプロイ
kubectl apply -f k8s/namespace.yaml
kubectl apply -f k8s/ollama.yaml
kubectl apply -f k8s/open-webui.yaml
kubectl apply -f k8s/ingress.yaml

# 2. Podの起動を確認
kubectl get pods -n local-llm -w

# 3. モデルをダウンロード（初回のみ）
kubectl exec -n local-llm deploy/ollama -- ollama pull llama3.2:1b  # 軽量版
# または
kubectl exec -n local-llm deploy/ollama -- ollama pull mistral      # 高性能版
```

## アクセス方法

### DNS設定後（推奨）
```
http://chat.k8s.local
```

### NodePort経由（DNS設定前）
```bash
# NodePort Serviceを一時的に作成
kubectl expose deployment open-webui -n local-llm \
  --type=NodePort --port=80 --target-port=8080 --name=open-webui-nodeport

# ポート確認
kubectl get svc -n local-llm open-webui-nodeport
# → http://<ノードIP>:<NodePort>
```

## 推奨モデル

| モデル | サイズ | メモリ | 特徴 |
|--------|-------|--------|------|
| `llama3.2:1b` | ~1GB | 2GB | 軽量、日本語△ |
| `llama3.2:3b` | ~2GB | 4GB | バランス良好 |
| `mistral` | ~4GB | 8GB | 高性能、英語 |
| `gemma2:2b` | ~1.6GB | 3GB | Google製、軽量 |

## トラブルシューティング

### モデルのダウンロードが遅い
```bash
# Pod内で直接実行（ログが見える）
kubectl exec -it -n local-llm deploy/ollama -- ollama pull llama3.2:1b
```

### メモリ不足
小さいモデルに変更するか、Nodeのメモリを増やしてください。

### Open WebUIがOllamaに接続できない
```bash
# Ollama Serviceの疎通確認
kubectl exec -n local-llm deploy/open-webui -- \
  curl -s http://ollama.local-llm.svc.cluster.local:11434/api/tags
```

