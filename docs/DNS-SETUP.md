# DNS設定ガイド

管理PCから `chat.k8s.local` や `guide.k8s.local` にアクセスできるようにするためのDNS設定方法です。

## 方法1: /etc/hosts に追加（推奨・簡単）

### macOS / Linux

```bash
# 管理者権限で編集
sudo nano /etc/hosts

# 以下を追加（Master NodeのIPを指定）
192.168.10.111  chat.k8s.local
192.168.10.111  guide.k8s.local
```

### Windows

1. `C:\Windows\System32\drivers\etc\hosts` を管理者権限で開く
2. 以下を追加:
```
192.168.10.111  chat.k8s.local
192.168.10.111  guide.k8s.local
```

## 方法2: ローカルDNSサーバー（dnsmasq）

複数のPCからアクセスする場合や、動的にIPが変わる場合に便利です。

### macOS (Homebrew)

```bash
# dnsmasqをインストール
brew install dnsmasq

# 設定ファイルを編集
nano /opt/homebrew/etc/dnsmasq.conf

# 以下を追加
address=/k8s.local/192.168.10.111
```

### Linux

```bash
# dnsmasqをインストール
sudo apt-get install dnsmasq  # Ubuntu/Debian
# または
sudo yum install dnsmasq      # CentOS/RHEL

# 設定ファイルを編集
sudo nano /etc/dnsmasq.conf

# 以下を追加
address=/k8s.local/192.168.10.111
```

### 起動

```bash
# macOS
brew services start dnsmasq

# Linux
sudo systemctl enable dnsmasq
sudo systemctl start dnsmasq
```

### DNS設定

**macOS**:
1. システム設定 → ネットワーク → 詳細 → DNS
2. `127.0.0.1` をDNSサーバーリストの先頭に追加

**Linux**:
```bash
# /etc/resolv.conf を編集（NetworkManager使用時は設定UIから）
nameserver 127.0.0.1
nameserver 8.8.8.8
```

## 方法3: ルーターのDNS設定

ルーターがカスタムDNSエントリをサポートしている場合、ルーター側で設定すると全デバイスからアクセス可能です。

## 確認方法

```bash
# 名前解決の確認
ping chat.k8s.local
ping guide.k8s.local

# または
nslookup chat.k8s.local
nslookup guide.k8s.local

# ブラウザでアクセス
# http://chat.k8s.local
# http://guide.k8s.local
```

## Traefikのポート確認

k3sのTraefikは通常、NodePortで公開されています。ポートを確認するには:

```bash
kubectl get svc -n kube-system traefik
```

デフォルトでは `80` ポートがNodePortで公開されているはずです。もし異なる場合は、Ingressの設定を確認してください。

## トラブルシューティング

### 名前解決できない

1. `/etc/hosts` の設定を確認
2. DNSキャッシュをクリア:
   ```bash
   # macOS
   sudo dscacheutil -flushcache; sudo killall -HUP mDNSResponder
   
   # Linux
   sudo systemd-resolve --flush-caches
   ```

### 接続できない（名前解決は成功）

1. Traefikが動作しているか確認:
   ```bash
   kubectl get pods -n kube-system | grep traefik
   ```

2. Ingressリソースが正しく作成されているか確認:
   ```bash
   kubectl get ingress -A
   ```

3. Serviceが正しく作成されているか確認:
   ```bash
   kubectl get svc -n dev-guide
   kubectl get svc -n local-llm
   ```

4. Podが起動しているか確認:
   ```bash
   kubectl get pods -n dev-guide
   kubectl get pods -n local-llm
   ```

