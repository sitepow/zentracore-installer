#!/bin/bash
set -e

BASE_DIR="$(cd "$(dirname "$0")" && pwd)"

APP_INSTALL="$BASE_DIR/modules/app/install.sh"
APP_UPDATE="$BASE_DIR/modules/app/update.sh"
APP_UNINSTALL="$BASE_DIR/modules/app/uninstall.sh"

SSL_INSTALL="$BASE_DIR/modules/ssl/install.sh"
SSL_REMOVE="$BASE_DIR/modules/ssl/remove.sh"

usage() {
  echo "Usage:"
  echo "  ./cli.sh install [branch]"
  echo "  ./cli.sh update [branch]"
  echo "  ./cli.sh ssl domain.com"
  echo "  ./cli.sh remove-ssl domain.com"
  echo "  ./cli.sh uninstall"
}

case "$1" in
  install)    bash "$APP_INSTALL" "$2" ;;
  update)     bash "$APP_UPDATE" "$2" ;;
  uninstall)  bash "$APP_UNINSTALL" ;;
  ssl)        bash "$SSL_INSTALL" "$2" ;;
  remove-ssl) bash "$SSL_REMOVE" "$2" ;;
  *) usage ;;
esac
