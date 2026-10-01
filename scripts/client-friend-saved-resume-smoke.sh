#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

./scripts/server-health.sh >/dev/null
./scripts/godot-import.sh

export AHOGE_DEVICE_ID_OVERRIDE="ahoge-friend-resume-${GITHUB_RUN_ID:-local}-${GITHUB_RUN_ATTEMPT:-0}-$$-${RANDOM:-0}"

LOG_FILE="$(mktemp)"
trap 'rm -f "$LOG_FILE"' EXIT

set +e
./scripts/godot-strict.sh --headless --path . --script res://tests/friend_saved_match_resume_smoke.gd 2>&1 | tee "$LOG_FILE"
STATUS=${PIPESTATUS[0]}
set -e

if [[ "$STATUS" -ne 0 ]]; then
  exit "$STATUS"
fi

if grep -Eq 'Authorization[^\n]*Bearer|Bearer[[:space:]]+[A-Za-z0-9._-]+|/ws\?[^\n]*token=' "$LOG_FILE"; then
  echo "認証tokenがFriend再ログイン回帰ログへ出力されています。" >&2
  exit 1
fi
