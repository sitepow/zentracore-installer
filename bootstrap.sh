#!/bin/bash
set -e

INSTALL_DIR="/opt/zentracore-installer"
REPO="https://github.com/sitepow/zentracore-installer.git"

sudo rm -rf "$INSTALL_DIR"
sudo rm -f /usr/local/bin/zentracore

sudo apt update && sudo apt install -y git curl

sudo git clone "$REPO" "$INSTALL_DIR"
sudo chmod +x "$INSTALL_DIR/cli.sh"
sudo ln -sf "$INSTALL_DIR/cli.sh" /usr/local/bin/zentracore

echo "--------------------------------------"
echo "[DONE]: ZentraCore CLI updated!"
echo "Run command 'zentracore' to start."
echo "--------------------------------------"
