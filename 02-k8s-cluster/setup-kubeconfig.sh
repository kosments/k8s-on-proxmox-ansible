#!/bin/bash

# =============================================================================
# Kubernetes kubeconfig Setup Script
# =============================================================================
# このスクリプトは、K8sクラスター構築後にkubeconfigファイルを
# 適切な場所にコピーし、環境変数を設定します。
# =============================================================================

set -euo pipefail

# 設定ファイル読み込み
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/../config.sh"

if [[ -f "$CONFIG_FILE" ]]; then
    source "$CONFIG_FILE"
else
    echo "❌ 設定ファイルが見つかりません: $CONFIG_FILE"
    exit 1
fi

# ログ関数
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

# ヘルプ表示
show_help() {
    cat << EOF
Kubernetes kubeconfig Setup Script

使用方法:
  $0 [command]

コマンド:
  setup     - kubeconfigをセットアップ（デフォルト）
  status    - クラスター状態を確認
  test      - kubectl接続テスト
  help      - このヘルプを表示

例:
  $0                    # kubeconfigをセットアップ
  $0 status            # クラスター状態確認
  $0 test              # 接続テスト

EOF
}

# kubeconfigセットアップ
setup_kubeconfig() {
    log "🔧 kubeconfigをセットアップ中..."
    
    # マスターノードのIPを取得
    local master_vm_id=$(get_master_vm)
    if [[ -z "$master_vm_id" ]]; then
        log "❌ マスターノードが見つかりません"
        return 1
    fi
    
    local master_ip=$(get_vm_ip $master_vm_id)
    if [[ -z "$master_ip" ]]; then
        log "❌ マスターノードのIPアドレスが取得できません"
        return 1
    fi
    
    log "マスターノード ($master_ip) からkubeconfigを取得中..."
    if ssh -o StrictHostKeyChecking=no ubuntu@${master_ip} "sudo cat /etc/kubernetes/admin.conf" > kubeconfig; then
        log "✅ kubeconfigファイルを取得しました"
    else
        log "❌ kubeconfigファイルの取得に失敗しました"
        return 1
    fi
    
    # ファイル権限設定
    chmod 600 kubeconfig
    log "✅ ファイル権限を設定しました (600)"
    
    # 環境変数設定
    export KUBECONFIG="${SCRIPT_DIR}/kubeconfig"
    log "✅ KUBECONFIG環境変数を設定しました: $KUBECONFIG"
    
    # 接続テスト
    if kubectl cluster-info &>/dev/null; then
        log "✅ クラスター接続テスト成功"
    else
        log "❌ クラスター接続テスト失敗"
        return 1
    fi
    
    log "🎉 kubeconfigセットアップ完了！"
    log "使用方法: export KUBECONFIG=${SCRIPT_DIR}/kubeconfig"
}

# クラスター状態確認
check_status() {
    log "📊 クラスター状態を確認中..."
    
    if [[ ! -f "kubeconfig" ]]; then
        log "❌ kubeconfigファイルが見つかりません"
        log "先に '$0 setup' を実行してください"
        return 1
    fi
    
    export KUBECONFIG="${SCRIPT_DIR}/kubeconfig"
    
    echo "=== クラスター情報 ==="
    kubectl cluster-info
    echo ""
    
    echo "=== ノード状態 ==="
    kubectl get nodes -o wide
    echo ""
    
    echo "=== Pod状態 ==="
    kubectl get pods -A
    echo ""
    
    echo "=== サービス状態 ==="
    kubectl get svc -A
}

# 接続テスト
test_connection() {
    log "🧪 kubectl接続テスト中..."
    
    if [[ ! -f "kubeconfig" ]]; then
        log "❌ kubeconfigファイルが見つかりません"
        log "先に '$0 setup' を実行してください"
        return 1
    fi
    
    export KUBECONFIG="${SCRIPT_DIR}/kubeconfig"
    
    if kubectl get nodes &>/dev/null; then
        log "✅ kubectl接続テスト成功"
        kubectl get nodes
    else
        log "❌ kubectl接続テスト失敗"
        return 1
    fi
}

# メイン処理
main() {
    local command="${1:-setup}"
    
    case "$command" in
        "setup")
            setup_kubeconfig
            ;;
        "status")
            check_status
            ;;
        "test")
            test_connection
            ;;
        "help"|"-h"|"--help")
            show_help
            ;;
        *)
            echo "❌ 不明なコマンド: $command"
            echo ""
            show_help
            exit 1
            ;;
    esac
}

# スクリプト実行
main "$@"
