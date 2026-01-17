#!/bin/bash
set -e

DOMAIN=$1
[[ -z "$DOMAIN" ]] && { echo "Usage: ./remove-ssl.sh domain.com"; exit 1; }

sudo rm -f "/etc/nginx/sites-enabled/$DOMAIN"

if sudo certbot certificates | grep -q "$DOMAIN"; then
    sudo certbot delete --cert-name "$DOMAIN" --non-interactive
fi

sudo nginx -t && sudo systemctl reload nginx

echo "--------------------------------------"
echo "[DONE]: SSL Removed: $DOMAIN"
echo "--------------------------------------"