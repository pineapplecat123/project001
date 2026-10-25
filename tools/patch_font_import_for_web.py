#!/usr/bin/env python3
"""After subset rebuild: compress=false + preload full ui_charset for Web."""
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]
cs = ROOT.joinpath("tools/ui_charset.txt").read_text(encoding="utf-8")
cs = "".join(ch for ch in cs if ch not in "\n\r")
imp = ROOT / "assets/fonts/NotoSansSC-UI.ttf.import"
t = imp.read_text(encoding="utf-8").replace("compress=true", "compress=false")
esc = cs.replace("\\", "\\\\").replace('"', '\\"')
block = (
    "preload=[{\n"
    f'"chars": "{esc}",\n'
    '"glyphs": PackedInt32Array(),\n'
    '"name": "ui_all",\n'
    '"size": 16,\n'
    '"variation_embolden": 0.0,\n'
    '"variation_face_index": 0,\n'
    '"variation_transform": Transform2D(1, 0, 0, 1, 0, 0)\n'
    "}]"
)
if re.search(r"^preload=\[\]", t, re.M):
    t = re.sub(r"^preload=\[\].*$", "PRELOAD_PH", t, flags=re.M)
else:
    t = re.sub(r"preload=\[\{[\s\S]*?\}\]", "PRELOAD_PH", t, count=1)
if "PRELOAD_PH" not in t:
    raise SystemExit("cannot patch preload in font import")
imp.write_text(t.replace("PRELOAD_PH", block), encoding="utf-8")
print(f"patched font import: compress=false + preload {len(cs)} chars")
