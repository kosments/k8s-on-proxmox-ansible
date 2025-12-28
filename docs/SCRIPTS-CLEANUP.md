# スクリプト整理計画

## 削除対象スクリプト

### scripts/配下

1. **01-clone-vms.sh** → 削除
   - 理由: `01-vm-creation/create-vms.sh`に置き換え済み
   - 代替: `01-vm-creation/create-vms.sh`

2. **verify-cluster.sh** → 削除
   - 理由: `03-verify-cluster.sh`に機能が統合済み
   - 代替: `03-verify-cluster.sh`

3. **fix-ssh-and-kubectl.sh** → 削除
   - 理由: 機能が`proxmox-post-boot-setup.sh`と`vm-post-boot-setup.sh`に統合済み

4. **setup-ssh-via-proxmox.sh** → 削除
   - 理由: 機能が`proxmox-post-boot-setup.sh`に統合済み

5. **enable-ssh-and-check-k8s.sh** → 削除
   - 理由: 機能が他のスクリプトに統合済み

6. **recreate-master.sh** → 削除
   - 理由: `01-vm-creation/create-vms.sh`で対応可能

7. **fix-master-vm.sh** → 削除
   - 理由: `01-vm-creation/create-vms.sh`で対応可能

### 保持するスクリプト

- **02-setup-k3s.sh**: k3sクラスター構築（主要）
- **03-verify-cluster.sh**: クラスター確認（主要）
- **check-vm-status.sh**: VM状態確認（ユーティリティ）
- **proxmox-post-boot-setup.sh**: 再起動時セットアップ（主要）
- **vm-post-boot-setup.sh**: VM起動後セットアップ（補助）
- **get-kubeconfig-from-master.sh**: kubeconfig取得（k3s用）
- **troubleshoot-ingress.sh**: Ingressトラブルシューティング（ユーティリティ）
- **fix-ingress.sh**: Ingress修正（ユーティリティ）
- **transfer-to-proxmox.sh**: ファイル転送（ユーティリティ）

## 統合・改善が必要なスクリプト

1. **02-setup-k3s.sh**
   - `config.sh`を読み込むように修正が必要
   - `selected-ips.txt`への依存を削除

2. **get-kubeconfig-from-master.sh**
   - `config.sh`を読み込むように修正が必要

