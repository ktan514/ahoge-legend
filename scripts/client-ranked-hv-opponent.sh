#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

./scripts/server-health.sh >/dev/null

echo "Ranked Human Verification用のP2を起動します。"
echo "このTerminalはP2専用です。P1のGodot実画面は別Terminalで操作してください。"

./scripts/godot-strict.sh --headless --path . --script res://tools/ranked_hv_opponent.gd
