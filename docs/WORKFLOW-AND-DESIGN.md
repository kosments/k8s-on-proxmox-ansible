# ワークフローと設計ルール

## 📋 基本的なワークフロー

### 標準的な構築フロー

```
1. VM作成 (01-vm-creation/create-vms.sh)
   ↓
2. k3sクラスター構築 (scripts/02-setup-k3s.sh または 02-k8s-cluster/setup-k8s-cluster.sh)
   ↓
3. kubeconfig設定 (02-k8s-cluster/setup-kubeconfig.sh または scripts/get-kubeconfig-from-master.sh)
   ↓
4. クラスター確認 (kubectl get nodes)
```

### 再起動後のセットアップ

```
Proxmoxホスト再起動
   ↓
systemdサービス自動実行 (scripts/proxmox-post-boot-setup.sh)
   ↓
VM起動確認 & SSH設定修正
   ↓
kubectl接続確認
```

## 🗂️ ディレクトリ構成と責務

### 01-vm-creation/
**責務**: VMの作成と初期設定
- `create-vms.sh`: メインのVM作成スクリプト（推奨）
- `cloud-init-user-data.yaml`: cloud-init設定ファイル
- `alternative-ansible-setup/`: Ansible方式（代替手段）

**使用しないもの**: 
- `scripts/01-clone-vms.sh` (古い、create-vms.shを使用)

### 02-k8s-cluster/
**責務**: Kubernetesクラスターの構築とkubeconfig管理
- `setup-k8s-cluster.sh`: kubeadm使用（標準Kubernetes）
- `setup-kubeconfig.sh`: kubeconfig設定（kubeadm用）
- `quick-kubeconfig.sh`: 簡易kubeconfig取得（k3s用）

**使用しないもの**:
- 重複するスクリプトは削除予定

### scripts/
**責務**: ユーティリティスクリプトと補助ツール

**主要スクリプト**:
- `02-setup-k3s.sh`: k3sクラスター構築
- `03-verify-cluster.sh`: クラスター確認
- `proxmox-post-boot-setup.sh`: 再起動時自動セットアップ
- `get-kubeconfig-from-master.sh`: kubeconfig取得（k3s用）

**削除対象**:
- `01-clone-vms.sh`: 01-vm-creation/create-vms.shを使用
- `verify-cluster.sh`: 03-verify-cluster.shを使用
- `fix-ssh-and-kubectl.sh`: 機能が他のスクリプトに統合済み
- `setup-ssh-via-proxmox.sh`: proxmox-post-boot-setup.shに統合
- `enable-ssh-and-check-k8s.sh`: 機能が他のスクリプトに統合済み
- `recreate-master.sh`: 必要に応じて01-vm-creation/create-vms.shを使用
- `fix-master-vm.sh`: 必要に応じて01-vm-creation/create-vms.shを使用

## 🎯 スクリプト設計ルール

### 1. スクリプトの命名規則
- 数字プレフィックス: 実行順序を表す（例: `01-`, `02-`）
- 動詞で始まる: 何をするかを明確に（例: `setup-`, `create-`, `verify-`）
- 用途が明確: スクリプト名から機能が推測できる

### 2. 依存関係の管理
- `config.sh`を必ず読み込む
- 他のスクリプトとの依存関係を最小限に
- スクリプトは独立して実行可能であること

### 3. エラーハンドリング
- `set -e`でエラー時に停止
- 適切なログ出力（成功/警告/エラー）
- エラー時は明確なメッセージを表示

### 4. 冪等性
- 同じスクリプトを複数回実行しても同じ結果になること
- 既存のリソースをチェックしてから作成

### 5. ログ出力
- タイムスタンプ付きログ
- カラー出力で可読性向上（INFO=緑、WARN=黄、ERROR=赤）
- 重要な処理には進捗表示

## 📝 ドキュメント管理

### 各ディレクトリのREADME.md
- そのディレクトリの目的と使用方法
- 前提条件とセットアップ手順
- トラブルシューティング

### docs/配下のドキュメント
- 設計思想とルール（このファイル）
- トラブルシューティングガイド
- 特定トピックの詳細説明

## 🔄 メンテナンス方針

### スクリプトの削除基準
1. **重複**: 同じ機能を持つスクリプトが複数ある場合、より新しく標準的なものを残す
2. **未使用**: 長期間使用されていないスクリプト
3. **置き換え済み**: より良い方法に置き換えられた場合

### スクリプトの統合基準
1. **類似機能**: 似た処理を行うスクリプトは統合を検討
2. **依存関係**: 常に一緒に実行される場合は統合を検討
3. **保守性**: 統合により保守が容易になる場合

## 🚀 新規スクリプト追加時のチェックリスト

- [ ] 既存のスクリプトで対応できないか確認
- [ ] 命名規則に従っているか
- [ ] `config.sh`を読み込んでいるか
- [ ] エラーハンドリングが適切か
- [ ] ログ出力が適切か
- [ ] 冪等性が保証されているか
- [ ] ドキュメントが更新されているか
- [ ] 既存スクリプトとの重複がないか

