#!/bin/bash
# Olympus v2 Daemon — Docker 원라인 설치
#
# 사용법:
#   curl -sL https://raw.githubusercontent.com/jgyoo/hermes_demon_test_repo/main/install-v2.sh | bash
#
# 환경 변수:
#   DAEMON_NAME    — 데몬 이름 (기본: hostname)
#   OLYMPUS_URL    — Olympus MCP URL (기본: Railway 주소)
#   DAEMON_PORT    — 데몬 포트 (기본: 9100)

set -e

NAME="${DAEMON_NAME:-$(hostname)}"
URL="${OLYMPUS_URL:-https://olympus-production-3544.up.railway.app/mcp}"
PORT="${DAEMON_PORT:-9100}"
IMAGE="ghcr.io/jgyoo/hermes-daemon:latest"

echo "╔══════════════════════════════════════╗"
echo "║   🏛️  Olympus v2 Daemon Install      ║"
echo "╚══════════════════════════════════════╝"
echo ""
echo "  Name:     $NAME"
echo "  Olympus:  $URL"
echo "  Port:     $PORT"
echo "  Image:    $IMAGE"
echo ""

# Stop existing v1/v2 daemon (force kill to avoid long grace period)
echo "[1/3] 기존 데몬 중지..."
docker kill olympus-daemon olympus-daemon-${NAME} hermes-daemon-${NAME} hermes-daemon-default 2>/dev/null || true
docker rm -f olympus-daemon olympus-daemon-${NAME} hermes-daemon-${NAME} hermes-daemon-default 2>/dev/null || true

# Pull latest
echo "[2/3] 최신 이미지 다운로드..."
docker pull "$IMAGE"

# Run
echo "[3/3] 데몬 시작..."
docker run -d \
  --name olympus-daemon-${NAME} \
  --restart unless-stopped \
  -e DAEMON_NAME="$NAME" \
  -e OLYMPUS_URL="$URL" \
  -v "${HOME}/.claude:/home/daemon/.claude:ro" \
  -v "${HOME}/.ssh:/home/daemon/.ssh:ro" \
  -p "${PORT}:9100" \
  "$IMAGE"

echo ""
echo "✅ 데몬 시작 완료!"
echo ""
echo "  로그:    docker logs -f olympus-daemon-${NAME}"
echo "  중지:    docker stop olympus-daemon-${NAME}"
echo "  업데이트: docker pull $IMAGE && docker restart olympus-daemon-${NAME}"
