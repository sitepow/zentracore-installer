#!/bin/bash
set -e

BASE_DIR="/opt/zentracore-installer"
BACKUP_DIR="/var/backups/zentracore"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")

source "$BASE_DIR/config/env.sh"

mkdir -p "$BACKUP_DIR"

PGPASSWORD="$DB_PASSWORD" pg_dump \
  -h 127.0.0.1 \
  -p "$DB_PORT" \
  -U "$DB_USER" \
  -F c \
  -f "$BACKUP_DIR/${DB_NAME}_${TIMESTAMP}.dump" \
  "$DB_NAME"

cp "$BASE_DIR/config/env.sh" \
   "$BACKUP_DIR/env_${TIMESTAMP}.sh"

ls -1t "$BACKUP_DIR" | head -n 5

echo "--------------------------------------"
echo " [DONE]: Backup completed!"
echo "--------------------------------------"