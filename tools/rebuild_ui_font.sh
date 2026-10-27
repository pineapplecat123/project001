#!/usr/bin/env bash
# 重建 UI 子集为 Noto Sans SC Regular 观感的 TrueType(glyf)。
# - 不用 VF 默认面（默认 wght=100=Thin，看起来更圆更细）
# - 先把 NotoSansSC-VF 实例化为 wght=400 Regular，再 subset
# - 保持 glyf，避免 Web/Pages 上 CFF 方块
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CHAR="$ROOT/tools/ui_charset.txt"
OUT="$ROOT/assets/fonts/NotoSansSC-UI.ttf"
SRC_DIR="$ROOT/tools/font_sources"
SRC_VF="$SRC_DIR/NotoSansSC-VF.ttf"
SRC_REG="$SRC_DIR/NotoSansSC-Regular-static.ttf"
SRC_URL="${NOTO_SC_VF_URL:-https://github.com/notofonts/noto-cjk/releases/download/Sans2.004/02_NotoSansCJK-TTF-VF.zip}"

python3 "$ROOT/tools/collect_ui_charset.py"
mkdir -p "$SRC_DIR"

if [[ ! -f "$SRC_VF" ]]; then
  echo "Fetching NotoSansSC-VF (TrueType variable)..."
  tmp="$(mktemp -d)"
  curl -fsSL -L -o "$tmp/ttf-vf.zip" "$SRC_URL"
  unzip -o -j "$tmp/ttf-vf.zip" 'Variable/TTF/Subset/NotoSansSC-VF.ttf' -d "$SRC_DIR"
  rm -rf "$tmp"
fi
test -f "$SRC_VF"

echo "Instantiating Regular (wght=400) static TTF from VF..."
python3 - <<'PY'
from pathlib import Path
from fontTools.ttLib import TTFont
from fontTools.varLib import instancer

root = Path(__file__).resolve().parents[1] if False else Path(".")
# script runs with cwd=ROOT via bash
vf = Path("tools/font_sources/NotoSansSC-VF.ttf")
out = Path("tools/font_sources/NotoSansSC-Regular-static.ttf")
font = instancer.instantiateVariableFont(TTFont(vf), {"wght": 400})
name = font["name"]
for nid, val in [
    (1, "Noto Sans SC"),
    (2, "Regular"),
    (4, "Noto Sans SC Regular"),
    (6, "NotoSansSC-Regular"),
    (16, "Noto Sans SC"),
    (17, "Regular"),
]:
    name.setName(val, nid, 3, 1, 0x409)
    name.setName(val, nid, 1, 0, 0)
# scrub leftover Thin strings
for rec in list(name.names):
    try:
        s = rec.toUnicode()
    except Exception:
        continue
    if "Thin" in s:
        name.names.remove(rec)
font["OS/2"].usWeightClass = 400
font.save(out)
print(f"Regular static: {out} ({out.stat().st_size} bytes), weight={TTFont(out)['OS/2'].usWeightClass}")
PY

pyftsubset "$SRC_REG" \
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
assert "glyf" in f and "CFF " not in f, "must be TrueType glyf"
w = f["OS/2"].usWeightClass
assert w == 400, f"expected Regular weight 400, got {w}"
names = []
for rec in f["name"].names:
    try:
        names.append(rec.toUnicode())
    except Exception:
        pass
assert not any("Thin" in n for n in names), f"Thin leftover in names: {names}"
print(f"OK: Regular TrueType UI font cmap={len(f.getBestCmap() or {})} weight={w} size={p.stat().st_size}")
PY

echo "Wrote $OUT ($(wc -c < "$OUT") bytes)"
python3 "$ROOT/tools/patch_font_import_for_web.py"
