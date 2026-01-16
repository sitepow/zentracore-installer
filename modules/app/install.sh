#!/bin/bash
set -e

BASE_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
source "$BASE_DIR/config/env.sh"

GIT_BRANCH="${1:-$DEFAULT_BRANCH}"
SSH_DIR="$HOME/.ssh"
SSH_KEY="$SSH_DIR/id_ed25519"

IS_WSL=false
if grep -qi microsoft /proc/version; then
  IS_WSL=true
fi

SERVER_IP=$(hostname -I | awk '{print $1}')
APP_URL="http://$SERVER_IP:$APP_PORT"

echo "--------------------------------------"
echo "ZentraCore Install"
echo "Branch: $GIT_BRANCH"
echo "WSL: $IS_WSL"
echo "APP URL: $APP_URL"
echo "--------------------------------------"

sudo apt update
sudo apt install -y \
  curl git nginx ca-certificates gnupg htop unzip \
  postgresql postgresql-contrib

if [ "$IS_WSL" = false ]; then
  sudo apt install -y ufw fail2ban
  sudo timedatectl set-timezone "$TIMEZONE"
fi

sudo systemctl enable postgresql
sudo systemctl start postgresql

if [ "$IS_WSL" = false ] && ! swapon --show | grep -q swapfile; then
  sudo fallocate -l "$SWAP_SIZE" /swapfile
  sudo chmod 600 /swapfile
  sudo mkswap /swapfile
  sudo swapon /swapfile
  echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab
fi

if command -v ufw >/dev/null 2>&1 && [ "$IS_WSL" = false ]; then
  sudo ufw allow OpenSSH || sudo ufw allow 22
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

echo "Setting up PostgreSQL..."

sudo -u postgres psql <<EOF
DO \$\$
BEGIN
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = '$DB_USER') THEN
    CREATE ROLE $DB_USER LOGIN PASSWORD '$DB_PASSWORD';
  END IF;

  IF NOT EXISTS (
    SELECT FROM pg_database WHERE datname = '$DB_NAME'
  ) THEN
    CREATE DATABASE $DB_NAME OWNER $DB_USER;
  END IF;
END
\$\$;
EOF

sudo rm -rf "$APP_DIR"
sudo mkdir -p "$APP_DIR"
sudo chown -R "$USER:$USER" "$APP_DIR"

git clone -b "$GIT_BRANCH" "$GIT_REPO" "$APP_DIR"

ENV_FILE="$APP_DIR/.env"

if [ ! -f "$ENV_FILE" ]; then
  echo "Creating .env file..."
  cat > "$ENV_FILE" <<EOF
DATABASE_URL="postgresql://$DB_USER:$DB_PASSWORD@localhost:$DB_PORT/$DB_NAME"

APP_URL="$APP_URL"
NEXT_PUBLIC_APP_URL="$APP_URL"

AUTH_SECRET="$(openssl rand -base64 32)"
NEXTAUTH_URL="$APP_URL"

GOOGLE_CLIENT_ID=""
GOOGLE_CLIENT_SECRET=""
FACEBOOK_CLIENT_ID=""
FACEBOOK_CLIENT_SECRET=""

STRIPE_SECRET_KEY=""
STRIPE_WEBHOOK_SECRET=""

OMISE_SECRET_KEY=""
NEXT_PUBLIC_OMISE_PUBLIC_KEY=""

SUPABASE_URL=""
SUPABASE_SERVICE_ROLE_KEY=""
NEXT_PUBLIC_SUPABASE_URL=""
NEXT_PUBLIC_SUPABASE_ANON_KEY=""
EOF
fi

cd "$APP_DIR"

pnpm install
pnpm prisma generate
pnpm prisma migrate deploy || pnpm prisma db push
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
sudo systemctl reload nginx

echo "--------------------------------------"
echo "ZentraCore installed successfully"
echo "App URL: $APP_URL"
echo "--------------------------------------"
