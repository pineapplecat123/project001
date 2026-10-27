#!/usr/bin/env python3
"""After subset rebuild: compress=false + preload full ui_charset at common UI sizes for Web."""
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]
cs = ROOT.joinpath("tools/ui_charset.txt").read_text(encoding="utf-8")
cs = "".join(ch for ch in cs if ch not in "\n\r")
imp = ROOT / "assets/fonts/NotoSansSC-UI.ttf.import"
t = imp.read_text(encoding="utf-8").replace("compress=true", "compress=false")
esc = cs.replace("\\", "\\\\").replace('"', '\\"')
# 预加载常用字号：主题默认 18，按钮/标题常见到 52；仅 16 时 Web 易缺光栅
sizes = [12, 14, 16, 18, 20, 22, 26, 32, 52]
entries = []
for sz in sizes:
    entries.append(
        "{\n"
        f'"chars": "{esc}",\n'
        '"glyphs": PackedInt32Array(),\n'
        f'"name": "ui_{sz}",\n'
        f'"size": {sz},\n'
        '"variation_embolden": 0.0,\n'
        '"variation_face_index": 0,\n'
        '"variation_transform": Transform2D(1, 0, 0, 1, 0, 0)\n'
        "}"
    )
block = "preload=[" + ",\n".join(entries) + "]"
if re.search(r"^preload=\[\]", t, re.M):
    t = re.sub(r"^preload=\[\].*$", "PRELOAD_PH", t, flags=re.M)
else:
    t = re.sub(r"preload=\[\{[\s\S]*?\}\]", "PRELOAD_PH", t, count=1)
    # if previous multi-entry preload, replace whole preload=[...]
    if "PRELOAD_PH" not in t:
        t = re.sub(r"preload=\[[\s\S]*?\]\nlanguage_support", "PRELOAD_PH\nlanguage_support", t, count=1)
if "PRELOAD_PH" not in t:
    raise SystemExit("cannot patch preload in font import")
imp.write_text(t.replace("PRELOAD_PH", block), encoding="utf-8")
print(f"patched font import: compress=false + preload {len(cs)} chars x {len(sizes)} sizes")
