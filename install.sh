#!/bin/bash
set -e

echo "--------------------------------------"
echo "   ZentraCore Auto Installer (VPS)"
echo "--------------------------------------"

APP_NAME="zentracore"
APP_DIR="/var/www/zentracore"

GIT_REPO="git@github.com:sitepow/zentracore.git"
GIT_BRANCH="main"

NODE_VERSION="20"
APP_PORT="3000"

TIMEZONE="Asia/Bangkok"
SWAP_SIZE="2G"

SSH_DIR="$HOME/.ssh"
SSH_KEY="$SSH_DIR/id_ed25519"

echo "[1/9] System update"
sudo apt update && sudo apt upgrade -y
sudo apt install -y \
  curl git ufw fail2ban nginx \
  ca-certificates gnupg htop unzip

sudo timedatectl set-timezone $TIMEZONE

if ! swapon --show | grep -q swapfile; then
  echo "[2/9] Create swap ($SWAP_SIZE)"
  sudo fallocate -l $SWAP_SIZE /swapfile
  sudo chmod 600 /swapfile
  sudo mkswap /swapfile
  sudo swapon /swapfile
  echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab
fi

echo "[3/9] Configure firewall"
sudo ufw allow OpenSSH
sudo ufw allow 80
sudo ufw allow 443
sudo ufw --force enable

echo "[4/9] Install Node.js $NODE_VERSION + pnpm + pm2"
curl -fsSL https://deb.nodesource.com/setup_$NODE_VERSION.x | sudo -E bash -
sudo apt install -y nodejs
sudo npm install -g pnpm pm2

echo "[5/9] Prepare SSH key for GitHub"

mkdir -p $SSH_DIR
chmod 700 $SSH_DIR

if [ ! -f "$SSH_KEY" ]; then
  ssh-keygen -t ed25519 -C "zentracore@$(hostname)" -f $SSH_KEY -N ""

  echo ""
  echo "------------------------------------------------"
  echo " ADD THIS PUBLIC KEY TO GITHUB DEPLOY KEY"
  echo "------------------------------------------------"
  cat "$SSH_KEY.pub"
  echo "------------------------------------------------"
  echo ""
  echo "➡ GitHub Repo > Settings > Deploy Keys"
  echo "➡ Paste key + Enable READ access"
  echo ""
  echo "Press ENTER after you finish..."
  read
fi

ssh-keyscan github.com >> $SSH_DIR/known_hosts

echo "[6/9] Clone / Update repo"

sudo mkdir -p $APP_DIR
sudo chown -R $USER:$USER $APP_DIR

if [ ! -d "$APP_DIR/.git" ]; then
  git clone -b $GIT_BRANCH $GIT_REPO $APP_DIR
else
  cd $APP_DIR
  git fetch
  git checkout $GIT_BRANCH
  git pull
fi

echo "[7/9] Build application"
cd $APP_DIR
pnpm install
pnpm build

echo "[8/9] Start app with PM2"
pm2 start pnpm --name "$APP_NAME" -- start
pm2 save
pm2 startup systemd -u $USER --hp $HOME | tail -n 1 | bash

echo "[9/9] Configure Nginx"

NGINX_CONF="/etc/nginx/sites-available/$APP_NAME"

sudo tee $NGINX_CONF > /dev/null <<EOF
server {
    listen 80;
    server_name _;

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

sudo ln -sf $NGINX_CONF /etc/nginx/sites-enabled/
sudo nginx -t
sudo systemctl reload nginx

echo ""
echo "--------------------------------------"
echo "ZentraCore is LIVE! -> http://<VPS-IP>"
echo "--------------------------------------"
