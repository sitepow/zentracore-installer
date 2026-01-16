#!/bin/bash
set -e

APP_NAME="zentracore"
APP_DIR="/var/www/zentracore"

DEFAULT_BRANCH="main"

BRANCH=${1:-$DEFAULT_BRANCH}

if [ ! -d "$APP_DIR/.git" ]; then
  echo "Application not installed at $APP_DIR"
  exit 1
fi

if ! command -v pnpm >/dev/null; then
  echo "pnpm not found"
  exit 1
fi

if ! command -v pm2 >/dev/null; then
  echo "pm2 not found"
  exit 1
fi

echo "--------------------------------------"
echo " ZentraCore Update"
echo " Branch: $BRANCH"
echo "--------------------------------------"

cd $APP_DIR

echo "[1/4] Git fetch & pull"
git fetch origin
git checkout $BRANCH
git pull origin $BRANCH

echo "[2/4] Install dependencies"
pnpm install --frozen-lockfile || pnpm install

echo "[3/4] Build application"
pnpm build

echo "[4/4] Reload PM2"
pm2 reload "$APP_NAME" || pm2 start pnpm --name "$APP_NAME" -- start
pm2 save

echo ""
echo "--------------------------------------"
echo "Update completed successfully"
echo "--------------------------------------"
