#!/usr/bin/env python3
"""check_lf.py (About Fishing F1 cloud work; Cloud, 2026-10-06)

Fails when any text file under the given root has CRLF line endings, a UTF-8 BOM, or no final newline.
A CRLF slip cost the team time on 2026-10-04 (Windows stdout redirection). Run: python check_lf.py <root>
Exit 0 = clean. Binary files and .bat files (which Windows cmd wants as CRLF) are skipped.
"""
import sys
from pathlib import Path

TEXT_EXT = {".lua", ".luau", ".py", ".md", ".json", ".txt", ".sh", ".yml", ".yaml", ".csv", ".toml", ".gitattributes", ".gitignore"}
SKIP_DIRS = {".git", "node_modules", "exports", "previews", "__pycache__"}


def main(root: str) -> int:
    bad = []
    for p in Path(root).rglob("*"):
        if any(part in SKIP_DIRS for part in p.parts):
            continue
        if not p.is_file() or p.suffix.lower() not in TEXT_EXT:
            continue
        data = p.read_bytes()
        if not data:
            continue
        if data.startswith(b"\xef\xbb\xbf"):
            bad.append((p, "UTF-8 BOM"))
        if b"\r\n" in data:
            bad.append((p, "CRLF"))
        if not data.endswith(b"\n"):
            bad.append((p, "no final newline"))
    for p, why in bad:
        print(f"  {why}: {p}")
    if bad:
        print(f"check_lf: FAIL {len(bad)}")
        return 1
    print("check_lf: PASS")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1] if len(sys.argv) > 1 else "."))
