#!/usr/bin/env python3
"""Inject a pre-engine '清理缓存并刷新' control into exported Web index.html.

Why: if an old .pck/.wasm is stuck, the in-game button never loads.
This HTML control works even when the canvas fails to boot.
"""
from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

MARKER = "<!-- project001-clear-cache -->"
SNIPPET = r'''<!-- project001-clear-cache -->
<style>
#p001-clear-cache {
  position: fixed; right: 10px; bottom: 10px; z-index: 100000;
  font: 14px/1.2 system-ui, sans-serif;
  color: #f0f3fa; background: rgba(20, 24, 36, 0.88);
  border: 1px solid rgba(140, 160, 210, 0.7); border-radius: 8px;
  padding: 8px 12px; cursor: pointer; user-select: none;
}
#p001-clear-cache:hover { background: rgba(40, 48, 72, 0.95); }
</style>
<button type="button" id="p001-clear-cache" title="清除本站缓存并强制刷新到最新版">清理缓存并刷新</button>
<script>
window.project001ClearSiteData = async function () {
  var log = function (m) { try { console.log('[project001 clear]', m); } catch (e) {} };
  try {
    (document.cookie || '').split(';').forEach(function (c) {
      var n = c.replace(/^\s+/, '').split('=')[0];
      if (!n) return;
      document.cookie = n + '=;expires=Thu, 01 Jan 1970 00:00:00 GMT;path=/';
      document.cookie = n + '=;expires=Thu, 01 Jan 1970 00:00:00 GMT;path=/;domain=' + location.hostname;
    });
    log('cookies');
  } catch (e) { log(e); }
  try { localStorage.clear(); log('localStorage'); } catch (e) {}
  try { sessionStorage.clear(); log('sessionStorage'); } catch (e) {}
  try {
    if (window.caches && caches.keys) {
      var keys = await caches.keys();
      await Promise.all(keys.map(function (k) { return caches.delete(k); }));
      log('caches ' + keys.length);
    }
  } catch (e) {}
  try {
    if (navigator.serviceWorker && navigator.serviceWorker.getRegistrations) {
      var regs = await navigator.serviceWorker.getRegistrations();
      await Promise.all(regs.map(function (r) { return r.unregister(); }));
      log('sw ' + regs.length);
    }
  } catch (e) {}
  try {
    if (window.indexedDB && indexedDB.databases) {
      var dbs = await indexedDB.databases();
      await Promise.all((dbs || []).map(function (db) {
        return new Promise(function (resolve) {
          if (!db || !db.name) { resolve(); return; }
          var req = indexedDB.deleteDatabase(db.name);
          req.onsuccess = req.onerror = req.onblocked = function () { resolve(); };
        });
      }));
      log('idb');
    }
  } catch (e) {}
  try {
    var u = new URL(location.href);
    u.searchParams.set('nocache', String(Date.now()));
    location.replace(u.toString());
  } catch (e) {
    location.reload();
  }
};
document.getElementById('p001-clear-cache').addEventListener('click', function () {
  window.project001ClearSiteData();
});
</script>
'''


def inject(html_path: Path) -> bool:
    text = html_path.read_text(encoding="utf-8")
    if MARKER in text:
        # replace existing block (idempotent)
        text = re.sub(
            re.escape(MARKER) + r".*?</script>\s*",
            SNIPPET,
            text,
            count=1,
            flags=re.S,
        )
    else:
        if "</body>" in text:
            text = text.replace("</body>", SNIPPET + "\n</body>", 1)
        else:
            text = text + "\n" + SNIPPET
    html_path.write_text(text, encoding="utf-8")
    return MARKER in html_path.read_text(encoding="utf-8")


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("html", type=Path, help="path to exported index.html")
    args = ap.parse_args()
    if not args.html.is_file():
        print(f"ERROR: missing {args.html}", file=sys.stderr)
        return 1
    ok = inject(args.html)
    print(f"{'OK' if ok else 'FAIL'}: injected clear-cache into {args.html}")
    return 0 if ok else 2


if __name__ == "__main__":
    raise SystemExit(main())
