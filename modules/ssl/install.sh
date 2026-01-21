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

echo "[SYSTEM]: Checking DNS for $DOMAIN..."
for i in {1..10}; do
    DOMAIN_IP=$(getent hosts "$DOMAIN" | awk '{print $1}')
    [[ "$DOMAIN_IP" == "$SERVER_IP" ]] && break
    [[ $i -eq 10 ]] && { echo "DNS Fail: IP is $DOMAIN_IP but expected $SERVER_IP"; exit 1; }
    echo "Waiting DNS ($i/10)..." && sleep 30
done

HAS_SSL=false
if [ -d "/etc/letsencrypt/live/$DOMAIN" ]; then
    echo "[INFO]: SSL Certificate for $DOMAIN already exists. Skipping new request."
    HAS_SSL=true
fi

echo "[SYSTEM]: Configuring Nginx for $DOMAIN with optimizations..."
sudo tee "$NGINX_CONF" > /dev/null <<EOF
server {
    listen 80;
    server_name $DOMAIN www.$DOMAIN;
    client_max_body_size 50M;

    gzip on;
    gzip_comp_level 5;
    gzip_min_length 256;
    gzip_proxied any;
    gzip_types text/plain text/css application/json application/javascript application/x-javascript text/xml application/xml text/javascript;

    location /_next/static/ {
        alias $APP_DIR/.next/static/;
        expires 365d;
        access_log off;
        add_header Cache-Control "public, max-age=31536000, immutable";
    }

    location /uploads/ {
        alias $APP_DIR/public/uploads/;
        expires 30d;
        access_log off;
        add_header Cache-Control "public, max-age=2592000";
        location ~* \.(php|sh|pl|py|js)$ { deny all; }
    }

    location / {
        proxy_pass http://127.0.0.1:$APP_PORT;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_buffers 8 16k;
        proxy_buffer_size 32k;
    }
}
EOF

sudo rm -f /etc/nginx/sites-enabled/default
sudo rm -f "/etc/nginx/sites-enabled/$APP_NAME"

sudo ln -sf "$NGINX_CONF" /etc/nginx/sites-enabled/

if [ "$HAS_SSL" = false ]; then
    echo "[SYSTEM]: Requesting new SSL Certificate..."
    sudo certbot --nginx -d $DOMAIN -d www.$DOMAIN --non-interactive --agree-tos -m $EMAIL --redirect
    echo "[SYSTEM]: Testing auto-renewal process..."
    sudo certbot renew --dry-run
else
    echo "[SYSTEM]: Existing SSL found. Re-installing SSL to current Nginx config..."
    sudo certbot install --nginx -d $DOMAIN -d www.$DOMAIN --cert-name $DOMAIN --redirect --non-interactive
    
    echo "[SUCCESS]: Nginx reloaded with existing SSL."
    sudo nginx -t && sudo systemctl reload nginx
fi

echo "[SYSTEM]: Updating .env with HTTPS and Domain..."

NEW_URL="https://$DOMAIN"
ENV_FILE="$APP_DIR/.env"

if [ -f "$ENV_FILE" ]; then
    sudo sed -i "s|^APP_URL=.*|APP_URL=$NEW_URL|" "$ENV_FILE"
    sudo sed -i "s|^NEXTAUTH_URL=.*|NEXTAUTH_URL=$NEW_URL|" "$ENV_FILE"
    
    echo "[SUCCESS]: .env updated to $NEW_URL"

    echo "[SYSTEM]: Restarting PM2 to apply changes..."
    cd "$APP_DIR"
    pm2 restart "$APP_NAME" || pm2 start ecosystem.config.js
    pm2 save
else
    echo "[ERROR]: .env file not found at $ENV_FILE"
fi

echo "--------------------------------------"
echo "[DONE]: SSL & Nginx Optimized for: $DOMAIN"
echo "--------------------------------------"