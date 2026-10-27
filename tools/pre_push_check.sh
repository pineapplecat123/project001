#!/usr/bin/env bash
# push / 发版前门禁：版本单一来源 + UI 字符集覆盖（缺字禁止推）。
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
echo "== pre-push: check_version =="
bash tools/check_version.sh
echo "== pre-push: check_ui_charset =="
bash tools/check_ui_charset.sh
echo "OK: pre-push checks passed"
