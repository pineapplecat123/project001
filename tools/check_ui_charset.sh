#!/usr/bin/env bash
# 玩家可见中文必须落在 tools/ui_charset.txt 与 NotoSansSC-UI 子集内。
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
exec python3 "$ROOT/tools/check_ui_charset.py"
