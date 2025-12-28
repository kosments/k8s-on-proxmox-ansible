# 作業フローと設計方針

## 📋 基本方針

### 1. スクリプト管理

- **単一責任の原則**: 1つのスクリプトは1つの明確な目的を持つ
- **冪等性**: 何度実行しても同じ結果になるように設計
- **再利用性**: 共通処理は関数化して再利用
- **ドキュメント**: 各スクリプトには用途と使用方法を明記

### 2. ディレクトリ構造

```
k8s-on-proxmox-ansible/
├── 01-vm-creation/          # VM作成関連
│   ├── create-vms.sh        # VM作成メインスクリプト
│   └── cloud-init-user-data.yaml  # cloud-init設定
├── 02-k8s-cluster/          # Kubernetesクラスター構築
│   ├── setup-kubeconfig.sh  # kubeconfig設定
│   └── quick-kubeconfig.sh  # 簡易kubeconfig取得
├── scripts/                 # 共通スクリプト
│   ├── 02-setup-k3s.sh      # k3sインストール
│   ├── 03-verify-cluster.sh # クラスター検証
│   ├── check-vm-status.sh   # VM状態確認
│   ├── proxmox-post-boot-setup.sh  # 再起動時セットアップ
│   └── vm-post-boot-setup.sh       # VM起動後セットアップ
└── docs/                    # ドキュメント
```

### 3. 命名規則

- **番号付きスクリプト**: 実行順序が明確な場合（例: `01-xxx.sh`, `02-xxx.sh`）
- **機能名スクリプト**: 特定の機能を表す（例: `check-vm-status.sh`）
- **用途別ディレクトリ**: 大きな機能ごとにディレクトリを分割

### 4. 不要ファイルの削除基準

- **重複機能**: 同じ目的のスクリプトが複数ある場合は最新・最適なものを残す
- **未使用**: 明らかに使用されていないファイル
- **古いバージョン**: より良い代替手段がある場合
- **一時ファイル**: テスト用や一時的なもの

## 🔄 標準的な作業フロー

### VM作成からクラスター構築まで

1. **VM作成**

   ```bash
   cd 01-vm-creation
   ./create-vms.sh
   ```

2. **k3sクラスター構築**

   ```bash
   cd ../scripts
   ./02-setup-k3s.sh
   ```

3. **クラスター検証**

   ```bash
   ./03-verify-cluster.sh
   ```

4. **kubeconfig設定**

   ```bash
   cd ../02-k8s-cluster
   ./setup-kubeconfig.sh
   export KUBECONFIG=$(pwd)/kubeconfig
   kubectl get nodes
   ```

### 再起動時の対応

1. **自動セットアップ（推奨）**
   - `proxmox-post-boot-setup.sh` をsystemdサービスとして登録
   - Proxmoxホスト起動時に自動実行

2. **手動実行**

   ```bash
   cd scripts
   ./proxmox-post-boot-setup.sh
   ```

## 🧹 スクリプト整理の原則

### 削除対象

- ✅ 機能が重複しているスクリプト
- ✅ 明らかに未使用のスクリプト
- ✅ テスト用や一時的なスクリプト
- ✅ より良い代替手段があるスクリプト

### 保持対象

- ✅ 標準的な作業フローで使用されるスクリプト
- ✅ トラブルシューティング用のスクリプト
- ✅ 特定の用途で必要なスクリプト

### 整理手順

1. 各スクリプトの目的と使用頻度を確認
2. 重複機能を特定
3. 最新・最適なものを残す
4. 削除前にバックアップまたは履歴を残す
5. ドキュメントを更新

## 📝 ドキュメント作成の原則

- **README.md**: 各ディレクトリに基本情報とクイックスタート
- **WORKFLOW.md**: このファイル - 作業フローと設計方針
- **TROUBLESHOOTING.md**: トラブルシューティングガイド
- **INSTALL-*.md**: 特定のインストール手順

## 🎯 タスク管理

- 重要な作業はタスクリストを作成して順次実行
- 各タスクは完了後に確認・テスト
- 問題があればタスクリストを更新して対応
