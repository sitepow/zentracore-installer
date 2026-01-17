#!/bin/bash
set -e

BASE_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
source "$BASE_DIR/config/env.sh"
BRANCH="${1:-$DEFAULT_BRANCH}"

cd "$APP_DIR"

git fetch origin
git checkout "$BRANCH"
git pull origin "$BRANCH"

pnpm install --frozen-lockfile || pnpm install
pnpm prisma generate
pnpm build

pm2 reload "$APP_NAME" || pm2 start pnpm --name "$APP_NAME" --interpreter none -- start -- -i max
pm2 save

echo "--------------------------------------"
echo "[DONE]: Update completed!"
echo "--------------------------------------"