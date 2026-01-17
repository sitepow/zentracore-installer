#!/bin/bash
set -e

BASE_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
source "$BASE_DIR/config/env.sh"
GIT_BRANCH="${1:-$DEFAULT_BRANCH}"
SERVER_IP=$(hostname -I | awk '{print $1}')
APP_URL="http://$SERVER_IP:$APP_PORT"
IS_WSL=false
[[ $(grep -qi microsoft /proc/version) ]] && IS_WSL=true

CPU_CORES=$(nproc)
MEM_TOTAL=$(free -m | awk '/^Mem:/{print $2}')

if [ "$IS_WSL" = false ]; then
    sudo tee -a /etc/sysctl.conf >/dev/null <<EOF
fs.file-max = 2097152
net.core.somaxconn = 65535
net.ipv4.tcp_max_tw_buckets = 1440000
net.ipv4.ip_local_port_range = 1024 65000
net.ipv4.tcp_fin_timeout = 15
net.ipv4.tcp_window_scaling = 1
net.ipv4.tcp_max_syn_backlog = 3240000
net.ipv4.tcp_fastopen = 3
vm.swappiness = 10
EOF
    sudo sysctl -p >/dev/null
fi

sudo apt update
sudo apt install -y curl git nginx ca-certificates gnupg htop unzip postgresql postgresql-contrib pgbouncer redis-server
[[ "$IS_WSL" = false ]] && sudo apt install -y ufw fail2ban && sudo timedatectl set-timezone "$TIMEZONE"

REDIS_MAX_MEM=$((MEM_TOTAL / 8))
sudo sed -i "s/^# maxmemory .*/maxmemory ${REDIS_MAX_MEM}mb/" /etc/redis/redis.conf
sudo sed -i "s/^# maxmemory-policy .*/maxmemory-policy allkeys-lru/" /etc/redis/redis.conf
sudo systemctl restart redis-server

PG_VERSION=$(psql -V | awk '{print $3}' | cut -d. -f1)
PG_CONF="/etc/postgresql/$PG_VERSION/main/postgresql.conf"
PG_HBA="/etc/postgresql/$PG_VERSION/main/pg_hba.conf"

SB=$((MEM_TOTAL / 4))
ECS=$((MEM_TOTAL * 3 / 4))
WM=$((MEM_TOTAL / CPU_CORES / 16))
[[ $WM -lt 4 ]] && WM=4

if [ "$IS_WSL" = false ]; then
    sudo sed -i "s/^#listen_addresses.*/listen_addresses = '*'/" "$PG_CONF"
    sudo tee -a "$PG_CONF" >/dev/null <<EOF
shared_buffers = ${SB}MB
effective_cache_size = ${ECS}MB
work_mem = ${WM}MB
maintenance_work_mem = $((MEM_TOTAL / 16))MB
max_connections = $((CPU_CORES * 100))
checkpoint_completion_target = 0.9
synchronous_commit = off
random_page_cost = 1.1
effective_io_concurrency = 200
wal_buffers = 16MB
min_wal_size = 1GB
max_wal_size = 4GB
EOF
    [[ "$DB_REMOTE_ACCESS" = "true" ]] && sudo tee -a "$PG_HBA" >/dev/null <<EOF
host    $DB_NAME    $DB_USER    $DB_ALLOWED_CIDR    md5
EOF
    sudo systemctl restart postgresql
    sudo ufw allow 5432 && sudo ufw allow OpenSSH && sudo ufw allow 80 && sudo ufw allow 443 && sudo ufw --force enable
fi

PG_MD5=$(echo -n "$DB_PASSWORD$DB_USER" | md5sum | awk '{print $1}')
sudo tee "/etc/pgbouncer/pgbouncer.ini" >/dev/null <<EOF
[databases]
$DB_NAME = host=127.0.0.1 port=5432 dbname=$DB_NAME user=$DB_USER password=$DB_PASSWORD
[pgbouncer]
listen_addr = 0.0.0.0
listen_port = 6432
auth_type = md5
auth_file = /etc/pgbouncer/userlist.txt
pool_mode = transaction
max_client_conn = 10000
default_pool_size = $((CPU_CORES * 20))
reserve_pool_size = $((CPU_CORES * 5))
ignore_startup_parameters = extra_float_digits
EOF
sudo tee "/etc/pgbouncer/userlist.txt" >/dev/null <<EOF
"$DB_USER" "md5$PG_MD5"
EOF
sudo chown postgres:postgres /etc/pgbouncer/userlist.txt && sudo chmod 600 /etc/pgbouncer/userlist.txt
sudo systemctl enable pgbouncer && sudo systemctl restart pgbouncer

curl -fsSL https://deb.nodesource.com/setup_$NODE_VERSION.x | sudo -E bash -
sudo apt install -y nodejs
sudo npm install -g pnpm pm2

sudo -u postgres psql -c "CREATE ROLE $DB_USER LOGIN PASSWORD '$DB_PASSWORD';" || true
sudo -u postgres psql -c "CREATE DATABASE $DB_NAME OWNER $DB_USER;" || true

sudo rm -rf "$APP_DIR"
sudo mkdir -p "$APP_DIR"
sudo chown -R "$USER:$USER" "$APP_DIR"
git clone -b "$GIT_BRANCH" "$GIT_REPO" "$APP_DIR"
cd "$APP_DIR"

cat > ".env" <<EOF
DATABASE_URL="postgresql://$DB_USER:$DB_PASSWORD@127.0.0.1:6432/$DB_NAME"
REDIS_URL="redis://localhost:6379"
APP_URL="$APP_URL"
NEXT_PUBLIC_APP_URL="$APP_URL"
NEXTAUTH_URL="$APP_URL"
NEXTAUTH_SECRET="$(openssl rand -base64 32)"
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

pnpm install && pnpm prisma generate
pnpm prisma migrate deploy || pnpm prisma db push
pnpm build

pm2 delete "$APP_NAME" || true
pm2 start pnpm --name "$APP_NAME" -i max --max-memory-restart $((MEM_TOTAL / CPU_CORES / 2))M -- start -- -p $APP_PORT -H 0.0.0.0
pm2 save
[[ "$IS_WSL" = false ]] && pm2 startup systemd -u "$USER" --hp "$HOME" | tail -n 1 | bash

sudo rm -f /etc/nginx/sites-enabled/default
sudo tee "/etc/nginx/sites-available/$APP_NAME" >/dev/null <<EOF
proxy_cache_path /var/cache/nginx levels=1:2 keys_zone=NEXT_CACHE:20m max_size=2g inactive=120m use_temp_path=off;
server {
    listen 80;
    server_name _;
    gzip on;
    gzip_proxied any;
    gzip_comp_level 4;
    gzip_types text/plain text/css application/json application/javascript text/xml application/xml;

    location /_next/static/ {
        alias $APP_DIR/.next/static/;
        expires 365d;
        access_log off;
    }

    location / {
        proxy_pass http://127.0.0.1:$APP_PORT;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host \$host;
        proxy_cache NEXT_CACHE;
        proxy_cache_valid 200 60m;
        proxy_cache_use_stale error timeout updating http_500 http_502 http_503 http_504;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
EOF
sudo ln -sf "/etc/nginx/sites-available/$APP_NAME" /etc/nginx/sites-enabled/
sudo nginx -t && sudo systemctl reload nginx

echo "--------------------------------------"
echo "[DONE]: Install completed: $APP_URL"
echo "--------------------------------------"