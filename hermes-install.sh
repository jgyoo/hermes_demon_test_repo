#!/usr/bin/env bash
# hermes-install.sh — Hermes daemon one-command setup (Linux/macOS)
#
# One-liner install:
#   curl -fsSL <RAW_URL>/hermes-install.sh | bash
#
# Or download and run:
#   ./hermes-install.sh             # Setup + start
#   ./hermes-install.sh stop        # Stop daemon
#   ./hermes-install.sh logs        # Tail logs
#   ./hermes-install.sh status      # Show status + version
#   ./hermes-install.sh update      # Manual image update
#   ./hermes-install.sh uninstall   # Remove everything
set -euo pipefail

REGISTRY="${HERMES_REGISTRY:-ghcr.io/jgyoo}"
IMAGE="${REGISTRY}/hermes-daemon"
DAEMON_DIR="${HERMES_DAEMON_DIR:-$HOME/.hermes-daemon}"

# Colors — use printf throughout (macOS bash 3.2 echo -e is unreliable)
RED=$'\033[0;31m'
GREEN=$'\033[0;32m'
YELLOW=$'\033[1;33m'
CYAN=$'\033[0;36m'
BOLD=$'\033[1m'
NC=$'\033[0m'

info()  { printf "%s[INFO]%s %s\n" "$GREEN" "$NC" "$*"; }
warn()  { printf "%s[WARN]%s %s\n" "$YELLOW" "$NC" "$*"; }
error() { printf "%s[ERROR]%s %s\n" "$RED" "$NC" "$*" >&2; }
step()  { printf "\n%s%s==> %s%s\n" "$CYAN" "$BOLD" "$*" "$NC"; }

# ---------------------------------------------------------------------------
# Prerequisites
# ---------------------------------------------------------------------------

check_docker() {
    if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
        info "Docker verified"
        return 0
    fi

    if command -v docker >/dev/null 2>&1; then
        error "Docker is installed but not running."
        case "$(uname -s)" in
            Darwin*) echo "  Open Docker Desktop app and wait until it's ready, then re-run." ;;
            *)       echo "  Run: sudo systemctl start docker" ;;
        esac
        exit 1
    fi

    error "Docker is not installed."
    echo ""
    case "$(uname -s)" in
        Darwin*) echo "  Install Docker Desktop: https://docs.docker.com/desktop/install/mac-install/" ;;
        *)       echo "  Install: curl -fsSL https://get.docker.com | sh"
                 echo "  Then:    sudo usermod -aG docker \$USER && newgrp docker" ;;
    esac
    exit 1
}

detect_compose() {
    if docker compose version >/dev/null 2>&1; then
        COMPOSE_CMD="docker compose"
    elif command -v docker-compose >/dev/null 2>&1; then
        COMPOSE_CMD="docker-compose"
    else
        error "docker compose not found. Please update Docker or install docker-compose-plugin."
        exit 1
    fi
}

check_claude_auth() {
    # Check multiple possible credential locations
    local found=false
    for creds in "$HOME/.claude/.credentials.json" "$HOME/.claude/credentials.json"; do
        if [[ -f "$creds" && -s "$creds" ]]; then
            found=true
            break
        fi
    done

    if [[ "$found" == "false" ]]; then
        error "Claude credentials not found."
        echo "  Checked: ~/.claude/.credentials.json, ~/.claude/credentials.json"
        echo ""
        echo "  1. Install Claude Code CLI (if needed):"
        printf "     %snpm install -g @anthropic-ai/claude-code%s\n" "$BOLD" "$NC"
        echo ""
        echo "  2. Login:"
        printf "     %sclaude login%s\n" "$BOLD" "$NC"
        echo ""
        echo "  Then re-run this script."
        exit 1
    fi
    info "Claude credentials verified"
}

check_prerequisites() {
    check_docker
    detect_compose
    check_claude_auth
}

# ---------------------------------------------------------------------------
# Setup — interactive prompts (works with curl | bash via /dev/tty)
# ---------------------------------------------------------------------------

prompt_input() {
    local prompt="$1" default="$2" var_name="$3"
    local input
    if [[ -t 0 ]]; then
        read -rp "$prompt" input
    else
        read -rp "$prompt" input < /dev/tty
    fi
    eval "$var_name=\"${input:-$default}\""
}

