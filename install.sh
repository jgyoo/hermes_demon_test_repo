#!/bin/bash
# Olympus v2 Daemon — 퍼블릭 설치 스크립트
#
# 이 파일을 https://github.com/jgyoo/hermes_demon_test_repo/install.sh 에 올립니다.
#
# 사용법:
#   GITHUB_TOKEN=ghp_xxx OLYMPUS_URL=https://olympus.example.com/mcp \
#     curl -sL https://raw.githubusercontent.com/jgyoo/hermes_demon_test_repo/main/install.sh | bash
#
# 또는 SSH 키가 있으면 토큰 없이:
#   OLYMPUS_URL=https://olympus.example.com/mcp \
#     curl -sL https://raw.githubusercontent.com/jgyoo/hermes_demon_test_repo/main/install.sh | bash

set -e

PRIVATE_REPO="jgyoo/olympus_jg"
SCRIPT_URL="https://raw.githubusercontent.com/${PRIVATE_REPO}/main/v2/scripts/daemon-install.sh"

# If we have a token, fetch the real install script from private repo
if [ -n "$GITHUB_TOKEN" ]; then
    curl -sL -H "Authorization: token $GITHUB_TOKEN" \
        -H "Accept: application/vnd.github.v3.raw" \
        "https://api.github.com/repos/${PRIVATE_REPO}/contents/v2/scripts/daemon-install.sh" | bash -s "$@"
else
    # Try SSH-based clone instead
    echo "[olympus] GITHUB_TOKEN이 설정되지 않았습니다."
    echo "[olympus] SSH 키로 시도합니다..."

    INSTALL_DIR="${INSTALL_DIR:-$HOME/olympus-daemon}"
    mkdir -p "$INSTALL_DIR"

    if [ -d "$INSTALL_DIR/.repo/.git" ]; then
        git -C "$INSTALL_DIR/.repo" pull --ff-only
    else
        git clone "git@github.com:${PRIVATE_REPO}.git" "$INSTALL_DIR/.repo"
    fi

    bash "$INSTALL_DIR/.repo/v2/scripts/daemon-install.sh" "$@"
fi
