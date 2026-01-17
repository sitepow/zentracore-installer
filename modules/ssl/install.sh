#!/bin/bash
set -e

BASE_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
source "$BASE_DIR/config/env.sh"

DOMAIN=$1
EMAIL="admin@$DOMAIN"
SERVER_IP=$(curl -s ifconfig.me)
NGINX_CONF="/etc/nginx/sites-available/$DOMAIN"

[[ -z "$DOMAIN" ]] && { echo "Usage: ./ssl.sh domain.com"; exit 1; }

command -v certbot >/dev/null || sudo apt install -y certbot python3-certbot-nginx

for i in {1..10}; do
    DOMAIN_IP=$(getent hosts "$DOMAIN" | awk '{print $1}')
    [[ "$DOMAIN_IP" == "$SERVER_IP" ]] && break
    [[ $i -eq 10 ]] && { echo "DNS Fail"; exit 1; }
    echo "Waiting DNS ($i/10)..." && sleep 60
done

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
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
EOF

sudo ln -sf "$NGINX_CONF" /etc/nginx/sites-enabled/
sudo rm -f /etc/nginx/sites-enabled/default
sudo nginx -t && sudo systemctl reload nginx

sudo certbot --nginx -d $DOMAIN -d www.$DOMAIN --non-interactive --agree-tos -m $EMAIL --redirect
sudo certbot renew --dry-run

echo "--------------------------------------"
echo "[DONE]: SSL Completed: $DOMAIN"
echo "--------------------------------------"