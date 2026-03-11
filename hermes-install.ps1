<#
.SYNOPSIS
    Hermes Daemon one-command setup for Windows.

.DESCRIPTION
    One-liner install:
        irm <RAW_URL>/hermes-install.ps1 | iex

    Or download and run:
        .\hermes-install.ps1              # Setup + start
        .\hermes-install.ps1 stop         # Stop daemon
        .\hermes-install.ps1 logs         # Tail logs
        .\hermes-install.ps1 status       # Show status + version
        .\hermes-install.ps1 update       # Manual image update
        .\hermes-install.ps1 uninstall    # Remove everything

.PARAMETER Command
    The command to execute. Default: start
#>
param(
    [Parameter(Position=0)]
    [ValidateSet("start","stop","logs","status","update","run","uninstall","help")]
    [string]$Command = "start"
)

$ErrorActionPreference = "Stop"

$REGISTRY = if ($env:HERMES_REGISTRY) { $env:HERMES_REGISTRY } else { "ghcr.io/jgyoo" }
$IMAGE = "$REGISTRY/hermes-daemon"
$DAEMON_DIR = if ($env:HERMES_DAEMON_DIR) { $env:HERMES_DAEMON_DIR } else { "$env:USERPROFILE\.hermes-daemon" }

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

function Write-Info  { param($Msg) Write-Host "[INFO] " -ForegroundColor Green -NoNewline; Write-Host $Msg }
function Write-Warn  { param($Msg) Write-Host "[WARN] " -ForegroundColor Yellow -NoNewline; Write-Host $Msg }
function Write-Err   { param($Msg) Write-Host "[ERROR] " -ForegroundColor Red -NoNewline; Write-Host $Msg }
function Write-Step  { param($Msg) Write-Host "`n==> $Msg" -ForegroundColor Cyan }

# ---------------------------------------------------------------------------
# Prerequisites
# ---------------------------------------------------------------------------

function Test-Docker {
    $dockerCmd = Get-Command docker -ErrorAction SilentlyContinue
    if (-not $dockerCmd) {
        Write-Err "Docker is not installed."
        Write-Host ""
        Write-Host "  Install Docker Desktop: https://docs.docker.com/desktop/install/windows-install/"
        Write-Host ""
        exit 1
    }

    $info = docker info 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Err "Docker is installed but not running."
        Write-Host "  Please start Docker Desktop and try again."
        exit 1
    }
}

function Test-DockerCompose {
    docker compose version 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) {
        Write-Err "docker compose not found. Please update Docker Desktop."
        exit 1
    }
}

function Test-ClaudeAuth {
    $creds = "$env:USERPROFILE\.claude\.credentials.json"
    if (-not (Test-Path $creds) -or (Get-Item $creds).Length -eq 0) {
        Write-Err "Claude credentials not found."
        Write-Host ""
        Write-Host "  1. Install Claude Code CLI (if needed):"
        Write-Host "     npm install -g @anthropic-ai/claude-code" -ForegroundColor White
        Write-Host ""
        Write-Host "  2. Login:"
        Write-Host "     claude login" -ForegroundColor White
        Write-Host ""
        Write-Host "  Then re-run this script."
        exit 1
    }
    Write-Info "Claude credentials verified"
}

function Test-Prerequisites {
    Test-Docker
    Test-DockerCompose
    Test-ClaudeAuth
}

# ---------------------------------------------------------------------------
# Setup
# ---------------------------------------------------------------------------

function New-ComposeFile {
    $agentName = (Select-String -Path "$DAEMON_DIR\.env.daemon" -Pattern "HERMES_AGENT_AGENT_NAME=(.+)" |
        ForEach-Object { $_.Matches.Groups[1].Value }).Trim()

    # Windows: Docker Desktop uses named pipe, not unix socket
    $composeContent = @"
services:
  hermes-daemon:
    image: ${IMAGE}:latest
    container_name: hermes-daemon-${agentName}
    env_file:
      - .env.daemon
    volumes:
      - daemon-workspace:/home/hermes/hermes-workspace
      - $($env:USERPROFILE -replace '\\','/')/.claude:/home/hermes/.claude
      - $($env:USERPROFILE -replace '\\','/')/.claude.json:/home/hermes/.claude.json
    ports:
      - "4317:4317"
      - "9100:9100"
    stop_grace_period: 120s
    restart: unless-stopped
    labels:
      - "com.centurylinklabs.watchtower.enable=true"

  watchtower:
    image: containrrr/watchtower
    container_name: hermes-watchtower-${agentName}
    volumes:
      - //var/run/docker.sock:/var/run/docker.sock
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
"@
    $composeContent | Out-File -FilePath "$DAEMON_DIR\docker-compose.yml" -Encoding utf8NoBOM
}

