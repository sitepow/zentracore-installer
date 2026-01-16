#!/bin/bash
set -e

INSTALL_DIR="/opt/zentracore-installer"
REPO="https://github.com/sitepow/zentracore-installer.git"

echo "------- ZentraCore CLI Force Update -------"

echo "Cleaning old installation..."
sudo rm -rf "$INSTALL_DIR"
sudo rm -f /usr/local/bin/zentracore

sudo apt update
sudo apt install -y git curl

echo "Cloning repository..."
sudo git clone "$REPO" "$INSTALL_DIR"

sudo chmod +x "$INSTALL_DIR/cli.sh"

sudo ln -sf "$INSTALL_DIR/cli.sh" /usr/local/bin/zentracore

echo "------------------------------------------"
echo "ZentraCore CLI installed successfully"
echo "Path: /usr/local/bin/zentracore"
echo "Run: zentracore"
