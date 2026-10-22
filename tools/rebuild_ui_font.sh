#!/usr/bin/env bash
# 从系统 Noto Sans CJK SC 重建 UI 子集字体。先跑 collect 逻辑见同目录说明。
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="${NOTO_CJK_TTC:-/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc}"
CHAR="$ROOT/tools/ui_charset.txt"
OUT="$ROOT/assets/fonts/NotoSansSC-UI.ttf"
python3 "$ROOT/tools/collect_ui_charset.py"
pyftsubset "$SRC" \
  --font-number=2 \
  --text-file="$CHAR" \
  --output-file="$OUT" \
  --layout-features='*' \
  --glyph-names --symbol-cmap --legacy-cmap \
  --notdef-glyph --notdef-outline --recommended-glyphs \
  --name-IDs='*' --name-legacy --name-languages='*' \
  --recalc-bounds --recalc-average-width
echo "Wrote $OUT ($(wc -c < "$OUT") bytes)"
