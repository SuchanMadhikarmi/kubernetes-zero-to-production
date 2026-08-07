#!/usr/bin/env python3
"""Validate every lesson conforms to the required template sections.

Exits non-zero if any docs/*/lesson-*.md file is missing a required
section heading. Run from the repository root:

    python3 scripts/validate-lessons.py
"""
import glob
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

REQUIRED = [
    "Table of Contents",
    "Learning Objectives",
    "Prerequisites",
    "Real-world Motivation",
    "Core Concepts",
    "Architecture",
    "ASCII Diagrams",
    "Hands-on",
    "Commands",
    "YAML Explanation",
    "Production Notes",
    "Best Practices",
    "Common Mistakes",
    "Troubleshooting",
    "Interview Questions",
    "Scenario Questions",
    "Quiz",
    "Revision",
    "Cheat Sheet",
    "References",
    "Related Lessons",
    "Coming Next",
]


def main():
    lessons = sorted(glob.glob(os.path.join(ROOT, "docs", "*", "lesson-*.md")))
    failures = 0
    for path in lessons:
        name = os.path.basename(path)
        if name == "lesson-template.md":
            continue
        text = open(path, encoding="utf-8", errors="ignore").read()
        missing = [section for section in REQUIRED if ("## " + section) not in text]
        if missing:
            failures += 1
            print("[FAIL] {} missing: {}".format(name, ", ".join(missing)))
    if failures:
        print("{} lesson(s) do not conform to the template.".format(failures))
        return 1
    print("OK - all {} lessons conform to the template.".format(len(lessons)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
