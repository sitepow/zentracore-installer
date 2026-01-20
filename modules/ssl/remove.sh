#!/bin/bash
set -e

BASE_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
source "$BASE_DIR/config/env.sh"

DOMAIN=$1
[[ -z "$DOMAIN" ]] && { echo "Usage: ./remove-ssl.sh domain.com"; exit 1; }

echo "[SYSTEM]: Removing SSL but RESTORING Optimized Nginx Config..."

sudo rm -f "/etc/nginx/sites-enabled/$DOMAIN"
sudo rm -f "/etc/nginx/sites-available/$DOMAIN"

if sudo certbot certificates 2>/dev/null | grep -q "$DOMAIN"; then
    echo "[SYSTEM]: Deleting certificate from Let's Encrypt storage..."
    sudo certbot delete --cert-name "$DOMAIN" --non-interactive
fi

sudo tee "/etc/nginx/sites-available/$DOMAIN" > /dev/null <<EOF
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
        proxy_buffers 8 16k;
        proxy_buffer_size 32k;
    }
}
EOF

sudo ln -sf "/etc/nginx/sites-available/$DOMAIN" "/etc/nginx/sites-enabled/"
sudo nginx -t && sudo systemctl reload nginx

echo "--------------------------------------"
echo "[DONE]: SSL Removed. Nginx restored to Optimized Port 80."
echo "--------------------------------------"