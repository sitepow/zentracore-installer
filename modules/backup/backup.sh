#!/bin/bash
set -e

BASE_DIR="/opt/zentracore-installer"
APP_DIR="/var/www/zentracore"
UPLOADS_DIR="$APP_DIR/public/uploads"
BACKUP_DIR="/var/backups/zentracore"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")

source "$BASE_DIR/config/env.sh"

mkdir -p "$BACKUP_DIR"

echo "• Backing up database..."
PGPASSWORD="$DB_PASSWORD" pg_dump \
  -h 127.0.0.1 \
  -p "$DB_PORT" \
  -U "$DB_USER" \
  -F c \
  -f "$BACKUP_DIR/${DB_NAME}_${TIMESTAMP}.dump" \
  "$DB_NAME"

echo "• Backing up env config..."
cp "$BASE_DIR/config/env.sh" \
   "$BACKUP_DIR/env_${TIMESTAMP}.sh"

if [ -d "$UPLOADS_DIR" ]; then
  echo "• Backing up uploads..."
  tar -czf \
    "$BACKUP_DIR/uploads_${TIMESTAMP}.tar.gz" \
    -C "$UPLOADS_DIR" .
else
  echo "• uploads directory not found, skipping"
fi

echo ""
echo "Latest backups:"
ls -lh "$BACKUP_DIR" | tail -n 5

echo "--------------------------------------"
echo " [DONE]: Backup completed!"
echo " Location: $BACKUP_DIR"
echo "--------------------------------------"