generate_compose_file() {
    local agent_name
    agent_name=$(grep HERMES_AGENT_AGENT_NAME "$DAEMON_DIR/.env.daemon" | cut -d= -f2)

    cat > "$DAEMON_DIR/docker-compose.yml" <<YAML
services:
  hermes-daemon:
    image: ${IMAGE}:latest
    container_name: hermes-daemon-${agent_name}
    env_file:
      - .env.daemon
    volumes:
      - daemon-workspace:/home/hermes/hermes-workspace
      - \${HOME}/.claude:/home/hermes/.claude
      - \${HOME}/.claude.json:/home/hermes/.claude.json
    ports:
      - "4317:4317"
      - "9100:9100"
    stop_grace_period: 120s
    restart: unless-stopped
    labels:
      - "com.centurylinklabs.watchtower.enable=true"

  watchtower:
    image: containrrr/watchtower
    container_name: hermes-watchtower-${agent_name}
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
    environment:
      - WATCHTOWER_CLEANUP=true
      - WATCHTOWER_POLL_INTERVAL=300
      - WATCHTOWER_LABEL_ENABLE=true
      - WATCHTOWER_HTTP_API_UPDATE=true
      - WATCHTOWER_HTTP_API_TOKEN=hermes-update
    ports:
      - "127.0.0.1:8080:8080"
    restart: unless-stopped

volumes:
  daemon-workspace:
YAML
}

ensure_setup() {
    if [[ -f "$DAEMON_DIR/.env.daemon" && -f "$DAEMON_DIR/docker-compose.yml" ]]; then
        return 0
    fi

    step "Hermes Daemon Setup"
    mkdir -p "$DAEMON_DIR"

    local default_name daemon_name orch_url
    default_name=$(hostname)

    echo ""
    prompt_input "  Daemon name [$default_name]: " "$default_name" daemon_name
    prompt_input "  Orchestrator URL [ws://192.168.11.23:8003/ws/nodes]: " "ws://192.168.11.23:8003/ws/nodes" orch_url

    cat > "$DAEMON_DIR/.env.daemon" <<EOF
HERMES_AGENT_AGENT_NAME=${daemon_name}
HERMES_AGENT_ORCHESTRATOR_URL=${orch_url}
CLAUDE_CONFIG_DIR=/home/hermes/.claude

# OTEL Configuration
CLAUDE_CODE_ENABLE_TELEMETRY=1
OTEL_METRICS_EXPORTER=otlp
OTEL_LOGS_EXPORTER=otlp
OTEL_EXPORTER_OTLP_PROTOCOL=grpc
OTEL_EXPORTER_OTLP_ENDPOINT=http://localhost:4317
OTEL_LOG_TOOL_DETAILS=1
EOF

    generate_compose_file
    info "Configuration saved to $DAEMON_DIR/"
}

# ---------------------------------------------------------------------------
# Save this script locally for future management commands
# ---------------------------------------------------------------------------

save_script_locally() {
    local target="$DAEMON_DIR/hermes-install.sh"
    # When piped (curl | bash), $0 is "bash" — skip copy in that case
    if [[ "$0" != "bash" && -f "$0" ]]; then
        cp "$0" "$target" 2>/dev/null || true
        chmod +x "$target" 2>/dev/null || true
    fi
}

# ---------------------------------------------------------------------------
# Commands
# ---------------------------------------------------------------------------

cmd_start() {
    step "Checking prerequisites..."
    check_prerequisites
    ensure_setup

    cd "$DAEMON_DIR"
    step "Pulling latest image (this may take a few minutes on first install)..."
    docker pull "${IMAGE}:latest" || true

    step "Starting daemon + Watchtower..."
    $COMPOSE_CMD up -d

    echo ""
    info "=== Hermes Daemon is running! ==="
    echo ""
    printf "  %sManage with:%s\n" "$BOLD" "$NC"
    echo "    hermes logs      — View logs"
    echo "    hermes status    — Check status"
    echo "    hermes stop      — Stop daemon"
    echo "    hermes update    — Manual update"
    echo "    hermes uninstall — Remove"
    echo ""
    echo "  Auto-update is enabled."
    echo "  Config: $DAEMON_DIR/"

    # Install 'hermes' alias for convenience
    install_alias
}

cmd_stop() {
    check_docker; detect_compose
    cd "$DAEMON_DIR"
    $COMPOSE_CMD down
    info "Daemon stopped."
}

