#!/bin/bash
set -e

BASE_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
source "$BASE_DIR/config/env.sh"

GIT_BRANCH="${1:-$DEFAULT_BRANCH}"
SERVER_IP=$(hostname -I | awk '{print $1}')
APP_URL="http://$SERVER_IP:$APP_PORT"

IS_WSL=false
grep -qi microsoft /proc/version && IS_WSL=true

CPU_CORES=$(nproc)
MEM_TOTAL=$(free -m | awk '/^Mem:/{print $2}')

echo "--------------------------------------"
echo " ZentraCore Install"
echo " CPU: $CPU_CORES cores"
echo " RAM: ${MEM_TOTAL}MB"
echo " WSL: $IS_WSL"
echo " APP: $APP_URL"
echo "--------------------------------------"

sudo apt update
sudo apt install -y \
  curl git nginx ca-certificates gnupg unzip htop \
  postgresql postgresql-contrib \
  redis-server

if [ "$IS_WSL" = false ]; then
  sudo apt install -y ufw fail2ban
  sudo timedatectl set-timezone "$TIMEZONE"
fi


sudo systemctl enable redis-server
sudo systemctl restart redis-server

PG_VERSION=$(psql -V | awk '{print $3}' | cut -d. -f1)
PG_CONF="/etc/postgresql/$PG_VERSION/main/postgresql.conf"
PG_HBA="/etc/postgresql/$PG_VERSION/main/pg_hba.conf"

sudo sed -i "s/^#\?listen_addresses.*/listen_addresses = 'localhost'/" "$PG_CONF"

sudo sed -i "s/^local\s\+all\s\+all\s\+.*/local all all scram-sha-256/" "$PG_HBA"
sudo sed -i "s/^host\s\+all\s\+all\s\+127.0.0.1\/32\s\+.*/host all all 127.0.0.1\/32 scram-sha-256/" "$PG_HBA"
sudo sed -i "s/^host\s\+all\s\+all\s\+::1\/128\s\+.*/host all all ::1\/128 scram-sha-256/" "$PG_HBA"

sudo systemctl restart postgresql

sudo -u postgres psql <<EOF
SELECT pg_terminate_backend(pid)
FROM pg_stat_activity
WHERE datname IN ('$DB_NAME', '${DB_NAME}_shadow');

DROP DATABASE IF EXISTS ${DB_NAME};
DROP DATABASE IF EXISTS ${DB_NAME}_shadow;
DROP ROLE IF EXISTS $DB_USER;

CREATE ROLE $DB_USER
  LOGIN
  PASSWORD '$DB_PASSWORD'
  CREATEDB
  CREATEROLE;

CREATE DATABASE $DB_NAME OWNER $DB_USER;
CREATE DATABASE ${DB_NAME}_shadow OWNER $DB_USER;

GRANT ALL PRIVILEGES ON DATABASE $DB_NAME TO $DB_USER;
GRANT ALL PRIVILEGES ON DATABASE ${DB_NAME}_shadow TO $DB_USER;

ALTER DATABASE $DB_NAME OWNER TO $DB_USER;
ALTER DATABASE ${DB_NAME}_shadow OWNER TO $DB_USER;
EOF

curl -fsSL https://deb.nodesource.com/setup_$NODE_VERSION.x | sudo -E bash -
sudo apt install -y nodejs
sudo npm install -g pnpm pm2

sudo rm -rf "$APP_DIR"
sudo mkdir -p "$APP_DIR"
sudo chown -R "$USER:$USER" "$APP_DIR"

echo "--------------------------------------"
echo " Checking SSH key for GitHub"
echo "--------------------------------------"

SSH_KEY="$HOME/.ssh/id_ed25519"

mkdir -p "$HOME/.ssh"
chmod 700 "$HOME/.ssh"

if [ ! -f "$SSH_KEY" ]; then
  echo "No SSH key found, generating new one..."
  ssh-keygen -t ed25519 -C "zentracore@$(hostname)" -f "$SSH_KEY" -N ""
else
  echo "SSH key already exists"
fi

