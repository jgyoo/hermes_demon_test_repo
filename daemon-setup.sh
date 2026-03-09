#!/usr/bin/env bash
# daemon-setup.sh — Hermes daemon one-command setup (Linux/macOS)
#
# This script is self-contained. No source code clone needed.
# Just download this file to a daemon PC and run it.
#
# Usage:
#   ./daemon-setup.sh                # Setup + install as background service
#   ./daemon-setup.sh run            # Foreground mode (for debugging)
#   ./daemon-setup.sh stop           # Stop daemon
#   ./daemon-setup.sh update v0.2.0  # Pull specific version + restart
#   ./daemon-setup.sh logs           # Tail daemon logs
#   ./daemon-setup.sh status         # Show daemon status
#   ./daemon-setup.sh uninstall      # Remove background service
set -euo pipefail

REGISTRY="${HERMES_REGISTRY:-ghcr.io/jgyoo}"
IMAGE="${REGISTRY}/hermes-daemon"
VERSION="${HERMES_VERSION:-v0.1.6}"
DAEMON_DIR="${HERMES_DAEMON_DIR:-$HOME/.hermes-daemon}"
SERVICE_NAME="hermes-daemon"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info()  { echo -e "${GREEN}[INFO]${NC} $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }

detect_compose() {
    if command -v docker-compose >/dev/null 2>&1; then
        COMPOSE_CMD="docker-compose"
    elif docker compose version >/dev/null 2>&1; then
        COMPOSE_CMD="docker compose"
    else
        error "docker-compose not found"
        exit 1
    fi
}

check_prerequisites() {
    command -v docker >/dev/null 2>&1 || { error "docker not found"; exit 1; }
    detect_compose
}

check_auth() {
    local creds="$HOME/.claude/.credentials.json"
    if [[ ! -f "$creds" ]]; then
        error "Claude credentials not found at $creds"
        echo "  Run 'claude login' on this machine first."
        exit 1
    fi
    if [[ ! -s "$creds" ]]; then
        error "Claude credentials file is empty."
        echo "  Run 'claude login' to re-authenticate."
        exit 1
    fi
    info "Claude credentials verified"
}

generate_compose_file() {
    local agent_name tag
    agent_name=$(grep HERMES_AGENT_AGENT_NAME "$DAEMON_DIR/.env.daemon" | cut -d= -f2)
    tag=$(grep HERMES_IMAGE_TAG "$DAEMON_DIR/.env.daemon" | cut -d= -f2 || echo "$VERSION")

    cat > "$DAEMON_DIR/docker-compose.yml" <<YAML
services:
  hermes-daemon:
    image: ${IMAGE}:${tag}
    container_name: hermes-daemon-${agent_name}
    env_file:
      - .env.daemon
    volumes:
      - daemon-workspace:/home/hermes/hermes-workspace
      - \${CLAUDE_CONFIG_DIR:-~/.claude}:/home/hermes/.claude:ro
    stop_grace_period: 120s
    restart: unless-stopped

volumes:
  daemon-workspace:
YAML
}

ensure_setup() {
    if [[ -f "$DAEMON_DIR/.env.daemon" && -f "$DAEMON_DIR/docker-compose.yml" ]]; then
        return 0
    fi

    info "=== Hermes Daemon Setup ==="
    mkdir -p "$DAEMON_DIR"

    check_auth

    local daemon_name orch_url image_tag
    daemon_name=$(hostname)
    orch_url="ws://192.168.11.23:8003/ws/nodes"
    image_tag="$VERSION"

    info "Daemon name: ${daemon_name}"
    info "Orchestrator: ${orch_url}"
    info "Image version: ${image_tag}"

    cat > "$DAEMON_DIR/.env.daemon" <<EOF
HERMES_AGENT_AGENT_NAME=${daemon_name}
HERMES_AGENT_ORCHESTRATOR_URL=${orch_url}
HERMES_IMAGE_TAG=${image_tag}
CLAUDE_CONFIG_DIR=${HOME}/.claude
EOF

    generate_compose_file
    info "Configuration saved to $DAEMON_DIR/"
}

cmd_start() {
    check_prerequisites
    check_auth
    ensure_setup

    cd "$DAEMON_DIR"

    info "Pulling image..."
    local tag
    tag=$(grep HERMES_IMAGE_TAG "$DAEMON_DIR/.env.daemon" | cut -d= -f2 || echo "$VERSION")
    docker pull "${IMAGE}:${tag}"

    # Install systemd service
    local script_path
    script_path="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"

    local service_dir="$HOME/.config/systemd/user"
    mkdir -p "$service_dir"

    cat > "$service_dir/${SERVICE_NAME}.service" <<EOF
[Unit]
Description=Hermes Agent Daemon
After=network-online.target docker.service
Wants=network-online.target

[Service]
Type=simple
WorkingDirectory=${DAEMON_DIR}
ExecStart=${script_path} run
ExecStop=${script_path} stop
Restart=on-failure
RestartSec=10
Environment=HOME=${HOME}
Environment=PATH=${PATH}

[Install]
WantedBy=default.target
EOF

    systemctl --user daemon-reload
    systemctl --user enable "$SERVICE_NAME"
    systemctl --user start "$SERVICE_NAME"

    sudo loginctl enable-linger "$USER" 2>/dev/null \
        || warn "enable-linger needs sudo. Service may stop on logout."

    info "=== Daemon running (systemd) ==="
    info "  Logs:      $0 logs"
    info "  Status:    $0 status"
    info "  Stop:      $0 stop"
    info "  Update:    $0 update v0.2.0"
    info "  Uninstall: $0 uninstall"
}

cmd_run() {
    check_prerequisites
    check_auth
    ensure_setup

    cd "$DAEMON_DIR"
    info "Starting daemon (Ctrl+C to stop)..."
    $COMPOSE_CMD up --abort-on-container-exit hermes-daemon
}

cmd_stop() {
    if systemctl --user is-active "$SERVICE_NAME" >/dev/null 2>&1; then
        systemctl --user stop "$SERVICE_NAME"
        info "Service stopped."
        return
    fi

    check_prerequisites
    cd "$DAEMON_DIR"
    $COMPOSE_CMD down
    info "Daemon stopped."
}

cmd_update() {
    local new_tag="${2:-}"
    if [[ -z "$new_tag" ]]; then
        error "Usage: $0 update <version>"
        echo "  Example: $0 update v0.2.0"
        exit 1
    fi

    check_prerequisites
    check_auth
    cd "$DAEMON_DIR"

    info "Updating to ${IMAGE}:${new_tag}..."
    docker pull "${IMAGE}:${new_tag}"

    # Update .env.daemon with new tag
    sed -i "s/^HERMES_IMAGE_TAG=.*/HERMES_IMAGE_TAG=${new_tag}/" "$DAEMON_DIR/.env.daemon"

    # Regenerate compose file with new tag
    generate_compose_file

    $COMPOSE_CMD up -d hermes-daemon
    info "Update complete: ${new_tag}"
}

cmd_logs() {
    if systemctl --user is-active "$SERVICE_NAME" >/dev/null 2>&1; then
        journalctl --user -u "$SERVICE_NAME" -f
    else
        check_prerequisites
        cd "$DAEMON_DIR"
        $COMPOSE_CMD logs -f hermes-daemon
    fi
}

cmd_status() {
    if systemctl --user cat "$SERVICE_NAME" >/dev/null 2>&1; then
        systemctl --user status "$SERVICE_NAME"
    else
        check_prerequisites
        cd "$DAEMON_DIR"
        $COMPOSE_CMD ps
    fi
}

cmd_uninstall() {
    systemctl --user stop "$SERVICE_NAME" 2>/dev/null || true
    systemctl --user disable "$SERVICE_NAME" 2>/dev/null || true
    rm -f "$HOME/.config/systemd/user/${SERVICE_NAME}.service"
    systemctl --user daemon-reload

    check_prerequisites
    cd "$DAEMON_DIR" 2>/dev/null && $COMPOSE_CMD down 2>/dev/null || true

    info "Service removed. Config preserved at $DAEMON_DIR/"
}

# --- Main ---
case "${1:-start}" in
    start)     cmd_start     ;;
    run)       cmd_run       ;;
    stop)      cmd_stop      ;;
    update)    cmd_update "$@" ;;
    logs)      cmd_logs      ;;
    status)    cmd_status    ;;
    uninstall) cmd_uninstall ;;
    help|-h|--help)
        echo "Hermes Daemon Manager"
        echo ""
        echo "Usage: $0 [command]"
        echo ""
        echo "  (none)        — Setup + install as background service (default)"
        echo "  run           — Foreground mode (for debugging)"
        echo "  stop          — Stop daemon"
        echo "  update <ver>  — Pull specific version + restart (e.g. update v0.2.0)"
        echo "  logs          — Tail daemon logs"
        echo "  status        — Show daemon status"
        echo "  uninstall     — Remove background service"
        echo ""
        echo "Auth: Run 'claude login' on this machine. Container uses host credentials (read-only)."
        ;;
    *)
        error "Unknown command: $1"
        echo "Run '$0 help' for usage."
        exit 1
        ;;
esac
