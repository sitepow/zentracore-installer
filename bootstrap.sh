#!/bin/bash
set -e

BASE_DIR="/opt/zentracore-installer"
REPO="https://github.com/sitepow/zentracore-installer.git"

echo "Installing ZentraCore CLI..."

sudo mkdir -p /opt
sudo rm -rf "$BASE_DIR"
sudo git clone "$REPO" "$BASE_DIR"

sudo ln -sf "$BASE_DIR/cli.sh" /usr/local/bin/zentracore
sudo chmod +x "$BASE_DIR/cli.sh"

echo "Done."
echo "Run: zentracore"
