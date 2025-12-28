# スクリプト整理記録

## 削除したスクリプトと理由

### 1. `scripts/get-kubeconfig-from-master.sh`

**削除理由**:

- `02-k8s-cluster/setup-kubeconfig.sh` と機能が重複
- `02-k8s-cluster/quick-kubeconfig.sh` も同様の機能を提供
- より標準的な `setup-kubeconfig.sh` を優先

**代替手段**:

- `02-k8s-cluster/setup-kubeconfig.sh` を使用
- `02-k8s-cluster/quick-kubeconfig.sh` も選択肢

### 2. `01-vm-creation/setup-vm-ssh-after-boot.sh`

**削除理由**:

- `cloud-init-user-data.yaml` で同じ処理を実装済み
- cloud-initの方が標準的で確実

**代替手段**:

- `cloud-init-user-data.yaml` が自動的にSSH設定を適用

## 保持するスクリプト

### 標準的な作業フローで使用

- `01-vm-creation/create-vms.sh` - VM作成
- `scripts/02-setup-k3s.sh` - k3sクラスター構築
- `scripts/03-verify-cluster.sh` - クラスター検証
- `02-k8s-cluster/setup-kubeconfig.sh` - kubeconfig設定

### メンテナンス・トラブルシューティング用

- `scripts/check-vm-status.sh` - VM状態確認
- `scripts/proxmox-post-boot-setup.sh` - 再起動時セットアップ
- `scripts/vm-post-boot-setup.sh` - VM起動後セットアップ
- `scripts/fix-ingress.sh` - Ingress修正
- `scripts/troubleshoot-ingress.sh` - Ingressトラブルシューティング

### 便利ツール

- `02-k8s-cluster/quick-kubeconfig.sh` - 簡易kubeconfig取得

## 検討が必要なスクリプト

### `02-k8s-cluster/setup-k8s-cluster.sh`

**状況**: kubeadmベースのKubernetesクラスター構築スクリプト
**判断**:

- 現在はk3sを使用しているため、このスクリプトは使用されていない
- 将来的にkubeadmを使う可能性がある場合は保持
- 現時点では削除を検討

**推奨**:

- 削除するか、`02-k8s-cluster/alternative-kubeadm-setup/` に移動
