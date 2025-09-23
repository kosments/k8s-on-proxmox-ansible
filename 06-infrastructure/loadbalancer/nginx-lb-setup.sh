#!/bin/bash

# =============================================================================
# Nginx Load Balancer Setup Script
# =============================================================================
# 
# このスクリプトは、K8sクラスター前段にNginx Load Balancerをセットアップします
#
# 前提条件:
# - Proxmox VM作成済み（VM 104）
# - SSH接続可能
# - ドメイン設定済み（オプション）
#
# 使用方法:
#   ./nginx-lb-setup.sh [vm-ip]
#
# 例:
#   ./nginx-lb-setup.sh 192.168.10.104
#
# =============================================================================

set -euo pipefail

# 設定
VM_IP="${1:-192.168.10.104}"
VM_USER="ubuntu"
SSH_KEY="/root/.ssh/id_rsa"
NGINX_VERSION="1.25"
DOMAIN="sampleapp.com"

# カラー出力
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# ログ関数
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

warn() {
    echo -e "${YELLOW}[WARN] $1${NC}"
}

error() {
    echo -e "${RED}[ERROR] $1${NC}"
    exit 1
}

# SSH接続テスト
test_ssh_connection() {
    log "Testing SSH connection to $VM_IP..."
    if ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no -i "$SSH_KEY" "$VM_USER@$VM_IP" "echo 'SSH OK'" >/dev/null 2>&1; then
        log "✓ SSH connection successful"
    else
        error "✗ SSH connection failed. Please check SSH configuration."
    fi
}

# Nginx インストール
install_nginx() {
    log "Installing Nginx on $VM_IP..."
    
    ssh -i "$SSH_KEY" "$VM_USER@$VM_IP" "
        # パッケージ更新
        sudo apt update
        
        # Nginx インストール
        sudo apt install -y nginx
        
        # サービス有効化
        sudo systemctl enable nginx
        sudo systemctl start nginx
        
        # ファイアウォール設定
        sudo ufw allow 'Nginx Full'
        sudo ufw allow ssh
        sudo ufw --force enable
        
        # ステータス確認
        sudo systemctl status nginx --no-pager
    "
    
    log "✓ Nginx installed successfully"
}

# Nginx設定
configure_nginx() {
    log "Configuring Nginx load balancer..."
    
    # ロードバランサー設定作成
    cat > /tmp/nginx-lb.conf << EOF
upstream k8s_backend {
    # K8s クラスターのノード（NodePort経由）
    server 192.168.10.101:30080 weight=1 max_fails=3 fail_timeout=30s;
    server 192.168.10.102:30080 weight=1 max_fails=3 fail_timeout=30s;
    server 192.168.10.103:30080 weight=1 max_fails=3 fail_timeout=30s;
    
    # ヘルスチェック
    keepalive 32;
}

# ログ設定
log_format main '\$remote_addr - \$remote_user [\$time_local] "\$request" '
                '\$status \$body_bytes_sent "\$http_referer" '
                '"\$http_user_agent" "\$http_x_forwarded_for" '
                'rt=\$request_time uct="\$upstream_connect_time" '
                'uht="\$upstream_header_time" urt="\$upstream_response_time"';

access_log /var/log/nginx/access.log main;
error_log /var/log/nginx/error.log warn;

server {
    listen 80;
    server_name $DOMAIN sampleapp.local;
    
    # セキュリティヘッダー
    add_header X-Frame-Options DENY;
    add_header X-Content-Type-Options nosniff;
    add_header X-XSS-Protection "1; mode=block";
    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
    
    # レート制限
    limit_req_zone \$binary_remote_addr zone=api:10m rate=10r/s;
    limit_req zone=api burst=20 nodelay;
    
    # ヘルスチェック
    location /health {
        access_log off;
        return 200 "nginx-lb healthy\n";
        add_header Content-Type text/plain;
    }
    
    # メトリクス（Nginx Plus または stub_status）
    location /nginx_status {
        stub_status on;
        access_log off;
        allow 127.0.0.1;
        allow 192.168.10.0/24;
        deny all;
    }
    
    # メインアプリケーション
    location / {
        proxy_pass http://k8s_backend;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        
        # タイムアウト設定
        proxy_connect_timeout 5s;
        proxy_send_timeout 10s;
        proxy_read_timeout 10s;
        
        # バッファ設定
        proxy_buffering on;
        proxy_buffer_size 4k;
        proxy_buffers 8 4k;
        
        # エラーページ
        proxy_next_upstream error timeout invalid_header http_500 http_502 http_503 http_504;
        proxy_next_upstream_tries 3;
        proxy_next_upstream_timeout 10s;
    }
    
    # 静的ファイル（オプション）
    location /static/ {
        alias /var/www/static/;
        expires 1y;
        add_header Cache-Control "public, immutable";
    }
}
EOF

    # 設定ファイルをアップロード
    scp -i "$SSH_KEY" /tmp/nginx-lb.conf "$VM_USER@$VM_IP:/tmp/"
    
    # 設定適用
    ssh -i "$SSH_KEY" "$VM_USER@$VM_IP" "
        # バックアップ作成
        sudo cp /etc/nginx/sites-available/default /etc/nginx/sites-available/default.backup
        
        # 新設定適用
        sudo cp /tmp/nginx-lb.conf /etc/nginx/sites-available/default
        
        # 設定テスト
        sudo nginx -t
        
        # サービス再起動
        sudo systemctl reload nginx
        
        # 設定確認
        sudo systemctl status nginx --no-pager
    "
    
    # 一時ファイル削除
    rm -f /tmp/nginx-lb.conf
    
    log "✓ Nginx configuration applied successfully"
}

