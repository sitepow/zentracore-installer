#!/bin/bash
set -e

INSTALL_DIR="/opt/zentracore-installer"
REPO="https://github.com/sitepow/zentracore-installer.git"

sudo apt update
sudo apt install -y git curl

if [ ! -d "$INSTALL_DIR/.git" ]; then
  sudo git clone "$REPO" "$INSTALL_DIR"
fi

sudo ln -sf "$INSTALL_DIR/cli.sh" /usr/local/bin/zentracore
sudo chmod +x /usr/local/bin/zentracore

echo "ZentraCore installed"
echo "Run: zentracore"
