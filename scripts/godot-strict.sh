#!/usr/bin/env bash
set -euo pipefail

LOG_FILE="$(mktemp)"
trap 'rm -f "$LOG_FILE"' EXIT

set +e
godot "$@" 2>&1 | tee "$LOG_FILE"
STATUS=${PIPESTATUS[0]}
set -e

if [ "$STATUS" -ne 0 ]; then
  exit "$STATUS"
fi

if grep -Eq 'SCRIPT ERROR:|Parse Error:|ERROR: Failed to load script|ERROR: Failed to instantiate an autoload' "$LOG_FILE"; then
  echo "Godotログにscript/autoloadエラーを検出しました。" >&2
  exit 1
fi
