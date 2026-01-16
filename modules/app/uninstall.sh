#!/bin/bash
set -e

if [ "$EUID" -ne 0 ]; then
  echo "Please run as root"
  echo "Trying again with sudo..."
  exec sudo bash "$0" "$@"
fi

echo "--------------------------------------"
echo "ZentraCore FULL UNINSTALL (NUKE MODE)"
echo "--------------------------------------"

read -p "Type YES to continue (THIS WILL DELETE EVERYTHING): " CONFIRM
if [ "$CONFIRM" != "YES" ]; then
  echo "Abort."
  exit 1
fi

echo "Killing app processes (ports 3000/4000/80/443)..."
for p in 3000 4000 80 443; do
  lsof -ti tcp:$p | xargs -r kill -9 || true
done

echo "Killing all node-related processes..."
pkill -9 node || true
pkill -9 pnpm || true
pkill -9 npm || true

echo "Stopping services..."
systemctl stop nginx || true
systemctl stop docker || true
systemctl stop pm2-root || true

echo "Removing systemd PM2 (user + root)..."
rm -rf /etc/systemd/system/pm2*
rm -rf /etc/systemd/user/pm2*
rm -rf /home/*/.config/systemd/user/pm2*

systemctl daemon-reload

echo "Removing nginx..."
apt purge -y nginx nginx-common nginx-core || true
rm -rf /etc/nginx
rm -rf /var/www

echo "Removing SSL (Let's Encrypt)..."
apt purge -y certbot python3-certbot-nginx || true
rm -rf /etc/letsencrypt
rm -rf /var/lib/letsencrypt

echo "Removing apps & data..."
rm -rf /opt
rm -rf /srv
rm -rf /var/www
rm -rf /home/*/zentracore*
rm -rf /home/*/.env

echo "Removing users..."
userdel -r appuser 2>/dev/null || true

echo "Removing Node / PNPM / PM2..."
npm uninstall -g pm2 || true
npm uninstall -g pnpm || true
apt purge -y nodejs || true

rm -rf /usr/lib/node_modules
rm -rf /root/.npm /root/.pnpm-store /root/.pm2
rm -rf /home/*/.npm /home/*/.pnpm-store /home/*/.pm2

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

echo "--------------------------------------"
echo "FULL UNINSTALL COMPLETED"
echo "Recommended: reboot or wsl --shutdown"
echo "--------------------------------------"
