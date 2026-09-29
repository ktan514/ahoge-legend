#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

./scripts/server-health.sh >/dev/null

MODE="${1:-auto}"
STATE_FILE="${AHOGE_HV_OPPONENT_DEVICE_FILE:-${TMPDIR:-/tmp}/ahoge-legend-ranked-hv-opponent-device-id}"

case "$MODE" in
  auto|new|reconnect)
    ;;
  *)
    echo "usage: $0 [auto|new|reconnect]" >&2
    exit 2
    ;;
esac

if [[ -s "$STATE_FILE" ]]; then
  DEVICE_ID="$(cat "$STATE_FILE")"
else
  if [[ "$MODE" == "reconnect" ]]; then
    echo "P2復帰用Device IDがありません。先に通常起動でHuman Verificationを開始してください。" >&2
    exit 1
  fi
  DEVICE_ID="$(uuidgen | tr -d '-' | tr '[:upper:]' '[:lower:]')"
  printf '%s\n' "$DEVICE_ID" > "$STATE_FILE"
fi

export AHOGE_HV_OPPONENT_MODE="$MODE"
export AHOGE_HV_OPPONENT_DEVICE_ID="$DEVICE_ID"

case "$MODE" in
  auto)
    echo "Ranked Human Verification用P2を自動判定で起動します。"
    echo "未解決matchがあれば同じP2として復帰し、なければ新規Matchmakingへ進みます。"
    ;;
  new)
    echo "Ranked Human Verification用P2を新規Matchmakingモードで起動します。"
    echo "未解決matchがある場合は上書きせず停止します。"
    ;;
  reconnect)
    echo "同じP2 userで未解決Ranked matchへ再接続します。"
    ;;
esac

./scripts/godot-strict.sh --headless --path . --script res://tools/ranked_hv_opponent.gd
