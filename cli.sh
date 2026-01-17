#!/bin/bash
set -e

BASE_DIR="/opt/zentracore-installer"

usage() {
    echo "Usage: zentracore {install|restart|update|ssl|remove-ssl|uninstall|backup|restore} [args]"
}

case "$1" in
    install)    bash "$BASE_DIR/modules/app/install.sh" "$2" ;;
    restart)    bash "$BASE_DIR/modules/app/restart.sh";;
    update)     bash "$BASE_DIR/modules/app/update.sh" "$2" ;;
    uninstall)  bash "$BASE_DIR/modules/app/uninstall.sh" ;;
    ssl)        bash "$BASE_DIR/modules/ssl/install.sh" "$2" ;;
    remove-ssl) bash "$BASE_DIR/modules/ssl/remove.sh" "$2" ;;
    backup)     bash "$BASE_DIR/modules/backup/backup.sh";;
    restore)    bash "$BASE_DIR/modules/backup/restore.sh" "$2";;
    *)          usage ;;
esac