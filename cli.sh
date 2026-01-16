#!/bin/bash
set -e

BASE_DIR="/opt/zentracore-installer"

APP_INSTALL="$BASE_DIR/modules/app/install.sh"
APP_UPDATE="$BASE_DIR/modules/app/update.sh"
APP_UNINSTALL="$BASE_DIR/modules/app/uninstall.sh"

SSL_INSTALL="$BASE_DIR/modules/ssl/install.sh"
SSL_REMOVE="$BASE_DIR/modules/ssl/remove.sh"

usage() {
  echo "ZentraCore CLI"
  echo "Usage:"
  echo "  zentracore install [branch]"
  echo "  zentracore update [branch]"
  echo "  zentracore ssl domain.com"
  echo "  zentracore remove-ssl domain.com"
  echo "  zentracore uninstall"
}

case "$1" in
  install)    bash "$APP_INSTALL" "$2" ;;
  update)     bash "$APP_UPDATE" "$2" ;;
  uninstall)  bash "$APP_UNINSTALL" ;;
  ssl)        bash "$SSL_INSTALL" "$2" ;;
  remove-ssl) bash "$SSL_REMOVE" "$2" ;;
  *) usage ;;
esac
