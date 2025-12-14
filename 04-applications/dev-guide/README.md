# 開発ガイド アプリケーション

Astro Starlightを使用した統合開発ガイドです。

## 特徴

- **Astro Starlight**: 最新のドキュメントフレームワーク
- **軽量**: 静的サイトとして高速に動作
- **モダンUI**: ダークモード、検索、サイドバー対応

## デプロイ方法

```bash
kubectl apply -f namespace.yaml
kubectl apply -f deployment.yaml
kubectl apply -f service.yaml
```

## アクセス

NodePortでアクセス:
```
http://<node-ip>:30080
```

## カスタマイズ

独自のドキュメントを追加する場合は、Dockerイメージを更新してください。

