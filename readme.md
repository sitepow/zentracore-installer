# Zentracore Installer

Automation shell script for provisioning and managing VPS environments  
Designed for fast, repeatable, and secure server setup.

## Features

- One-command VPS bootstrap
- Modular installation system
- SSL automation
- Backup & restore utilities
- Designed for production usage

## Project Structure

````text
zentracore-installer/
├─ config/        # Environment configuration
├─ modules/       # Feature-based installation modules
│  ├─ app/        # Application setup & update
│  ├─ backup/     # Backup & restore utilities
│  └─ ssl/        # SSL installation & removal
├─ scripts/       # Shared helper functions
├─ bootstrap.sh   # Entry point
├─ cli.sh         # CLI interface
└─ README.md

## Quick Install & Quick Update (CLI)

```sh
curl -fsSL https://raw.githubusercontent.com/sitepow/zentracore-installer/main/bootstrap.sh | bash
````