function Initialize-Setup {
    if ((Test-Path "$DAEMON_DIR\.env.daemon") -and (Test-Path "$DAEMON_DIR\docker-compose.yml")) {
        return
    }

    Write-Step "Hermes Daemon Setup"
    New-Item -ItemType Directory -Path $DAEMON_DIR -Force | Out-Null

    $defaultName = $env:COMPUTERNAME
    Write-Host ""
    $daemonName = Read-Host "  Daemon name [$defaultName]"
    if ([string]::IsNullOrWhiteSpace($daemonName)) { $daemonName = $defaultName }

    $defaultUrl = "ws://192.168.11.23:8003/ws/nodes"
    $orchUrl = Read-Host "  Orchestrator URL [$defaultUrl]"
    if ([string]::IsNullOrWhiteSpace($orchUrl)) { $orchUrl = $defaultUrl }

    $envContent = @"
HERMES_AGENT_AGENT_NAME=${daemonName}
HERMES_AGENT_ORCHESTRATOR_URL=${orchUrl}
HERMES_AGENT_HOST_OS=windows
HERMES_AGENT_HOST_ARCH=$([System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture.ToString().ToLower())
CLAUDE_CONFIG_DIR=/home/hermes/.claude

# OTEL Configuration
CLAUDE_CODE_ENABLE_TELEMETRY=1
OTEL_METRICS_EXPORTER=otlp
OTEL_LOGS_EXPORTER=otlp
OTEL_EXPORTER_OTLP_PROTOCOL=grpc
OTEL_EXPORTER_OTLP_ENDPOINT=http://localhost:4317
OTEL_LOG_TOOL_DETAILS=1
"@
    $envContent | Out-File -FilePath "$DAEMON_DIR\.env.daemon" -Encoding utf8NoBOM

    New-ComposeFile
    Write-Info "Configuration saved to $DAEMON_DIR\"
}

# ---------------------------------------------------------------------------
# Commands
# ---------------------------------------------------------------------------

function Invoke-Start {
    Write-Step "Checking prerequisites..."
    Test-Prerequisites
    Initialize-Setup

    # Save script locally for future use
    $target = "$DAEMON_DIR\hermes.ps1"
    if ($MyInvocation.ScriptName -and (Test-Path $MyInvocation.ScriptName)) {
        Copy-Item $MyInvocation.ScriptName $target -Force 2>$null
    }

    Push-Location $DAEMON_DIR
    try {
        Write-Step "Pulling latest image..."
        docker pull "${IMAGE}:latest" 2>$null

        Write-Step "Starting daemon + Watchtower..."
        docker compose up -d

        Write-Host ""
        Write-Info "=== Hermes Daemon is running! ==="
        Write-Host ""
        Write-Host "  Manage with:" -ForegroundColor White
        Write-Host "    .\hermes.ps1 logs      - View logs"
        Write-Host "    .\hermes.ps1 status    - Check status"
        Write-Host "    .\hermes.ps1 stop      - Stop daemon"
        Write-Host "    .\hermes.ps1 update    - Manual update"
        Write-Host "    .\hermes.ps1 uninstall - Remove"
        Write-Host ""
        Write-Host "  Auto-update is enabled."
        Write-Host "  Config: $DAEMON_DIR\"
    }
    finally { Pop-Location }
}

function Invoke-Stop {
    Test-Docker; Test-DockerCompose
    Push-Location $DAEMON_DIR
    try {
        docker compose down
        Write-Info "Daemon stopped."
    }
    finally { Pop-Location }
}

function Invoke-Update {
    Test-Docker; Test-DockerCompose
    Push-Location $DAEMON_DIR
    try {
        Write-Info "Pulling latest image..."
        docker pull "${IMAGE}:latest"
        docker compose up -d hermes-daemon
        Write-Info "Update complete."
    }
    finally { Pop-Location }
}

function Invoke-Logs {
    Test-Docker; Test-DockerCompose
    Push-Location $DAEMON_DIR
    try {
        docker compose logs -f hermes-daemon
    }
    finally { Pop-Location }
}

function Invoke-Status {
    Test-Docker; Test-DockerCompose
    Push-Location $DAEMON_DIR
    try {
        Write-Host ""
        docker compose ps
        Write-Host ""

        $container = docker compose ps -q hermes-daemon 2>$null
        if ($container) {
            $version = docker exec $container python -c "from agent.daemon import __version__; print(__version__)" 2>$null
            if (-not $version) { $version = "unknown" }
            Write-Info "Daemon version: $version"
        }
    }
    finally { Pop-Location }
}

function Invoke-Run {
    Test-Prerequisites
    Initialize-Setup
    Push-Location $DAEMON_DIR
    try {
        Write-Info "Starting daemon (Ctrl+C to stop)..."
        docker compose up --abort-on-container-exit hermes-daemon
    }
    finally { Pop-Location }
}

function Invoke-Uninstall {
    Test-Docker; Test-DockerCompose
    Push-Location $DAEMON_DIR
    try {
        docker compose down -v 2>$null
    }
    catch {}
    finally { Pop-Location }
    Write-Info "Service removed. Config preserved at $DAEMON_DIR\"
}

function Show-Help {
    Write-Host ""
    Write-Host "  Hermes Daemon Manager" -ForegroundColor White
    Write-Host ""
    Write-Host "  Usage: .\hermes.ps1 [command]"
    Write-Host ""
    Write-Host "    (none)    " -ForegroundColor White -NoNewline; Write-Host "- Setup + start (default)"
    Write-Host "    stop      " -ForegroundColor White -NoNewline; Write-Host "- Stop daemon"
    Write-Host "    logs      " -ForegroundColor White -NoNewline; Write-Host "- Tail logs"
    Write-Host "    status    " -ForegroundColor White -NoNewline; Write-Host "- Show status + version"
    Write-Host "    update    " -ForegroundColor White -NoNewline; Write-Host "- Manual image update"
    Write-Host "    run       " -ForegroundColor White -NoNewline; Write-Host "- Foreground mode (debug)"
    Write-Host "    uninstall " -ForegroundColor White -NoNewline; Write-Host "- Remove everything"
    Write-Host ""
}

# --- Main ---
switch ($Command) {
    "start"     { Invoke-Start }
    "stop"      { Invoke-Stop }
    "update"    { Invoke-Update }
    "logs"      { Invoke-Logs }
    "status"    { Invoke-Status }
    "run"       { Invoke-Run }
    "uninstall" { Invoke-Uninstall }
    "help"      { Show-Help }
}
