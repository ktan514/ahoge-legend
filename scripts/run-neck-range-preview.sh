#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

# 直接sceneを起動すると、初回checkout直後はclass_name cache未生成のまま
# Nakama autoloadが先にparseされることがある。先にimportしてからPreviewを起動する。
./scripts/godot-import.sh

exec godot --path . res://tools/motion_preview/NeckRangePreview.tscn
