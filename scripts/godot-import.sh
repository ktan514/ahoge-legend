#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

if [ "${AHOGE_GODOT_IMPORTED:-0}" = "1" ]; then
  exit 0
fi

LOG_FILE="$(mktemp)"
trap 'rm -f "$LOG_FILE"' EXIT

set +e
godot --headless --path . --import 2>&1 | tee "$LOG_FILE"
STATUS=${PIPESTATUS[0]}
set -e

if [ "$STATUS" -ne 0 ]; then
  exit "$STATUS"
fi

if grep -Eq 'SCRIPT ERROR:|Parse Error:|ERROR: Failed to load script|ERROR: Failed to instantiate an autoload' "$LOG_FILE"; then
  echo "Godot import中にscript/autoloadエラーを検出しました。" >&2
  exit 1
fi
