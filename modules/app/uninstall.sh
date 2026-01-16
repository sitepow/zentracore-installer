#!/bin/bash
set -e

if [ "$EUID" -ne 0 ]; then
  echo "❌ Please run as root"
  echo "👉 Trying again with sudo..."
  exec sudo bash "$0" "$@"
fi

echo "--------------------------------------"
echo "ZentraCore Uninstall"
echo "--------------------------------------"

read -p "Type YES to continue (THIS WILL DELETE DATA): " CONFIRM
if [ "$CONFIRM" != "YES" ]; then
  echo "Abort."
  exit 1
fi

echo "Stopping services..."
systemctl stop nginx || true
systemctl stop docker || true
systemctl stop pm2-root || true

echo "Removing nginx..."
apt purge -y nginx nginx-common nginx-core || true
rm -rf /etc/nginx
rm -rf /var/www

echo "Removing SSL (Let's Encrypt)..."
apt purge -y certbot python3-certbot-nginx || true
rm -rf /etc/letsencrypt
rm -rf /var/lib/letsencrypt

echo "Removing app directories..."
rm -rf /opt/app
rm -rf /srv/app
rm -rf /home/appuser

echo "Removing app user..."
userdel -r appuser 2>/dev/null || true

echo "Removing PM2..."
npm uninstall -g pm2 || true
rm -rf /root/.pm2
rm -rf /home/*/.pm2

echo "Removing Docker..."
apt purge -y docker docker-engine docker.io containerd runc || true
rm -rf /var/lib/docker
rm -rf /etc/docker

echo "Reset firewall..."
ufw --force reset || true
ufw disable || true

echo "Cleaning cron jobs..."
rm -f /etc/cron.d/*
crontab -r || true

echo "Autoremove unused packages..."
apt autoremove -y
apt autoclean -y

echo "Uninstall completed"
