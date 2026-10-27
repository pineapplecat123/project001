#!/usr/bin/env bash
# 安装本地 git hooks（pre-push 跑 charset/version 门禁）。
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
HOOK_DIR="$ROOT/.git/hooks"
SRC="$ROOT/tools/git-hooks/pre-push"
DST="$HOOK_DIR/pre-push"
if [[ ! -d "$HOOK_DIR" ]]; then
  echo "ERROR: $HOOK_DIR missing (not a git checkout?)" >&2
  exit 1
fi
cp -f "$SRC" "$DST"
chmod +x "$DST"
echo "OK: installed $DST -> runs tools/pre_push_check.sh"
