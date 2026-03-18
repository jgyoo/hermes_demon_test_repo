#!/bin/bash
# Olympus v2 Daemon — 설치 & 업데이트 통합 스크립트
#
# 사용법:
#   curl -sL https://raw.githubusercontent.com/jgyoo/hermes_demon_test_repo/main/install-v2.sh | bash
#
# 환경 변수:
#   DAEMON_NAME    — 데몬 이름 (기본: hostname)
#   DAEMON_USER    — 텔레메트리 수집 대상 사용자 (기본: 현재 사용자)
#   OLYMPUS_URL    — Olympus MCP URL (기본: Railway 주소)
#   DAEMON_PORT    — 데몬 포트 (기본: 9100)

set -e

NAME="${DAEMON_NAME:-$(hostname)}"
USER="${DAEMON_USER:-$(whoami)}"
URL="${OLYMPUS_URL:-https://olympus-production-3544.up.railway.app/mcp}"
PORT="${DAEMON_PORT:-9100}"
IMAGE="ghcr.io/jgyoo/hermes-daemon:latest"
CONTAINER="olympus-daemon-${NAME}"

# Detect mode
MODE="install"
if docker ps -a --format '{{.Names}}' 2>/dev/null | grep -q "^${CONTAINER}$"; then
  MODE="update"
fi

if [ "$MODE" = "update" ]; then
  echo "╔══════════════════════════════════════╗"
  echo "║   🏛️  Olympus v2 Daemon Update       ║"
  echo "╚══════════════════════════════════════╝"
else
  echo "╔══════════════════════════════════════╗"
  echo "║   🏛️  Olympus v2 Daemon Install      ║"
  echo "╚══════════════════════════════════════╝"
fi
echo ""
echo "  Name:      $NAME"
echo "  User:      $USER"
echo "  Olympus:   $URL"
echo "  Port:      $PORT"
echo "  Image:     $IMAGE"
echo ""

# Stop existing daemons
echo "[1/3] 기존 데몬 중지..."
docker kill olympus-daemon olympus-daemon-${NAME} hermes-daemon-${NAME} hermes-daemon-default 2>/dev/null || true
docker rm -f olympus-daemon olympus-daemon-${NAME} hermes-daemon-${NAME} hermes-daemon-default 2>/dev/null || true

# Pull latest
echo "[2/3] 최신 이미지 다운로드..."
docker pull "$IMAGE"

# Run — mount host .claude as .host-claude (read-only) to prevent ownership changes
echo "[3/3] 데몬 시작..."
docker run -d \
  --name "$CONTAINER" \
  --restart unless-stopped \
  -e DAEMON_NAME="$NAME" \
  -e DAEMON_USER="$USER" \
  -e OLYMPUS_URL="$URL" \
  -v "${HOME}/.claude:/home/daemon/.host-claude:ro" \
  -v "${HOME}/.ssh:/home/daemon/.ssh:ro" \
  -p "${PORT}:9100" \
  "$IMAGE"

echo ""
if [ "$MODE" = "update" ]; then
  echo "✅ 데몬 업데이트 완료!"
else
  echo "✅ 데몬 설치 완료!"
fi
echo ""
echo "  로그:     docker logs -f $CONTAINER"
echo "  중지:     docker stop $CONTAINER"
echo "  재설치:   curl -sL https://raw.githubusercontent.com/jgyoo/hermes_demon_test_repo/main/install-v2.sh | bash"