cmd_update() {
    check_docker; detect_compose
    cd "$DAEMON_DIR"
    info "Pulling latest image..."
    docker pull "${IMAGE}:latest"
    $COMPOSE_CMD up -d hermes-daemon
    info "Update complete."
}

cmd_logs() {
    check_docker; detect_compose
    cd "$DAEMON_DIR"
    $COMPOSE_CMD logs -f hermes-daemon
}

cmd_status() {
    check_docker; detect_compose
    cd "$DAEMON_DIR"
    echo ""
    $COMPOSE_CMD ps
    echo ""
    local container
    container=$($COMPOSE_CMD ps -q hermes-daemon 2>/dev/null || true)
    if [[ -n "$container" ]]; then
        local version
        version=$(docker exec "$container" python -c "from agent.daemon import __version__; print(__version__)" 2>/dev/null || echo "unknown")
        printf "%s[INFO]%s Daemon version: %s%s%s\n" "$GREEN" "$NC" "$BOLD" "$version" "$NC"
    fi
}

cmd_uninstall() {
    check_docker; detect_compose
    cd "$DAEMON_DIR" 2>/dev/null && $COMPOSE_CMD down -v 2>/dev/null || true
    # Remove alias
    local shell_rc="$HOME/.bashrc"
    [[ -f "$HOME/.zshrc" ]] && shell_rc="$HOME/.zshrc"
    if [[ "$(uname -s)" == "Darwin" ]]; then
        sed -i '' '/# Hermes daemon alias/d' "$shell_rc" 2>/dev/null || true
        sed -i '' '/alias hermes=/d' "$shell_rc" 2>/dev/null || true
    else
        sed -i '/# Hermes daemon alias/d' "$shell_rc" 2>/dev/null || true
        sed -i '/alias hermes=/d' "$shell_rc" 2>/dev/null || true
    fi
    info "Service removed. Config preserved at $DAEMON_DIR/"
}

cmd_run() {
    check_prerequisites
    ensure_setup
    cd "$DAEMON_DIR"
    info "Starting daemon (Ctrl+C to stop)..."
    $COMPOSE_CMD up --abort-on-container-exit hermes-daemon
}

# ---------------------------------------------------------------------------
# Convenience alias: 'hermes logs', 'hermes status', etc.
# ---------------------------------------------------------------------------

install_alias() {
    local script="$DAEMON_DIR/hermes-install.sh"
    local shell_rc="$HOME/.bashrc"
    [[ -f "$HOME/.zshrc" ]] && shell_rc="$HOME/.zshrc"

    if ! grep -q "alias hermes=" "$shell_rc" 2>/dev/null; then
        echo "" >> "$shell_rc"
        echo "# Hermes daemon alias" >> "$shell_rc"
        echo "alias hermes='$script'" >> "$shell_rc"
        printf "%s[INFO]%s Added 'hermes' alias. Run: %ssource %s%s or open a new terminal.\n" "$GREEN" "$NC" "$BOLD" "$shell_rc" "$NC"
    fi
}

# --- Main ---
case "${1:-start}" in
    start)     save_script_locally; cmd_start     ;;
    run)       cmd_run       ;;
    stop)      cmd_stop      ;;
    update)    cmd_update    ;;
    logs)      cmd_logs      ;;
    status)    cmd_status    ;;
    uninstall) cmd_uninstall ;;
    help|-h|--help)
        echo ""
        printf "  %sHermes Daemon Manager%s\n" "$BOLD" "$NC"
        echo ""
        echo "  Usage: hermes [command]"
        echo ""
        printf "    %s(none)%s    — Setup + start (default)\n" "$BOLD" "$NC"
        printf "    %sstop%s      — Stop daemon\n" "$BOLD" "$NC"
        printf "    %slogs%s      — Tail logs\n" "$BOLD" "$NC"
        printf "    %sstatus%s    — Show status + version\n" "$BOLD" "$NC"
        printf "    %supdate%s    — Manual image update\n" "$BOLD" "$NC"
        printf "    %srun%s       — Foreground mode (debug)\n" "$BOLD" "$NC"
        printf "    %suninstall%s — Remove everything\n" "$BOLD" "$NC"
        echo ""
        ;;
    *)
        error "Unknown command: $1"
        echo "Run 'hermes help' for usage."
        exit 1
        ;;
esac
