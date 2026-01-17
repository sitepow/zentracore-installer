#!/bin/bash
set -e

command -v pm2 >/dev/null 2>&1 || exit 1
pm2 resurrect
