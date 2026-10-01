#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

./scripts/server-health.sh >/dev/null

STATE_FILE="${AHOGE_FRIEND_HV_P2_DEVICE_FILE:-${TMPDIR:-/tmp}/ahoge-legend-friend-hv-p2-device-id}"

if [[ -s "$STATE_FILE" ]]; then
  DEVICE_ID="$(cat "$STATE_FILE")"
  echo "Friend Human Verification用P2の保存済みidentityを再利用します。"
else
  DEVICE_ID="$(uuidgen | tr -d '-' | tr '[:upper:]' '[:lower:]')"
  printf '%s\n' "$DEVICE_ID" > "$STATE_FILE"
  echo "Friend Human Verification用P2 identityを新規作成しました。"
fi

echo "P2 identity file: $STATE_FILE"
echo "このhelperを再実行すると同じP2 userとして再認証します。"

export AHOGE_DEVICE_ID_OVERRIDE="$DEVICE_ID"
./scripts/godot-strict.sh --path .
