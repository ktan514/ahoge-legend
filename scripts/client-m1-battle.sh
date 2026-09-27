#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

./scripts/server-health.sh >/dev/null
./scripts/godot-import.sh
./scripts/godot-strict.sh --path . -- --m1-battle
