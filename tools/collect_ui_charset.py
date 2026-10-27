#!/usr/bin/env python3
"""Collect every char that may appear in graybox UI (scenes/scripts/data/tools)."""
from pathlib import Path
import re, json

root = Path(__file__).resolve().parents[1]
chars = set()
base = (
    "0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ"
    " !\"#$%&'()*+,-./:;<=>?@[\\]^_`{|}~"
    "×·—–…｜【】（）「」『』《》、。，：；！？％＋－＝▼▲→←◀▶↔"
    "０１２３４５６７８９"
)
chars.update(base)

def add_text(s: str) -> None:
    for ch in s or "":
        chars.add(ch)

def walk(o):
    if isinstance(o, dict):
        for v in o.values():
            walk(v)
    elif isinstance(o, list):
        for v in o:
            walk(v)
    elif isinstance(o, str):
        add_text(o)

for jp in (root / "data").glob("*.json"):
    walk(json.loads(jp.read_text(encoding="utf-8")))

text_re = re.compile(r'text\s*=\s*"((?:\\.|[^"\\])*)"')
for sp in (root / "scenes").glob("*.tscn"):
    for m in text_re.finditer(sp.read_text(encoding="utf-8")):
        add_text(m.group(1).replace("\\n", "\n"))

str_re = re.compile(r'"(?:[^"\\]|\\.)*"')
zh_re = re.compile(r"[\u4e00-\u9fff\u3000-\u303f\uff00-\uffef]+")
for sp in (root / "scripts").rglob("*.gd"):
    src = sp.read_text(encoding="utf-8")
    for m in str_re.finditer(src):
        add_text(m.group(0)[1:-1].replace("\\n", "\n"))
    for m in zh_re.finditer(src):
        add_text(m.group(0))

# tools：HTML 注入文案等也可能进 Pages
for sp in (root / "tools").rglob("*"):
    if sp.suffix.lower() not in {".py", ".sh", ".md", ".txt", ".html", ".js"}:
        continue
    if sp.name == "ui_charset.txt":
        continue
    try:
        src = sp.read_text(encoding="utf-8")
    except Exception:
        continue
    for m in zh_re.finditer(src):
        add_text(m.group(0))
    for m in str_re.finditer(src):
        add_text(m.group(0)[1:-1].replace("\\n", "\n"))

charset = "".join(sorted(chars, key=ord))
(root / "tools" / "ui_charset.txt").write_text(charset, encoding="utf-8")
print(f"charset={len(charset)} -> tools/ui_charset.txt")