# SSL証明書設定（Let's Encrypt）
setup_ssl() {
    log "Setting up SSL certificate with Let's Encrypt..."
    
    ssh -i "$SSH_KEY" "$VM_USER@$VM_IP" "
        # Certbot インストール
        sudo apt install -y certbot python3-certbot-nginx
        
        # 証明書取得（ドメインが設定されている場合のみ）
        if [ '$DOMAIN' != 'sampleapp.com' ] && [ -n '$DOMAIN' ]; then
            sudo certbot --nginx -d '$DOMAIN' --non-interactive --agree-tos --email admin@$DOMAIN
        else
            echo 'Skipping SSL setup - using default domain'
        fi
    "
    
    log "✓ SSL setup completed"
}

# 監視設定
setup_monitoring() {
    log "Setting up monitoring for Nginx..."
    
    ssh -i "$SSH_KEY" "$VM_USER@$VM_IP" "
        # ログローテーション設定
        sudo tee /etc/logrotate.d/nginx > /dev/null << 'EOF'
/var/log/nginx/*.log {
    daily
    missingok
    rotate 52
    compress
    delaycompress
    notifempty
    create 640 nginx adm
    sharedscripts
    postrotate
        if [ -f /var/run/nginx.pid ]; then
            kill -USR1 \$(cat /var/run/nginx.pid)
        fi
    endscript
}
EOF
        
        # システム監視スクリプト作成
        sudo tee /usr/local/bin/nginx-monitor.sh > /dev/null << 'EOF'
#!/bin/bash
# Nginx 監視スクリプト

# ヘルスチェック
check_nginx() {
    if systemctl is-active --quiet nginx; then
        echo \"✓ Nginx is running\"
        return 0
    else
        echo \"✗ Nginx is not running\"
        return 1
    fi
}

# バックエンド接続チェック
check_backend() {
    local backend_servers=(\"192.168.10.101:30080\" \"192.168.10.102:30080\" \"192.168.10.103:30080\")
    
    for server in \"\${backend_servers[@]}\"; do
        if curl -s --connect-timeout 5 \"http://\$server/health\" > /dev/null; then
            echo \"✓ Backend \$server is healthy\"
        else
            echo \"✗ Backend \$server is unhealthy\"
        fi
    done
}

# メイン処理
echo \"=== Nginx Load Balancer Status ===\"
echo \"Date: \$(date)\"
echo

check_nginx
echo
check_backend
echo

# 接続統計
echo \"=== Connection Statistics ===\"
curl -s http://localhost/nginx_status
EOF
        
        sudo chmod +x /usr/local/bin/nginx-monitor.sh
        
        # Cron設定（5分ごと）
        echo \"*/5 * * * * /usr/local/bin/nginx-monitor.sh >> /var/log/nginx-monitor.log 2>&1\" | sudo crontab -
    "
    
    log "✓ Monitoring setup completed"
}

# 動作確認
verify_setup() {
    log "Verifying Nginx Load Balancer setup..."
    
    # ヘルスチェック
    if curl -s --connect-timeout 5 "http://$VM_IP/health" | grep -q "nginx-lb healthy"; then
        log "✓ Health check passed"
    else
        warn "✗ Health check failed"
    fi
    
    # バックエンド接続テスト
    if curl -s --connect-timeout 5 "http://$VM_IP/" | grep -q "Sample Web Application"; then
        log "✓ Backend connection successful"
    else
        warn "✗ Backend connection failed - K8s cluster may not be ready"
    fi
    
    # ステータス確認
    ssh -i "$SSH_KEY" "$VM_USER@$VM_IP" "
        echo '=== Nginx Status ==='
        sudo systemctl status nginx --no-pager
        echo
        echo '=== Nginx Configuration Test ==='
        sudo nginx -t
        echo
        echo '=== Active Connections ==='
        curl -s http://localhost/nginx_status
    "
    
    log "✓ Verification completed"
}

# メイン処理
main() {
    echo -e "${BLUE}"
    echo "================================================"
    echo "  Nginx Load Balancer Setup"
    echo "  Target: $VM_USER@$VM_IP"
    echo "  Domain: $DOMAIN"
    echo "================================================"
    echo -e "${NC}"
    
    test_ssh_connection
    install_nginx
    configure_nginx
    setup_ssl
    setup_monitoring
    verify_setup
    
    log "Nginx Load Balancer setup completed successfully!"
    log "Access your application at: http://$VM_IP"
    if [ "$DOMAIN" != "sampleapp.com" ]; then
        log "Or via domain: http://$DOMAIN"
    fi
}

# スクリプト実行
main "$@"
