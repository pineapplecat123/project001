#!/usr/bin/env bash
# 禁止其它脚本再写 const VERSION :=（发版只改 scripts/game_version.gd）。
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

if [[ ! -f scripts/game_version.gd ]]; then
  echo "ERROR: missing scripts/game_version.gd" >&2
  exit 1
fi

if ! grep -qE 'const STRING := "[0-9]+\.[0-9]+\.[0-9]+"' scripts/game_version.gd; then
  echo "ERROR: GameVersion.STRING missing or malformed in scripts/game_version.gd" >&2
  exit 1
fi

hits="$(rg -n --glob '*.gd' --glob '!scripts/game_version.gd' '^\s*const VERSION\s*:=' scripts || true)"
if [[ -n "$hits" ]]; then
  echo "ERROR: duplicate VERSION const found (use GameVersion.STRING instead):" >&2
  echo "$hits" >&2
  exit 1
fi

echo "OK: single version source GameVersion.STRING"
