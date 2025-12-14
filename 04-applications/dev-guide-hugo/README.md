# Dev Guide - Hugo ドキュメントサイト

Go製の静的サイトジェネレーター「Hugo」を使用した開発ガイドです。

## 特徴

- **Hugo**: Go製で高速なビルド
- **Markdown**: ドキュメントはMarkdownで記述
- **ディレクトリベース**: ファイルを配置するだけで自動的にナビゲーション生成
- **テーマ**: Book テーマ（ドキュメント向け）

## ローカル開発

```bash
# Hugoインストール（Mac）
brew install hugo

# 開発サーバー起動
cd dev-guide-hugo
hugo server -D

# ブラウザでアクセス
open http://localhost:1313
```

## ドキュメント追加方法

```bash
# 新しいページを追加
hugo new content/operations/new-page.md

# または直接ファイル作成
echo "# 新しいページ" > content/operations/new-page.md
```

## ビルド

```bash
# 静的ファイル生成
hugo --minify

# 出力先: public/
```

## Kubernetes デプロイ

```bash
# Dockerイメージビルド
docker build -t dev-guide:latest .

# デプロイ
kubectl apply -f k8s/
```

## ディレクトリ構成

```
dev-guide-hugo/
├── config.toml         # Hugo設定
├── content/            # ドキュメント（Markdown）
│   ├── _index.md       # トップページ
│   ├── getting-started/
│   ├── architecture/
│   ├── operations/
│   └── troubleshooting/
├── Dockerfile          # コンテナビルド
└── k8s/                # Kubernetesマニフェスト
```

