#!/bin/bash
set -e

BASE_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
source "$BASE_DIR/config/env.sh"

SSH_DIR="$HOME/.ssh"
SSH_KEY="$SSH_DIR/id_ed25519"
GIT_BRANCH="${1:-$DEFAULT_BRANCH}"

IS_WSL=false
if grep -qi microsoft /proc/version; then
  IS_WSL=true
fi

echo "--------------------------------------"
echo "ZentraCore Install"
echo "Branch: $GIT_BRANCH"
echo "WSL: $IS_WSL"
echo "--------------------------------------"

sudo apt update
sudo apt install -y curl git nginx ca-certificates gnupg htop unzip

if [ "$IS_WSL" = false ]; then
  sudo apt install -y ufw fail2ban
fi

if [ "$IS_WSL" = false ]; then
  sudo timedatectl set-timezone "$TIMEZONE"
fi

if [ "$IS_WSL" = false ] && ! swapon --show | grep -q swapfile; then
  sudo fallocate -l "$SWAP_SIZE" /swapfile
  sudo chmod 600 /swapfile
  sudo mkswap /swapfile
  sudo swapon /swapfile
  echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab
fi

if command -v ufw >/dev/null 2>&1 && [ "$IS_WSL" = false ]; then
  if ufw app list | grep -q OpenSSH; then
    sudo ufw allow OpenSSH
  else
    sudo ufw allow 22
  fi
  sudo ufw allow 80
  sudo ufw allow 443
  sudo ufw --force enable
fi

curl -fsSL https://deb.nodesource.com/setup_$NODE_VERSION.x | sudo -E bash -
sudo apt install -y nodejs
sudo npm install -g pnpm pm2

mkdir -p "$SSH_DIR"
chmod 700 "$SSH_DIR"

if [ ! -f "$SSH_KEY" ]; then
  ssh-keygen -t ed25519 -C "zentracore@$(hostname)" -f "$SSH_KEY" -N ""
  echo ""
  echo "👉 Add this SSH key to GitHub:"
  cat "$SSH_KEY.pub"
  read -p "Press ENTER after adding the key..."
fi

ssh-keyscan github.com >> "$SSH_DIR/known_hosts" 2>/dev/null

sudo mkdir -p "$APP_DIR"
sudo chown -R "$USER:$USER" "$APP_DIR"

if [ ! -d "$APP_DIR/.git" ]; then
  git clone -b "$GIT_BRANCH" "$GIT_REPO" "$APP_DIR"
else
  echo "Repo already exists, skipping clone"
fi

cd "$APP_DIR"
pnpm install
pnpm build

pm2 start pnpm --name "$APP_NAME" -- start
pm2 save

if [ "$IS_WSL" = false ]; then
  pm2 startup systemd -u "$USER" --hp "$HOME" | tail -n 1 | bash
fi

NGINX_CONF="/etc/nginx/sites-available/$APP_NAME"

sudo tee "$NGINX_CONF" >/dev/null <<EOF
server {
  listen 80;
  server_name _;
  location / {
    proxy_pass http://127.0.0.1:$APP_PORT;
    proxy_set_header Host \$host;
    proxy_set_header Upgrade \$http_upgrade;
    proxy_set_header Connection 'upgrade';
  }
}
EOF

sudo ln -sf "$NGINX_CONF" /etc/nginx/sites-enabled/
sudo nginx -t
sudo systemctl reload nginx || true

echo "Installed successfully"
