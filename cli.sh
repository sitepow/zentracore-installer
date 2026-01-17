#!/bin/bash
set -e

BASE_DIR="/opt/zentracore-installer"

usage() {
    echo "Usage: zentracore {install|update|ssl|remove-ssl|uninstall} [args]"
}

case "$1" in
    install)    bash "$BASE_DIR/modules/app/install.sh" "$2" ;;
    update)     bash "$BASE_DIR/modules/app/update.sh" "$2" ;;
    uninstall)  bash "$BASE_DIR/modules/app/uninstall.sh" ;;
    ssl)        bash "$BASE_DIR/modules/ssl/install.sh" "$2" ;;
    remove-ssl) bash "$BASE_DIR/modules/ssl/remove.sh" "$2" ;;
    *)          usage ;;
esac