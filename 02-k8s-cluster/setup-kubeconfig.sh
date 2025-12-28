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
    
    # マスターノードのIPを取得（k3sまたはkubeadmの両方に対応）
    local master_ip="${VM_IPS[0]}"
    if [[ -z "$master_ip" ]]; then
        log "❌ マスターノードのIPアドレスが設定されていません"
        log "config.shのVM_IPSを確認してください"
        return 1
    fi
    
    log "マスターノード ($master_ip) からkubeconfigを取得中..."
    
    # SSH接続オプション
    local ssh_opts="-o StrictHostKeyChecking=no -o ConnectTimeout=10 -o UserKnownHostsFile=/dev/null"
    local ssh_key=""
    if [[ -n "$SSH_KEY_PATH" ]] && [[ -f "$SSH_KEY_PATH" ]]; then
        ssh_key="-i $SSH_KEY_PATH"
    fi
    
    # k3sの場合のkubeconfig取得を試行
    log "k3sのkubeconfigを取得中（/etc/rancher/k3s/k3s.yaml）..."
    if ssh $ssh_opts $ssh_key ${SSH_USER}@${master_ip} "sudo cat /etc/rancher/k3s/k3s.yaml" > kubeconfig.tmp 2>/dev/null; then
        # k3sのkubeconfigを取得できた場合、127.0.0.1をmaster_ipに置換
        sed "s/127.0.0.1/${master_ip}/g" kubeconfig.tmp > kubeconfig
        rm -f kubeconfig.tmp
        log "✅ k3sのkubeconfigファイルを取得しました"
    # kubeadmの場合のkubeconfig取得を試行
    elif ssh $ssh_opts $ssh_key ${SSH_USER}@${master_ip} "sudo cat /etc/kubernetes/admin.conf" > kubeconfig 2>/dev/null; then
        log "✅ kubeadmのkubeconfigファイルを取得しました"
    else
        log "❌ kubeconfigファイルの取得に失敗しました"
        log "以下を確認してください:"
        log "  1. VM ($master_ip) が起動しているか"
        log "  2. SSH接続が可能か（ssh ${SSH_USER}@${master_ip}）"
        log "  3. k3sまたはkubeadmがインストールされているか"
        rm -f kubeconfig.tmp
        return 1
    fi
    
    # ファイル権限設定
    chmod 600 kubeconfig
    log "✅ ファイル権限を設定しました (600)"
    
    # 環境変数設定
    export KUBECONFIG="${SCRIPT_DIR}/kubeconfig"
    log "✅ KUBECONFIG環境変数を設定しました: $KUBECONFIG"
    
    # 接続テスト
    if kubectl cluster-info &>/dev/null 2>&1; then
        log "✅ クラスター接続テスト成功"
        log ""
        log "🎉 kubeconfigセットアップ完了！"
        log "使用方法:"
        log "  export KUBECONFIG=${SCRIPT_DIR}/kubeconfig"
        log "  kubectl get nodes"
    else
        log "❌ クラスター接続テスト失敗"
        log "以下を確認してください:"
        log "  1. kubectlがインストールされているか（which kubectl）"
        log "  2. マスターノードのポート6443が開いているか"
        log "  3. ネットワーク接続が正常か（ping $master_ip）"
        return 1
    fi
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
