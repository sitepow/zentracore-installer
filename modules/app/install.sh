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
echo " ZentraCore Production Install"
echo " CPU: $CPU_CORES cores | RAM: ${MEM_TOTAL}MB"
echo " WSL: $IS_WSL"
echo " APP: $APP_URL"
echo "--------------------------------------"

if [ "$IS_WSL" = false ]; then
sudo tee /etc/sysctl.d/99-zentracore.conf >/dev/null <<EOF
fs.file-max = 2097152
net.core.somaxconn = 65535
net.ipv4.tcp_fin_timeout = 15
net.ipv4.ip_local_port_range = 1024 65000
net.ipv4.tcp_fastopen = 3
vm.swappiness = 10
EOF
sudo sysctl --system >/dev/null
fi

sudo apt update
sudo apt install -y \
  curl git nginx ca-certificates gnupg htop unzip \
  postgresql postgresql-contrib \
  pgbouncer redis-server

REDIS_MAX_MEM=$((MEM_TOTAL / 8))
sudo sed -i "s/^# maxmemory .*/maxmemory ${REDIS_MAX_MEM}mb/" /etc/redis/redis.conf
sudo sed -i "s/^# maxmemory-policy .*/maxmemory-policy allkeys-lru/" /etc/redis/redis.conf
sudo systemctl restart redis-server

PG_VERSION=$(psql -V | awk '{print $3}' | cut -d. -f1)
PG_CONF="/etc/postgresql/$PG_VERSION/main/postgresql.conf"

SB=$((MEM_TOTAL / 4))
ECS=$((MEM_TOTAL * 3 / 4))
WM=$((MEM_TOTAL / CPU_CORES / 16))
[ "$WM" -lt 4 ] && WM=4

sudo sed -i "s/^#listen_addresses.*/listen_addresses = 'localhost'/" "$PG_CONF"

grep -q "ZENTRACORE_TUNING" "$PG_CONF" || sudo tee -a "$PG_CONF" >/dev/null <<EOF
# ZENTRACORE_TUNING
shared_buffers = ${SB}MB
effective_cache_size = ${ECS}MB
work_mem = ${WM}MB
maintenance_work_mem = $((MEM_TOTAL / 16))MB
max_connections = 200
checkpoint_completion_target = 0.9
random_page_cost = 1.1
EOF

sudo systemctl restart postgresql

sudo -u postgres psql <<EOF
CREATE ROLE $DB_USER LOGIN PASSWORD '$DB_PASSWORD'
  NOSUPERUSER NOCREATEDB NOCREATEROLE INHERIT;
EOF

sudo -u postgres psql <<EOF
CREATE DATABASE $DB_NAME OWNER $DB_USER;
EOF

sudo tee /etc/pgbouncer/pgbouncer.ini >/dev/null <<EOF
[databases]
$DB_NAME = host=127.0.0.1 port=5432 dbname=$DB_NAME

[pgbouncer]
listen_addr = 127.0.0.1
listen_port = 6432
auth_type = scram-sha-256
auth_query = SELECT usename, passwd FROM pg_shadow WHERE usename=\$1
pool_mode = transaction
max_client_conn = 5000
default_pool_size = $((CPU_CORES * 20))
ignore_startup_parameters = extra_float_digits
EOF

sudo systemctl restart pgbouncer
sudo systemctl enable pgbouncer

curl -fsSL https://deb.nodesource.com/setup_$NODE_VERSION.x | sudo -E bash -
sudo apt install -y nodejs
sudo npm install -g pnpm pm2

sudo rm -rf "$APP_DIR"
sudo mkdir -p "$APP_DIR"
sudo chown -R "$USER:$USER" "$APP_DIR"

git clone -b "$GIT_BRANCH" "$GIT_REPO" "$APP_DIR"
cd "$APP_DIR"

cat > .env <<EOF
DATABASE_URL=postgresql://$DB_USER:$DB_PASSWORD@127.0.0.1:6432/$DB_NAME
REDIS_URL=redis://127.0.0.1:6379
APP_URL=$APP_URL
NEXT_PUBLIC_APP_URL=$APP_URL
NEXTAUTH_URL=$APP_URL
NEXTAUTH_SECRET=$(openssl rand -base64 32)
NODE_ENV=production
GOOGLE_CLIENT_ID="dummy"
GOOGLE_CLIENT_SECRET="dummy"
FACEBOOK_CLIENT_ID="dummy"
FACEBOOK_CLIENT_SECRET="dummy"
STRIPE_SECRET_KEY="sk_test_dummy"
STRIPE_WEBHOOK_SECRET="whsec_dummy"
OMISE_SECRET_KEY="pkey_test_dummy"
NEXT_PUBLIC_OMISE_PUBLIC_KEY="pkey_test_dummy_public"
SUPABASE_URL="https://dummy.supabase.co"
SUPABASE_SERVICE_ROLE_KEY="dummy"
NEXT_PUBLIC_SUPABASE_URL="https://dummy.supabase.co"
NEXT_PUBLIC_SUPABASE_ANON_KEY="dummy"
EOF

pnpm install
pnpm prisma generate
pnpm prisma migrate deploy || pnpm prisma db push
pnpm build

cat > ecosystem.config.js <<EOF
module.exports = {
  apps: [{
    name: "$APP_NAME",
    script: "node_modules/next/dist/bin/next",
    args: "start -p $APP_PORT -H 0.0.0.0",
    exec_mode: "cluster",
    instances: "max",
    env: { NODE_ENV: "production" }
  }]
}
EOF

pm2 delete "$APP_NAME" || true
pm2 start ecosystem.config.js
pm2 save

sudo rm -f /etc/nginx/sites-enabled/default
sudo tee /etc/nginx/sites-available/$APP_NAME >/dev/null <<EOF
server {
  listen 80;
  server_name _;
  gzip on;

  location / {
    proxy_pass http://127.0.0.1:$APP_PORT;
    proxy_http_version 1.1;
    proxy_set_header Upgrade \$http_upgrade;
    proxy_set_header Connection 'upgrade';
    proxy_set_header Host \$host;
  }
}
EOF

sudo ln -sf /etc/nginx/sites-available/$APP_NAME /etc/nginx/sites-enabled/
sudo nginx -t
sudo systemctl reload nginx

echo "--------------------------------------"
echo " INSTALL DONE"
echo " $APP_URL"
echo "--------------------------------------"
