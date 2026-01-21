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

echo "--------------------------------------------------"
echo "ZentraCore Production Install"
echo " OS: $(lsb_release -ds 2>/dev/null || echo "Linux")"
echo " CPU: $CPU_CORES cores | RAM: ${MEM_TOTAL}MB"
echo " APP: $APP_URL"
echo "--------------------------------------------------"

if [ "$IS_WSL" = false ] && [ $(swapon --show | wc -l) -eq 0 ]; then
    echo "[SYSTEM]: Creating 2GB Swap file for build stability..."
    sudo fallocate -l 2G /swapfile || sudo dd if=/dev/zero of=/swapfile bs=1M count=2048
    sudo chmod 600 /swapfile
    sudo mkswap /swapfile
    sudo swapon /swapfile
    echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab
    echo "[SUCCESS]: Swap set up."
fi

if [ "$IS_WSL" = false ]; then
    echo "[SYSTEM]: Optimizing Network and File System..."
    sudo tee /etc/sysctl.d/99-zentracore.conf >/dev/null <<EOF
fs.file-max = 2097152
net.ipv4.tcp_fastopen = 3
net.core.somaxconn = 65535
net.core.netdev_max_backlog = 65535
net.ipv4.tcp_max_syn_backlog = 65535
net.ipv4.tcp_fin_timeout = 10
vm.swappiness = 10
vm.vfs_cache_pressure = 50
EOF
    sudo sysctl --system >/dev/null
fi

echo "[SYSTEM]: Updating and Installing Software Stack..."
sudo apt update
sudo apt install -y curl git nginx ca-certificates gnupg unzip htop postgresql postgresql-contrib redis-server fail2ban

OS_RESERVE=$((MEM_TOTAL * 15 / 100))
PG_BUDGET=$((MEM_TOTAL * 40 / 100))
NODE_BUDGET=$((MEM_TOTAL * 25 / 100))
REDIS_BUDGET=$((MEM_TOTAL * 10 / 100))

if [ "$IS_WSL" = false ]; then
  sudo apt install -y ufw fail2ban
  sudo timedatectl set-timezone "$TIMEZONE"
fi

REDIS_MAX_MEM=$REDIS_BUDGET
[ "$REDIS_MAX_MEM" -lt 64 ] && REDIS_MAX_MEM=64
[ "$REDIS_MAX_MEM" -gt 1024 ] && REDIS_MAX_MEM=1024

sudo sed -i "s/^# maxmemory .*/maxmemory ${REDIS_MAX_MEM}mb/" /etc/redis/redis.conf
sudo sed -i "s/^# maxmemory-policy .*/maxmemory-policy allkeys-lru/" /etc/redis/redis.conf
sudo systemctl restart redis-server

PG_VERSION=$(psql -V | awk '{print $3}' | cut -d. -f1)
PG_CONF="/etc/postgresql/$PG_VERSION/main/postgresql.conf"
PG_HBA="/etc/postgresql/$PG_VERSION/main/pg_hba.conf"

grep -q "ZENTRACORE_REMOTE_ACCESS" "$PG_HBA" || sudo tee -a "$PG_HBA" >/dev/null <<EOF

# ZENTRACORE_REMOTE_ACCESS
host    all             all             0.0.0.0/0               md5
host    all             all             ::/0                    md5
EOF

PG_SHARED_BUFFERS=$((PG_BUDGET * 25 / 100))
PG_CACHE_SIZE=$((PG_BUDGET * 75 / 100))
PG_MAINT_MEM=$((PG_BUDGET * 10 / 100))

PG_WORK_MEM=$((PG_BUDGET / CPU_CORES / 8))
[ "$PG_WORK_MEM" -lt 4 ] && PG_WORK_MEM=4
[ "$PG_WORK_MEM" -gt 64 ] && PG_WORK_MEM=64

PG_MAX_CONN=$((CPU_CORES * 20))
[ "$PG_MAX_CONN" -gt 200 ] && PG_MAX_CONN=200

sudo sed -i "/^listen_addresses\s*=.*/d" "$PG_CONF"
sudo sed -i "/^#listen_addresses\s*=.*/d" "$PG_CONF"

grep -q "ZENTRACORE_NETWORK" "$PG_CONF" || sudo tee -a "$PG_CONF" >/dev/null <<EOF

# ZENTRACORE_NETWORK
listen_addresses = '*'
EOF

sudo sed -i "s/^shared_buffers =.*/shared_buffers = ${PG_SHARED_BUFFERS}MB/" "$PG_CONF"
grep -q "ZENTRACORE_TUNING" "$PG_CONF" || sudo tee -a "$PG_CONF" >/dev/null <<EOF

# ZENTRACORE_TUNING
shared_buffers = ${PG_SHARED_BUFFERS}MB
effective_cache_size = ${PG_CACHE_SIZE}MB
work_mem = ${PG_WORK_MEM}MB
maintenance_work_mem = ${PG_MAINT_MEM}MB
max_connections = ${PG_MAX_CONN}
checkpoint_completion_target = 0.9
synchronous_commit = off
random_page_cost = 1.1
effective_io_concurrency = 200
work_mem = $((PG_BUDGET / CPU_CORES / 8))MB
EOF

sudo sed -i "s/^local\s\+all\s\+all\s\+.*/local all all md5/" "$PG_HBA"
sudo sed -i "s/^host\s\+all\s\+all\s\+127.0.0.1\/32\s\+.*/host all all 127.0.0.1\/32 md5/" "$PG_HBA"
sudo sed -i "s/^host\s\+all\s\+all\s\+::1\/128\s\+.*/host all all ::1\/128 md5/" "$PG_HBA"

