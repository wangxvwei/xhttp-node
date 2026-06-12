#!/usr/bin/env bash

set -Eeuo pipefail

APP_NAME="xhttp-node"
INSTALL_DIR="/usr/local/xhttp-node"
SCRIPT_URL="${SCRIPT_URL:-https://raw.githubusercontent.com/wangxvwei/xhttp-node/main/xhttp-node.sh}"

need_root() {
  if [ "$(id -u)" -ne 0 ]; then
    echo "Please run as root."
    exit 1
  fi
}

need_command() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "Missing command: $1"
    exit 1
  }
}

need_root
need_command curl

mkdir -p "$INSTALL_DIR"
curl -fsSL "$SCRIPT_URL" -o "${INSTALL_DIR}/${APP_NAME}.sh"
chmod +x "${INSTALL_DIR}/${APP_NAME}.sh"
ln -sf "${INSTALL_DIR}/${APP_NAME}.sh" "/usr/local/bin/${APP_NAME}"

echo "Installed: /usr/local/bin/${APP_NAME}"
echo "Starting ${APP_NAME}..."
exec "${APP_NAME}"
