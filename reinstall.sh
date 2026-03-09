#!/usr/bin/env bash
# reinstall.sh — One-command clean reinstall of Hermes daemon
# Usage: curl -fsSL https://raw.githubusercontent.com/jgyoo/hermes_demon_test_repo/main/reinstall.sh | bash
set -euo pipefail

DAEMON_DIR="$HOME/.hermes-daemon"
SERVICE_NAME="hermes-daemon"

echo "[1/4] Stopping existing daemon..."
if systemctl --user is-active "$SERVICE_NAME" >/dev/null 2>&1; then
    systemctl --user stop "$SERVICE_NAME"
    systemctl --user disable "$SERVICE_NAME" 2>/dev/null || true
    rm -f "$HOME/.config/systemd/user/${SERVICE_NAME}.service"
    systemctl --user daemon-reload
fi

# Stop docker compose if running
if [ -f "$DAEMON_DIR/docker-compose.yml" ]; then
    cd "$DAEMON_DIR"
    if command -v docker-compose >/dev/null 2>&1; then
        docker-compose down -v 2>/dev/null || true
    elif docker compose version >/dev/null 2>&1; then
        docker compose down -v 2>/dev/null || true
    fi
fi

echo "[2/4] Removing old installation..."
rm -rf "$DAEMON_DIR"

echo "[3/4] Downloading latest daemon-setup.sh..."
mkdir -p "$DAEMON_DIR"
curl -fsSL https://raw.githubusercontent.com/jgyoo/hermes_demon_test_repo/main/daemon-setup.sh \
    -o "$DAEMON_DIR/daemon-setup.sh"
chmod +x "$DAEMON_DIR/daemon-setup.sh"

echo "[4/4] Installing daemon..."
"$DAEMON_DIR/daemon-setup.sh"
