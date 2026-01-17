#!/bin/bash
set -e

BASE_DIR="/opt/zentracore-installer"

usage() {
cat <<EOF

ZentraCore CLI
Usage:
  zentracore <command> [options]

Commands:
  install <git-branch>       Install ZentraCore application
  update <domain>        Update application
  restart                Restart all services
  uninstall              Remove ZentraCore completely

  ssl <domain>           Install SSL (Let's Encrypt)
  remove-ssl <domain>    Remove SSL

  backup                 Create backup
  restore <file>         Restore from backup file

Examples:
  zentracore install
  zentracore ssl example.com
  zentracore backup
  zentracore restore backup-2026-01-16.tar.gz

EOF
exit 1
}

require_arg() {
  if [ -z "$2" ]; then
    echo "Missing required argument"
    usage
  fi
}

case "$1" in
    ""|help|-h|--help) usage ;;
    install)    require_arg "$@"; bash "$BASE_DIR/modules/app/install.sh" "$2" ;;
    restart)    bash "$BASE_DIR/modules/app/restart.sh" ;;
    update)     require_arg "$@"; bash "$BASE_DIR/modules/app/update.sh" "$2" ;;
    uninstall)  bash "$BASE_DIR/modules/app/uninstall.sh" ;;
    ssl)        require_arg "$@"; bash "$BASE_DIR/modules/ssl/install.sh" "$2" ;;
    remove-ssl) require_arg "$@"; bash "$BASE_DIR/modules/ssl/remove.sh" "$2" ;;
    backup)     bash "$BASE_DIR/modules/backup/backup.sh" ;;
    # restore)    require_arg "$@"; bash "$BASE_DIR/modules/backup/restore.sh" "$2" ;;
    restore)    bash "$BASE_DIR/modules/backup/restore.sh" "${@:2}";;
    *)          echo "❌ Unknown command: $1"; usage ;;
esac
