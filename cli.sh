#!/bin/bash
set -e

BASE_URL="https://raw.githubusercontent.com/you/zentracore-installer/main"

download() {
  curl -fsSL "$BASE_URL/$1" -o "/tmp/$1"
  chmod +x "/tmp/$1"
}

echo "--------------------------------------"
echo "ZentraCore CLI"
echo "--------------------------------------"
echo "1) Install application"
echo "2) Update application"
echo "3) Install SSL"
echo "4) Remove SSL"
echo "5) Uninstall everything"
echo "--------------------------------------"

read -p "Select option: " CHOICE

case "$CHOICE" in
  1)
    download install.sh
    /tmp/install.sh
    ;;
  2)
    download update.sh
    /tmp/update.sh
    ;;
  3)
    read -p "Domain: " DOMAIN
    download install-ssl.sh
    /tmp/install-ssl.sh "$DOMAIN"
    ;;
  4)
    read -p "Domain: " DOMAIN
    download remove-ssl.sh
    /tmp/remove-ssl.sh "$DOMAIN"
    ;;
  5)
    download uninstall.sh
    /tmp/uninstall.sh
    ;;
  *)
    echo "Invalid option"
    exit 1
esac
