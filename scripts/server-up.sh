#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

docker compose up --build -d

echo "Nakama/PostgreSQLを起動しました。"
echo "API:     http://127.0.0.1:7350"
echo "Console: http://127.0.0.1:7351"
