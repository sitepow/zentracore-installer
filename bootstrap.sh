#!/bin/bash
set -e

BIN_PATH="/usr/local/bin/zentracore"
CLI_URL="https://raw.githubusercontent.com/sitepow/zentracore-installer/main/cli.sh"

echo "Installing ZentraCore CLI..."

sudo curl -fsSL "$CLI_URL" -o "$BIN_PATH"
sudo chmod +x "$BIN_PATH"

echo "Done."
echo ""
echo "Run: zentracore"
