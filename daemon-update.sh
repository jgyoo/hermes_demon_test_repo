#!/bin/bash
# Olympus v2 Daemon — 업데이트 스크립트
#
# 사용법:
#   curl -sL https://raw.githubusercontent.com/jgyoo/hermes_demon_test_repo/main/daemon-update.sh | bash
#
# 최신 이미지를 pull하고 데몬을 재시작합니다.

set -e

NAME="${DAEMON_NAME:-$(hostname)}"
IMAGE="ghcr.io/jgyoo/hermes-daemon:latest"
CONTAINER="olympus-daemon-${NAME}"

echo "╔══════════════════════════════════════╗"
echo "║   🏛️  Olympus v2 Daemon Update       ║"
echo "╚══════════════════════════════════════╝"
echo ""
echo "  Container: $CONTAINER"
echo "  Image:     $IMAGE"
echo ""

# Check if container exists
if ! docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER}$"; then
  echo "❌ 컨테이너 '$CONTAINER'를 찾을 수 없습니다."
  echo "   먼저 install-v2.sh로 설치하세요."
  exit 1
fi

echo "[1/3] 최신 이미지 다운로드..."
docker pull "$IMAGE"

echo "[2/3] 데몬 재시작..."
docker stop "$CONTAINER" 2>/dev/null || true
docker rm "$CONTAINER" 2>/dev/null || true

# Get existing env vars from old container
OLD_ENV=$(docker inspect "$CONTAINER" --format '{{range .Config.Env}}{{println .}}{{end}}' 2>/dev/null || true)
DAEMON_NAME_VAL=$(echo "$OLD_ENV" | grep "^DAEMON_NAME=" | cut -d= -f2-)
OLYMPUS_URL_VAL=$(echo "$OLD_ENV" | grep "^OLYMPUS_URL=" | cut -d= -f2-)
PORT=$(docker inspect "$CONTAINER" --format '{{range $k, $v := .HostConfig.PortBindings}}{{range $v}}{{.HostPort}}{{end}}{{end}}' 2>/dev/null || echo "9100")

[ -z "$DAEMON_NAME_VAL" ] && DAEMON_NAME_VAL="$NAME"
[ -z "$OLYMPUS_URL_VAL" ] && OLYMPUS_URL_VAL="https://olympus-production-3544.up.railway.app/mcp"
[ -z "$PORT" ] && PORT="9100"

echo "[3/3] 새 컨테이너 시작..."
docker run -d \
  --name "$CONTAINER" \
  --restart unless-stopped \
  -e DAEMON_NAME="$DAEMON_NAME_VAL" \
  -e OLYMPUS_URL="$OLYMPUS_URL_VAL" \
  -v "${HOME}/.claude:/home/daemon/.claude:ro" \
  -v "${HOME}/.ssh:/home/daemon/.ssh:ro" \
  -p "${PORT}:9100" \
  "$IMAGE"

echo ""
echo "✅ 데몬 업데이트 완료!"
echo ""
echo "  로그: docker logs -f $CONTAINER"
echo "  상태: docker ps | grep $CONTAINER"
