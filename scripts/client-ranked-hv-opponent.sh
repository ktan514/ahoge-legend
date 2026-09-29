#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

./scripts/server-health.sh >/dev/null

MODE="${1:-new}"
STATE_FILE="${AHOGE_HV_OPPONENT_DEVICE_FILE:-${TMPDIR:-/tmp}/ahoge-legend-ranked-hv-opponent-device-id}"

case "$MODE" in
  new)
    DEVICE_ID="$(uuidgen | tr -d '-' | tr '[:upper:]' '[:lower:]')"
    printf '%s\n' "$DEVICE_ID" > "$STATE_FILE"
    export AHOGE_HV_OPPONENT_MODE="new"
    export AHOGE_HV_OPPONENT_DEVICE_ID="$DEVICE_ID"
    echo "Ranked Human Verification用のP2を起動します。"
    echo "このTerminalはP2専用です。P1のGodot実画面は別Terminalで操作してください。"
    echo "P2復帰確認時は同じTerminalで次を実行してください:"
    echo "  ./scripts/client-ranked-hv-opponent.sh reconnect"
    ;;
  reconnect)
    if [[ ! -s "$STATE_FILE" ]]; then
      echo "P2復帰用Device IDがありません。先に通常モードでP2を起動してください。" >&2
      exit 1
    fi
    export AHOGE_HV_OPPONENT_MODE="reconnect"
    export AHOGE_HV_OPPONENT_DEVICE_ID="$(cat "$STATE_FILE")"
    echo "同じP2 userで未解決Ranked matchへ再接続します。"
    ;;
  *)
    echo "usage: $0 [new|reconnect]" >&2
    exit 2
    ;;
esac

./scripts/godot-strict.sh --headless --path . --script res://tools/ranked_hv_opponent.gd
