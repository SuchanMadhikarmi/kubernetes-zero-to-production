#!/usr/bin/env python3
"""Check that all internal relative links in markdown files resolve.

Ignores external URLs, anchors, mailto, and images served under the
assets example. Run from the repository root:

    python3 scripts/check-links.py
"""
import glob
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LINK = re.compile(r"\]\(([^)]+)\)")


def main():
    files = [
        f
        for f in glob.glob(os.path.join(ROOT, "**", "*.md"), recursive=True)
        if ".git" not in f and "node_modules" not in f
    ]
    broken = []
    checked = 0
    for path in files:
        directory = os.path.dirname(path)
        try:
            text = open(path, encoding="utf-8", errors="ignore").read()
        except OSError:
            continue
        for match in LINK.finditer(text):
            target = match.group(1).strip()
            if target.startswith(("http://", "https://", "#", "mailto:")):
                continue
            real = target.split("#", 1)[0].strip()
            if not real:
                continue
            checked += 1
            if real == "path":  # intentional example in CONTRIBUTING.md
                continue
            if not os.path.exists(os.path.normpath(os.path.join(directory, real))):
                broken.append((os.path.relpath(path, ROOT), target))
    if broken:
        for source, target in broken:
            print("[FAIL] {} -> {}".format(source, target))
        print("{} broken link(s) out of {} checked.".format(len(broken), checked))
        return 1
    print("OK - {} links checked, none broken.".format(checked))
    return 0


if __name__ == "__main__":
    sys.exit(main())
