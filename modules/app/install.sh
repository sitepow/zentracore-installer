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
  postgresql postgresql-contrib pgbouncer

if [ "$IS_WSL" = false ]; then
  sudo apt install -y ufw fail2ban
  sudo timedatectl set-timezone "$TIMEZONE"
fi

sudo systemctl enable postgresql
sudo systemctl start postgresql

echo "Tuning PostgreSQL for Web App..."

PG_VERSION=$(psql -V | awk '{print $3}' | cut -d. -f1)
PG_CONF="/etc/postgresql/$PG_VERSION/main/postgresql.conf"
PG_HBA="/etc/postgresql/$PG_VERSION/main/pg_hba.conf"

if [ "$IS_WSL" = false ]; then
sudo sed -i "s/^#listen_addresses.*/listen_addresses = 'localhost'/" "$PG_CONF"
sudo tee -a "$PG_CONF" >/dev/null <<'EOF'

shared_buffers = 2GB
effective_cache_size = 6GB
work_mem = 16MB
maintenance_work_mem = 512MB
max_connections = 30
wal_buffers = 16MB
min_wal_size = 1GB
max_wal_size = 4GB
checkpoint_completion_target = 0.9
synchronous_commit = off
random_page_cost = 1.1
effective_io_concurrency = 200
log_min_duration_statement = 500ms
EOF

  if [ "$DB_REMOTE_ACCESS" = "true" ]; then
    echo "Config pg_hba.conf"
    sudo tee -a "$PG_HBA" >/dev/null <<EOF

# ZentraCore Remote DB Access
host    $DB_NAME    $DB_USER    $DB_ALLOWED_CIDR    md5
EOF
  fi

  sudo systemctl restart postgresql
else
  echo "⚠️ Skip PostgreSQL tuning on WSL"
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

echo "Configuring PgBouncer..."

PGBOUNCER_INI="/etc/pgbouncer/pgbouncer.ini"
PGBOUNCER_USERLIST="/etc/pgbouncer/userlist.txt"

sudo tee "$PGBOUNCER_INI" >/dev/null <<EOF
[databases]
$DB_NAME = host=127.0.0.1 port=5432 dbname=$DB_NAME user=$DB_USER password=$DB_PASSWORD

[pgbouncer]
listen_addr = 127.0.0.1
listen_port = 6432
auth_type = md5
auth_file = $PGBOUNCER_USERLIST
pool_mode = transaction

max_client_conn = 1000
default_pool_size = 20
reserve_pool_size = 5
ignore_startup_parameters = extra_float_digits
EOF

echo "Setting PgBouncer auth..."

PG_MD5=$(echo -n "$DB_PASSWORD$DB_USER" | md5sum | awk '{print $1}')

sudo tee "$PGBOUNCER_USERLIST" >/dev/null <<EOF
"$DB_USER" "md5$PG_MD5"
EOF

sudo chown postgres:postgres "$PGBOUNCER_USERLIST"
sudo chmod 600 "$PGBOUNCER_USERLIST"

sudo systemctl enable pgbouncer
sudo systemctl restart pgbouncer

sudo rm -rf "$APP_DIR"
sudo mkdir -p "$APP_DIR"
sudo chown -R "$USER:$USER" "$APP_DIR"

git clone -b "$GIT_BRANCH" "$GIT_REPO" "$APP_DIR"

ENV_FILE="$APP_DIR/.env"

if [ ! -f "$ENV_FILE" ]; then
  echo "Creating .env file..."
 cat > "$ENV_FILE" <<EOF
DATABASE_URL="postgresql://$DB_USER:$DB_PASSWORD@127.0.0.1:6432/$DB_NAME"
APP_URL="$APP_URL"
NEXT_PUBLIC_APP_URL="$APP_URL"
NEXTAUTH_URL="$APP_URL"
AUTH_SECRET="$(openssl rand -base64 32)"
GOOGLE_CLIENT_ID="dummy-google-client-id"
GOOGLE_CLIENT_SECRET="dummy-google-client-secret"
FACEBOOK_CLIENT_ID="dummy-facebook-client-id"
FACEBOOK_CLIENT_SECRET="dummy-facebook-client-secret"
STRIPE_SECRET_KEY="sk_test_dummykey1234567890"
STRIPE_WEBHOOK_SECRET="whsec_dummywebhooksecret"
OMISE_SECRET_KEY="pkey_test_dummy"
NEXT_PUBLIC_OMISE_PUBLIC_KEY="pkey_test_dummy_public"
SUPABASE_URL="https://dummy.supabase.co"
SUPABASE_SERVICE_ROLE_KEY="dummy-service-role-key"
NEXT_PUBLIC_SUPABASE_URL="https://dummy.supabase.co"
NEXT_PUBLIC_SUPABASE_ANON_KEY="dummy-anon-key"
EOF
fi

cd "$APP_DIR"

pnpm install
pnpm prisma generate
pnpm prisma migrate deploy || pnpm prisma db push
pnpm build

pm2 start pnpm \
  --name "$APP_NAME" \
  -- start \
  -i max \
  --max-memory-restart 512M

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
    proxy_http_version 1.1;
    proxy_set_header X-Forwarded-For \$remote_addr;
    proxy_set_header X-Forwarded-Proto \$scheme;
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
