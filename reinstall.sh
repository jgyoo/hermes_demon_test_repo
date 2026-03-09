#!/usr/bin/env bash
# reinstall.sh — One-command clean reinstall of Hermes daemon
# Usage: curl -fsSL https://raw.githubusercontent.com/jgyoo/hermes_demon_test_repo/main/reinstall.sh | bash
set -euo pipefail

DAEMON_DIR="$HOME/.hermes-daemon"
SERVICE_NAME="hermes-daemon"

echo "[1/4] Stopping existing daemon..."
systemctl --user stop "$SERVICE_NAME" 2>/dev/null || true
systemctl --user disable "$SERVICE_NAME" 2>/dev/null || true
rm -f "$HOME/.config/systemd/user/${SERVICE_NAME}.service"
systemctl --user daemon-reload 2>/dev/null || true

# Force-kill container if running
docker rm -f "hermes-daemon-$(hostname)" 2>/dev/null || true
docker rm -f hermes-daemon-default 2>/dev/null || true

echo "[2/4] Removing old installation..."
rm -rf "$DAEMON_DIR"

echo "[3/4] Downloading latest daemon-setup.sh..."
mkdir -p "$DAEMON_DIR"
curl -fsSL https://raw.githubusercontent.com/jgyoo/hermes_demon_test_repo/main/daemon-setup.sh \
    -o "$DAEMON_DIR/daemon-setup.sh"
chmod +x "$DAEMON_DIR/daemon-setup.sh"

echo "[4/4] Installing daemon..."
"$DAEMON_DIR/daemon-setup.sh"