sudo systemctl restart postgresql

sudo -u postgres psql <<EOF
REVOKE CONNECT ON DATABASE $DB_NAME FROM public;
SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname = '$DB_NAME';

DROP DATABASE IF EXISTS ${DB_NAME};
DROP DATABASE IF EXISTS ${DB_NAME}_shadow;
DROP ROLE IF EXISTS $DB_USER;

CREATE ROLE $DB_USER LOGIN PASSWORD '$DB_PASSWORD' CREATEDB;
CREATE DATABASE $DB_NAME OWNER $DB_USER;
CREATE DATABASE ${DB_NAME}_shadow OWNER $DB_USER;

GRANT ALL PRIVILEGES ON DATABASE $DB_NAME TO $DB_USER;
GRANT ALL PRIVILEGES ON DATABASE ${DB_NAME}_shadow TO $DB_USER;
EOF

if ! command -v node &> /dev/null; then
    curl -fsSL https://deb.nodesource.com/setup_$NODE_VERSION.x | sudo -E bash -
    sudo apt install -y nodejs
fi
sudo npm install -g pnpm pm2

sudo rm -rf "$APP_DIR"
sudo mkdir -p "$APP_DIR"
sudo chown -R "$USER:$USER" "$APP_DIR"
echo "--------------------------------------"
echo " Checking SSH key for GitHub"
echo "--------------------------------------"

SSH_DIR="$HOME/.ssh"
SSH_KEY="$SSH_DIR/id_ed25519"
SSH_PUB="$SSH_KEY.pub"

mkdir -p "$SSH_DIR"
chmod 700 "$SSH_DIR"

if [ -f "$SSH_KEY" ] && [ -f "$SSH_PUB" ]; then
  echo "SSH key already exists, skipping generation"
else
  echo "No SSH key found, generating new one..."
  ssh-keygen -t ed25519 -C "zentracore@$(hostname)" -f "$SSH_KEY" -N ""

  chmod 600 "$SSH_KEY"
  chmod 644 "$SSH_PUB"

  echo ""
  echo "--------------------------------------"
  echo " COPY THIS SSH PUBLIC KEY TO GITHUB"
  echo "--------------------------------------"
  cat "$SSH_PUB"
  echo "--------------------------------------"
  echo "GitHub → Settings → SSH and GPG keys → New SSH key"
  echo "Paste the key above, then press ENTER to continue"
  read -r
fi

git clone -b "$GIT_BRANCH" "$GIT_REPO" "$APP_DIR"
cd "$APP_DIR"

cat > .env <<EOF
# --- App Configuration ---
NODE_ENV=production
APP_URL=$APP_URL
NEXTAUTH_URL=$APP_URL

# --- Database & Cache ---
DATABASE_URL=postgresql://$DB_USER:$DB_PASSWORD@127.0.0.1:$DB_PORT/$DB_NAME
REDIS_URL=redis://127.0.0.1:6379

# --- Authentication (NextAuth) ---
NEXTAUTH_SECRET=$(openssl rand -base64 32)

# Google Provider
GOOGLE_CLIENT_ID="zentracore_"
GOOGLE_CLIENT_SECRET="zentracore_"

# Facebook Provider
FACEBOOK_CLIENT_ID="zentracore_"
FACEBOOK_CLIENT_SECRET="zentracore_"

# --- Payment Gateways ---
# Stripe
STRIPE_SECRET_KEY="sk_test_zentracore_"
STRIPE_WEBHOOK_SECRET="whsec_zentracore_"

# Omise
OMISE_SECRET_KEY="pkey_test_zentracore_"
NEXT_PUBLIC_OMISE_PUBLIC_KEY="zentracore_"
EOF

pnpm install
pnpm prisma generate
pnpm prisma migrate deploy
pnpm build

cat > ecosystem.config.js <<EOF
module.exports = {
  apps: [{
    name: "$APP_NAME",
    script: "node_modules/next/dist/bin/next",
    args: "start -p $APP_PORT -H 0.0.0.0",
    instances: "max",
    exec_mode: "cluster",
    max_memory_restart: "${NODE_BUDGET}M",
    wait_ready: true,
    listen_timeout: 10000,
    kill_timeout: 5000,
    env: {
      NODE_ENV: "production",
      NODE_OPTIONS: "--max-old-space-size=${NODE_BUDGET}"
    }
  }]
}
EOF

pm2 delete "$APP_NAME" || true
pm2 start ecosystem.config.js
pm2 save

if [ "$IS_WSL" = false ]; then
  pm2 startup systemd -u "$USER" --hp "$HOME"
fi

sudo rm -f /etc/nginx/sites-enabled/default
sudo tee /etc/nginx/sites-available/$APP_NAME >/dev/null <<EOF
server {
    listen 80;
    server_name _;
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
        proxy_set_header X-Forwarded-For \$remote_addr;
        proxy_buffers 8 16k;
        proxy_buffer_size 32k;
    }
}
EOF

sudo ln -sf /etc/nginx/sites-available/$APP_NAME /etc/nginx/sites-enabled/
sudo rm -f /etc/nginx/sites-enabled/default
sudo nginx -t && sudo systemctl reload nginx

if [ "$IS_WSL" = false ]; then
    sudo ufw allow OpenSSH
    sudo ufw allow 80
    sudo ufw allow 443
    sudo ufw allow 5432
    sudo ufw --force enable
fi

echo "--------------------------------------"
echo " [DONE]: Install completed!"
echo " $APP_URL"
echo "--------------------------------------"
