#!/bin/bash
set -e

[[ "$EUID" -ne 0 ]] && exec sudo bash "$0" "$@"

read -p "Type YES to NUKE EVERYTHING: " CONFIRM
[[ "$CONFIRM" != "YES" ]] && exit 1

systemctl stop nginx pgbouncer postgresql docker pm2-root || true
pkill -9 node || true
pkill -9 pnpm || true
pkill -9 npm || true
lsof -ti tcp:3000,4000,80,443,5432,6432 | xargs -r kill -9 || true

rm -rf /etc/systemd/system/pm2* /etc/systemd/user/pm2* /home/*/.config/systemd/user/pm2*
systemctl daemon-reload

apt purge -y nginx* certbot* nodejs postgresql* pgbouncer docker-ce* docker.io containerd runc ufw fail2ban
apt autoremove -y && apt autoclean -y

rm -rf /etc/nginx /var/www /etc/letsencrypt /var/lib/letsencrypt
rm -rf /var/lib/postgresql /etc/postgresql /etc/pgbouncer
rm -rf /var/lib/docker /etc/docker
rm -rf /opt/* /srv/* /home/*/zentracore* /home/*/.env
rm -rf /usr/lib/node_modules /root/.npm /root/.pnpm-store /root/.pm2
rm -rf /home/*/.npm /home/*/.pnpm-store /home/*/.pm2

ufw --force reset || true
ufw disable || true
crontab -r || true
rm -f /etc/cron.d/*
userdel -r appuser 2>/dev/null || true

echo "--------------------------------------"
echo "[DONE]: Uninstall completed!"
echo "--------------------------------------"