chmod 600 "$SSH_KEY"
chmod 644 "$SSH_KEY.pub"

echo ""
echo "--------------------------------------"
echo "COPY THIS SSH PUBLIC KEY TO GITHUB"
echo "--------------------------------------"
cat "$SSH_KEY.pub"
echo "--------------------------------------"
echo ""
echo "GitHub → Settings → SSH and GPG keys → New SSH key"
echo "Paste the key above, then press ENTER to continue"
read -r

git clone -b "$GIT_BRANCH" "$GIT_REPO" "$APP_DIR"
cd "$APP_DIR"

cat > .env <<EOF
DATABASE_URL=postgresql://$DB_USER:$DB_PASSWORD@127.0.0.1:$DB_PORT/$DB_NAME
SHADOW_DATABASE_URL=postgresql://$DB_USER:$DB_PASSWORD@127.0.0.1:$DB_PORT/${DB_NAME}_shadow
REDIS_URL=redis://127.0.0.1:6379
APP_URL=$APP_URL
NEXT_PUBLIC_APP_URL=$APP_URL
NEXTAUTH_URL=$APP_URL
NEXTAUTH_SECRET=$(openssl rand -base64 32)
NODE_ENV=production
GOOGLE_CLIENT_ID="zentracore_"
GOOGLE_CLIENT_SECRET="zentracore_"
FACEBOOK_CLIENT_ID="zentracore_"
FACEBOOK_CLIENT_SECRET="zentracore_"
STRIPE_SECRET_KEY="zentracore_"
STRIPE_WEBHOOK_SECRET="zentracore_"
OMISE_SECRET_KEY="zentracore_"
NEXT_PUBLIC_OMISE_PUBLIC_KEY="zentracore_"
EOF

mkdir -p "$APP_DIR/public/uploads"
chmod 755 "$APP_DIR/public/uploads"
chown -R "$USER:$USER" "$APP_DIR/public/uploads"

pnpm install
pnpm prisma generate
pnpm prisma migrate deploy
pnpm build

pm2 delete "$APP_NAME" || true
pm2 start pnpm \
  --name "$APP_NAME" \
  -- start --port $APP_PORT
pm2 save

if [ "$IS_WSL" = false ]; then
  pm2 startup systemd -u "$USER" --hp "$HOME" || true
fi

sudo rm -f /etc/nginx/sites-enabled/default
sudo tee /etc/nginx/sites-available/$APP_NAME >/dev/null <<EOF
server {
  listen 80;
  server_name _;

  gzip on;
  gzip_types text/plain text/css application/json application/javascript application/xml image/svg+xml;

  location /_next/static/ {
    alias $APP_DIR/.next/static/;
    expires 365d;
    access_log off;
  }

  location /uploads/ {
    alias $APP_DIR/public/uploads/;
    autoindex off;

    expires 30d;
    access_log off;
    add_header Cache-Control "public, max-age=2592000";

    types {
      image/jpeg jpg jpeg;
      image/png png;
      image/webp webp;
      video/mp4 mp4;
    }

    default_type application/octet-stream;

    limit_except GET HEAD {
      deny all;
    }
  }

  location /health {
    access_log off;
    return 200 "OK";
  }

  location / {
    proxy_pass http://127.0.0.1:$APP_PORT;
    proxy_http_version 1.1;
    proxy_set_header Host \$host;
    proxy_set_header X-Forwarded-For \$remote_addr;
    proxy_set_header X-Real-IP \$remote_addr;
    proxy_set_header X-Forwarded-Proto \$scheme;
  }

  location ~* \.(php|sh|env|sql)$ {
    deny all;
  }
}
EOF

sudo ln -sf /etc/nginx/sites-available/$APP_NAME /etc/nginx/sites-enabled/
sudo nginx -t
sudo systemctl reload nginx

if [ "$IS_WSL" = false ]; then
  sudo ufw allow OpenSSH
  sudo ufw allow 80
  sudo ufw allow 443
  sudo ufw --force enable
fi

echo "--------------------------------------"
echo " [DONE]: Install completed!"
echo " $APP_URL"
echo "--------------------------------------"
