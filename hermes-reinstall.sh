#!/usr/bin/env bash
# hermes-reinstall.sh — Clean uninstall + fresh install of Hermes daemon
#
# Usage:
#   ./hermes-reinstall.sh              # Full reinstall (removes config + volumes)
#   ./hermes-reinstall.sh --keep-data  # Reinstall but preserve workspace data
set -euo pipefail

DAEMON_DIR="${HERMES_DAEMON_DIR:-$HOME/.hermes-daemon}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_SCRIPT="$SCRIPT_DIR/hermes-install.sh"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info()  { echo -e "${GREEN}[INFO]${NC} $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }

KEEP_DATA=false
[[ "${1:-}" == "--keep-data" ]] && KEEP_DATA=true

# --- Step 1: Stop existing containers ---
info "Stopping existing daemon..."
if docker compose version >/dev/null 2>&1; then
    COMPOSE_CMD="docker compose"
elif command -v docker-compose >/dev/null 2>&1; then
    COMPOSE_CMD="docker-compose"
else
    COMPOSE_CMD=""
fi

if [[ -n "$COMPOSE_CMD" && -f "$DAEMON_DIR/docker-compose.yml" ]]; then
    cd "$DAEMON_DIR"
    if $KEEP_DATA; then
        $COMPOSE_CMD down 2>/dev/null || true
    else
        $COMPOSE_CMD down -v 2>/dev/null || true
    fi
fi

# --- Step 2: Remove old containers by name pattern ---
info "Removing old containers..."
docker rm -f $(docker ps -aq --filter "name=hermes-daemon") 2>/dev/null || true
docker rm -f $(docker ps -aq --filter "name=hermes-watchtower") 2>/dev/null || true

# --- Step 3: Remove old images ---
info "Removing cached images..."
docker rmi $(docker images "ghcr.io/jgyoo/hermes-daemon" -q) 2>/dev/null || true

# --- Step 4: Remove config files ---
if $KEEP_DATA; then
    info "Keeping workspace data, removing config only..."
    rm -f "$DAEMON_DIR/docker-compose.yml"
    # Preserve .env.daemon so user doesn't have to re-enter settings
else
    info "Removing all config and data..."
    rm -f "$DAEMON_DIR/docker-compose.yml"
    rm -f "$DAEMON_DIR/.env.daemon"
fi

# --- Step 5: Re-run install ---
info "Running fresh install..."
if [[ -x "$INSTALL_SCRIPT" ]]; then
    exec "$INSTALL_SCRIPT"
else
    chmod +x "$INSTALL_SCRIPT"
    exec "$INSTALL_SCRIPT"
fi
