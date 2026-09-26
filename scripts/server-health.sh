#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

docker compose exec -T postgres pg_isready -U postgres -d nakama >/dev/null
docker compose exec -T nakama /nakama/nakama healthcheck >/dev/null

RESPONSE="$(
  curl -fsS     -X POST     'http://127.0.0.1:7350/v2/rpc/ahoge_health?http_key=defaulthttpkey&unwrap'     -H 'Content-Type: application/json'     -H 'Accept: application/json'     -d '{}'
)"

printf '%s
' "$RESPONSE"

if ! printf '%s' "$RESPONSE" | grep -Eq '"status"[[:space:]]*:[[:space:]]*"ok"'; then
  echo "ahoge_health RPCがstatus=okを返しませんでした。" >&2
  exit 1
fi
