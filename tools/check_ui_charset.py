#!/usr/bin/env python3
"""Ensure UI charset + subset font cover every player-visible char.

Fails non-zero when:
  - tools/ui_charset.txt is stale vs fresh collect from data/scenes/scripts
  - assets/fonts/NotoSansSC-UI.ttf is missing any required glyph
  - .godot/imported/NotoSansSC-UI.ttf-*.fontdata exists but is older/smaller than source TTF

Usage:
  python3 tools/check_ui_charset.py
  bash tools/check_ui_charset.sh
"""
from __future__ import annotations

import json
import re
import sys
from pathlib import Path

try:
    from fontTools.ttLib import TTFont
except ImportError:
    print("ERROR: fonttools required (pip install fonttools)", file=sys.stderr)
    sys.exit(2)

ROOT = Path(__file__).resolve().parents[1]
CHARSET_PATH = ROOT / "tools" / "ui_charset.txt"
FONT_PATH = ROOT / "assets" / "fonts" / "NotoSansSC-UI.ttf"

BASE = (
    "0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ"
    " !\"#$%&'()*+,-./:;<=>?@[\\]^_`{|}~"
    "×·—–…｜【】（）「」『』《》、。，：；！？％＋－＝▼▲→←◀▶↔"
    "０１２３４５６７８９"
)


def collect_chars() -> set[str]:
    chars: set[str] = set(BASE)

    def add_text(s: str) -> None:
        for ch in s or "":
            chars.add(ch)

    def walk(o) -> None:
        if isinstance(o, dict):
            for v in o.values():
                walk(v)
        elif isinstance(o, list):
            for v in o:
                walk(v)
        elif isinstance(o, str):
            add_text(o)

    for jp in (ROOT / "data").glob("*.json"):
        walk(json.loads(jp.read_text(encoding="utf-8")))

    text_re = re.compile(r'text\s*=\s*"((?:\\.|[^"\\])*)"')
    for sp in (ROOT / "scenes").glob("*.tscn"):
        for m in text_re.finditer(sp.read_text(encoding="utf-8")):
            add_text(m.group(1).replace("\\n", "\n"))

    str_re = re.compile(r'"(?:[^"\\]|\\.)*"')
    zh_re = re.compile(r"[\u4e00-\u9fff\u3000-\u303f\uff00-\uffef]+")
    for sp in (ROOT / "scripts").rglob("*.gd"):
        src = sp.read_text(encoding="utf-8")
        for m in str_re.finditer(src):
            add_text(m.group(0)[1:-1].replace("\\n", "\n"))
        for m in zh_re.finditer(src):
            add_text(m.group(0))

    return chars


def font_cmap_codepoints(path: Path) -> set[int]:
    font = TTFont(str(path))
    cmap: dict[int, str] = {}
    for table in font["cmap"].tables:
        cmap.update(table.cmap)
    return set(cmap.keys())


def main() -> int:
    errors = 0
    expected = collect_chars()
    expected_str = "".join(sorted(expected, key=ord))

    if not CHARSET_PATH.is_file():
        print(f"ERROR: missing {CHARSET_PATH}", file=sys.stderr)
        return 1
    committed = CHARSET_PATH.read_text(encoding="utf-8")
    if committed != expected_str:
        only_code = sorted(set(committed) - expected, key=ord)
        only_fresh = sorted(expected - set(committed), key=ord)
        print("ERROR: tools/ui_charset.txt is stale vs data/scenes/scripts.", file=sys.stderr)
        if only_fresh:
            print(f"  missing from charset.txt ({len(only_fresh)}): {''.join(only_fresh)}", file=sys.stderr)
        if only_code:
            print(f"  extra in charset.txt ({len(only_code)}): {''.join(only_code)}", file=sys.stderr)
        print("  Fix: python3 tools/collect_ui_charset.py && bash tools/rebuild_ui_font.sh", file=sys.stderr)
        errors += 1

    if not FONT_PATH.is_file():
        print(f"ERROR: missing {FONT_PATH}", file=sys.stderr)
        return 1

    covered = font_cmap_codepoints(FONT_PATH)
    # Control/whitespace often absent or irrelevant in subset cmap.
    skip = set("\n\r\t")
    missing = sorted(
        (c for c in expected if c not in skip and ord(c) not in covered),
        key=ord,
    )
    if missing:
        print(
            f"ERROR: NotoSansSC-UI.ttf missing {len(missing)} glyph(s): {''.join(missing)}",
            file=sys.stderr,
        )
        print("  Fix: bash tools/rebuild_ui_font.sh", file=sys.stderr)
        errors += 1

    # Stale Godot import cache can still show tofu even when source TTF is OK.
    import_dir = ROOT / ".godot" / "imported"
    if import_dir.is_dir():
        caches = sorted(import_dir.glob("NotoSansSC-UI.ttf-*.fontdata"))
        if caches:
            src_mtime = FONT_PATH.stat().st_mtime
            src_size = FONT_PATH.stat().st_size
            for cache in caches:
                st = cache.stat()
                # fontdata slightly larger than source TTF is normal; flag clear lag/shrink.
                stale_mtime = st.st_mtime + 1.0 < src_mtime  # allow 1s clock skew
                too_small = st.st_size + 4096 < src_size  # more than ~4KB smaller than source
                if stale_mtime or too_small:
                    print(
                        "ERROR: Godot import cache for NotoSansSC-UI looks stale vs source TTF.",
                        file=sys.stderr,
                    )
                    print(
                        f"  source: {FONT_PATH.name} size={src_size} mtime={src_mtime:.0f}",
                        file=sys.stderr,
                    )
                    print(
                        f"  cache:  {cache.name} size={st.st_size} mtime={st.st_mtime:.0f}",
                        file=sys.stderr,
                    )
                    print(
                        "  Fix: rm .godot/imported/NotoSansSC-UI.ttf-* && godot --headless --path . --import",
                        file=sys.stderr,
                    )
                    errors += 1
        else:
            print(
                "WARN: no .godot/imported/NotoSansSC-UI.ttf-*.fontdata yet "
                "(run godot --import before screenshots / Web export).",
                file=sys.stderr,
            )

    if errors:
        return 1
    print(f"OK: UI charset ({len(expected_str)} chars) covered by subset font")
    return 0


if __name__ == "__main__":
    sys.exit(main())
