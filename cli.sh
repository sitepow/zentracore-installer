#!/bin/bash
set -e

REPO_URL="https://raw.githubusercontent.com/sitepow/zentracore-installer"

download_and_run() {
  local path="$1"
  shift
  bash <(curl -fsSL "$REPO_URL/$BRANCH/$path") "$@"
}

usage() {
  echo "ZentraCore CLI"
  echo ""
  echo "Usage:"
  echo "  zentracore install [branch]"
  echo "  zentracore update [branch]"
  echo "  zentracore ssl domain.com"
  echo "  zentracore remove-ssl domain.com"
  echo "  zentracore uninstall"
}

case "$1" in
  install)
    BRANCH="${2:-main}"
    download_and_run modules/app/install.sh
    ;;

  update)
    BRANCH="${2:-main}"
    download_and_run modules/app/update.sh
    ;;

  uninstall)
    BRANCH="main"
    download_and_run modules/app/uninstall.sh
    ;;

  ssl)
    if [ -z "$2" ]; then
      echo "Domain required"
      exit 1
    fi
    BRANCH="main"
    download_and_run modules/ssl/install.sh "$2"
    ;;

  remove-ssl)
    if [ -z "$2" ]; then
      echo "Domain required"
      exit 1
    fi
    BRANCH="main"
    download_and_run modules/ssl/remove.sh "$2"
    ;;

  *)
    usage
    ;;
esac
