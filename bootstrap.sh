#!/bin/bash
set -e

INSTALL_DIR="/opt/zentracore-installer"
REPO="https://github.com/sitepow/zentracore-installer.git"

echo "------- ZentraCore CLI Force Update -------"

if [ -d "$INSTALL_DIR" ]; then
  echo "Removing old installer..."
  sudo rm -rf "$INSTALL_DIR"
fi

if [ -e "/usr/local/bin/zentracore" ]; then
  echo "Removing old CLI link..."
  sudo rm -f /usr/local/bin/zentracore
fi

sudo apt update
sudo apt install -y git curl

echo "Cloning repository..."
sudo git clone "$REPO" "$INSTALL_DIR"

sudo ln -s "$INSTALL_DIR/cli.sh" /usr/local/bin/zentracore
sudo chmod +x "$INSTALL_DIR/cli.sh"

echo "--------------------------------"
echo "ZentraCore CLI updated successfully"
echo "Run: zentracore"
