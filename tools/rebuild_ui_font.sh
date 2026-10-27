#!/usr/bin/env bash
# 从 Noto Sans SC（TrueType）重建 UI 子集。Web 对 CFF/OTTO 子集易出方块，故强制 glyf/TTF。
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CHAR="$ROOT/tools/ui_charset.txt"
OUT="$ROOT/assets/fonts/NotoSansSC-UI.ttf"
SRC_DIR="$ROOT/tools/font_sources"
SRC_TTF="$SRC_DIR/NotoSansSC-VF.ttf"
SRC_URL="${NOTO_SC_VF_URL:-https://github.com/notofonts/noto-cjk/releases/download/Sans2.004/02_NotoSansCJK-TTF-VF.zip}"

python3 "$ROOT/tools/collect_ui_charset.py"

mkdir -p "$SRC_DIR"
if [[ ! -f "$SRC_TTF" ]]; then
  echo "Fetching TrueType NotoSansSC-VF for subsetting..."
  tmp="$(mktemp -d)"
  curl -fsSL -L -o "$tmp/ttf-vf.zip" "$SRC_URL"
  unzip -o -j "$tmp/ttf-vf.zip" 'Variable/TTF/Subset/NotoSansSC-VF.ttf' -d "$SRC_DIR"
  rm -rf "$tmp"
fi
test -f "$SRC_TTF"

# 不使用系统 CJK TTC 的 CFF face：导出为 TrueType glyf，避免 Pages/Web 大方块
pyftsubset "$SRC_TTF" \
  --text-file="$CHAR" \
  --output-file="$OUT" \
  --layout-features='*' \
  --glyph-names --symbol-cmap --legacy-cmap \
  --notdef-glyph --notdef-outline --recommended-glyphs \
  --name-IDs='*' --name-legacy --name-languages='*' \
  --recalc-bounds --recalc-average-width

python3 - <<'PY'
from fontTools.ttLib import TTFont
from pathlib import Path
p = Path("assets/fonts/NotoSansSC-UI.ttf")
f = TTFont(p)
assert "glyf" in f, "UI font must be TrueType (glyf), not CFF"
assert "CFF " not in f, "UI font must not be CFF/OTTO"
print(f"OK: TrueType UI font cmap={len(f.getBestCmap() or {})} size={p.stat().st_size}")
PY

echo "Wrote $OUT ($(wc -c < "$OUT") bytes)"
python3 "$ROOT/tools/patch_font_import_for_web.py"
