#!/usr/bin/env python3
"""Field-by-field diff of the 21-29 encounter table against a pristine revision.

Written after a B8 edit script used a generic `"interval":...` substitution and silently
rewrote the `elite.interval` field as well, because both keys live on the same line. A
line-level diff would have shown "6 lines changed" and looked fine. This compares the parsed
FIELDS, so a field that was collateral damage cannot hide.
"""
import os
import re
import subprocess
import sys

REL = "Don't stop/game/config/M5Content.gd"
FIELDS = ["cap", "interval", "rhythm", "elite", "pressure", "roles", "seconds", "region", "boss"]


def locate():
    """Resolve the file whether the script is run from the repo root or from `Don't stop`."""
    for candidate in (REL, "game/config/M5Content.gd"):
        if os.path.exists(candidate):
            return candidate
    raise SystemExit(f"cannot find {REL}")


def parse(text):
    table = {}
    for match in re.finditer(r"^\t\t(\d+):\{(.*)$", text, re.M):
        table[int(match.group(1))] = match.group(2).rstrip("\r")
    return table


def field(body, name):
    pattern = re.compile(r'"%s":(\{.*?\}|\[.*?\]|"[^"]*"|[^,}]+)' % name)
    found = pattern.search(body)
    return found.group(1) if found else None


def main():
    path = locate()
    pristine = subprocess.run(["git", "show", f"HEAD:{REL}"], capture_output=True, text=True,
                              encoding="utf-8").stdout
    with open(path, encoding="utf-8", newline="") as handle:
        live = handle.read()
    before, after = parse(pristine), parse(live)
    changed = 0
    for stage in sorted(after):
        if not (21 <= stage <= 40):
            continue
        if stage not in before:
            continue
        for name in FIELDS:
            old, new = field(before[stage], name), field(after[stage], name)
            if old != new:
                changed += 1
                print(f"stage {stage:>2} {name:>9}: {old}  ->  {new}")
    print(f"\n{changed} field changes across stages 21-40")
    return 0


if __name__ == "__main__":
    sys.exit(main())
