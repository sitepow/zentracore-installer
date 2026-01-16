#!/bin/bash
set -e

BASE_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
source "$BASE_DIR/config/env.sh"

DOMAIN=$1
EMAIL="admin@$DOMAIN"

CHECK_INTERVAL=60
MAX_RETRY=10

if [ -z "$DOMAIN" ]; then
  echo "Usage: ./ssl.sh your-domain.com"
  exit 1
fi

if ! command -v nginx >/dev/null; then
  echo "nginx not found"
  exit 1
fi

if ! command -v certbot >/dev/null; then
  echo "Installing certbot"
  sudo apt install -y certbot python3-certbot-nginx
fi

SERVER_IP=$(curl -s ifconfig.me)
NGINX_CONF="/etc/nginx/sites-available/$DOMAIN"

echo "--------------------------------------"
echo "SSL setup for domain: $DOMAIN"
echo "Server IP: $SERVER_IP"
echo "--------------------------------------"

echo "[1/6] Check DNS propagation"

COUNT=1
while true; do
  DOMAIN_IP=$(getent hosts "$DOMAIN" | awk '{ print $1 }')

  if [ "$DOMAIN_IP" = "$SERVER_IP" ]; then
    echo "DNS is pointing to this server"
    break
  fi

  if [ $COUNT -ge $MAX_RETRY ]; then
    echo "DNS not ready after $MAX_RETRY attempts"
    echo "Current DNS IP: ${DOMAIN_IP:-not found}"
    exit 1
  fi

  echo "Waiting for DNS propagation ($COUNT/$MAX_RETRY)"
  sleep $CHECK_INTERVAL
  COUNT=$((COUNT + 1))
done

echo "[2/6] Create nginx config"

sudo tee "$NGINX_CONF" > /dev/null <<EOF
server {
    listen 80;
    server_name $DOMAIN www.$DOMAIN;

    location / {
        proxy_pass http://127.0.0.1:$APP_PORT;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host \$host;
        proxy_cache_bypass \$http_upgrade;
    }
}
EOF

sudo ln -sf "$NGINX_CONF" /etc/nginx/sites-enabled/

echo "[3/6] Test nginx config"
sudo nginx -t

echo "[4/6] Reload nginx"
sudo systemctl reload nginx

echo "[5/6] Request SSL certificate"
sudo certbot --nginx \
  -d $DOMAIN -d www.$DOMAIN \
  --non-interactive \
  --agree-tos \
  -m $EMAIL \
  --redirect

echo "[6/6] Verify auto renew"
sudo certbot renew --dry-run

echo "SSL setup completed"