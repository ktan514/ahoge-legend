#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

./scripts/server-health.sh >/dev/null
./scripts/godot-import.sh

./scripts/godot-strict.sh --headless --path . --script res://tests/online_smoke.gd
