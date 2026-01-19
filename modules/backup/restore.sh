#!/bin/bash
set -e

BASE_DIR="/opt/zentracore-installer"
APP_DIR="/var/www/zentracore"
UPLOADS_DIR="$APP_DIR/public/uploads"
BACKUP_DIR="/var/backups/zentracore"

source "$BASE_DIR/config/env.sh"

mapfile -t FILES < <(ls -1t "$BACKUP_DIR"/*.dump 2>/dev/null || true)

if [ "${#FILES[@]}" -eq 0 ]; then
  echo "no backup files found"
  exit 1
fi

if [ -z "$1" ]; then
  echo "Available backups:"
  echo

  i=1
  for f in "${FILES[@]}"; do
    name=$(basename "$f")
    date=$(stat -c '%y' "$f" | cut -d'.' -f1)
    size=$(du -h "$f" | cut -f1)
    printf "%2d) %-40s %s %s\n" "$i" "$name" "$date" "$size"
    i=$((i+1))
  done

  echo
  read -p "Select backup number: " CHOICE
else
  CHOICE="$1"
fi

if ! [[ "$CHOICE" =~ ^[0-9]+$ ]] || [ "$CHOICE" -lt 1 ] || [ "$CHOICE" -gt "${#FILES[@]}" ]; then
  echo "invalid selection"
  exit 1
fi

FILE="${FILES[$((CHOICE-1))]}"
BASENAME=$(basename "$FILE")

TIMESTAMP=$(echo "$BASENAME" | sed -E 's/.*_([0-9]{8}_[0-9]{6})\.dump/\1/')

UPLOADS_ARCHIVE="$BACKUP_DIR/uploads_${TIMESTAMP}.tar.gz"
ENV_FILE="$BACKUP_DIR/env_${TIMESTAMP}.sh"

echo "--------------------------------------"
echo " Restoring backup: $BASENAME"
echo " Timestamp: $TIMESTAMP"
echo "--------------------------------------"

echo "• Restoring database..."

PGPASSWORD="$DB_PASSWORD" psql \
  -h 127.0.0.1 \
  -p "$DB_PORT" \
  -U "$DB_USER" \
  -d postgres \
  -c "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname='$DB_NAME';"

PGPASSWORD="$DB_PASSWORD" psql \
  -h 127.0.0.1 \
  -p "$DB_PORT" \
  -U "$DB_USER" \
  -d postgres \
  -c "DROP DATABASE IF EXISTS $DB_NAME;"

PGPASSWORD="$DB_PASSWORD" psql \
  -h 127.0.0.1 \
  -p "$DB_PORT" \
  -U "$DB_USER" \
  -d postgres \
  -c "CREATE DATABASE $DB_NAME OWNER $DB_USER;"

PGPASSWORD="$DB_PASSWORD" pg_restore \
  -h 127.0.0.1 \
  -p "$DB_PORT" \
  -U "$DB_USER" \
  -d "$DB_NAME" \
  "$FILE"

if [ -f "$UPLOADS_ARCHIVE" ]; then
  echo "• Restoring uploads..."

  mkdir -p "$UPLOADS_DIR"
  rm -rf "$UPLOADS_DIR"/*
  tar -xzf "$UPLOADS_ARCHIVE" -C "$UPLOADS_DIR"

  chown -R www-data:www-data "$UPLOADS_DIR" || true
else
  echo "• No uploads archive found, skipping"
fi

if [ -f "$ENV_FILE" ]; then
  echo "• Env backup available: $ENV_FILE (not auto-applied)"
fi

echo "--------------------------------------"
echo " [DONE]: Restore completed!"
echo "--------------------------------------"
