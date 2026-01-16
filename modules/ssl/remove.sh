#!/bin/bash
set -e

DOMAIN=$1

if [ -z "$DOMAIN" ]; then
  echo "Usage: ./remove-ssl.sh your-domain.com"
  exit 1
fi

NGINX_CONF="/etc/nginx/sites-available/$DOMAIN"
NGINX_LINK="/etc/nginx/sites-enabled/$DOMAIN"

echo "--------------------------------------"
echo "Remove SSL for domain: $DOMAIN"
echo "--------------------------------------"

echo "[1/4] Disable nginx site"

if [ -L "$NGINX_LINK" ]; then
  sudo rm "$NGINX_LINK"
else
  echo "Nginx site not enabled"
fi

echo "[2/4] Remove SSL certificate"

if sudo certbot certificates | grep -q "$DOMAIN"; then
  sudo certbot delete --cert-name "$DOMAIN" --non-interactive
else
  echo "Certificate not found"
fi

echo "[3/4] Test nginx config"
sudo nginx -t

echo "[4/4] Reload nginx"
sudo systemctl reload nginx

echo "SSL remove completed"
