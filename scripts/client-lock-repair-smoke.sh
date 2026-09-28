#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

./scripts/server-health.sh >/dev/null
./scripts/godot-import.sh

LOG_FILE="$(mktemp)"
trap 'rm -f "$LOG_FILE"' EXIT

set +e
./scripts/godot-strict.sh --headless --path . --script res://tests/lock_repair_smoke.gd 2>&1 | tee "$LOG_FILE"
STATUS=${PIPESTATUS[0]}
set -e

if [ "$STATUS" -ne 0 ]; then
  exit "$STATUS"
fi

if grep -Eq 'Authorization[^\n]*Bearer|Bearer[[:space:]]+[A-Za-z0-9._-]+|/ws\?[^\n]*token=' "$LOG_FILE"; then
  echo "認証tokenがLock repairログへ出力されています。" >&2
  exit 1
fi
