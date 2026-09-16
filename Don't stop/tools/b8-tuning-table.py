#!/usr/bin/env python3
"""Print the LIVE Normal 21-29 tuning surface straight out of M5Content.gd.

Read-only. Exists because the B8 batch changed three knob families across four adjustment
rounds, and a reader of the report must be able to see the resulting table - and confirm that
31-40 were not touched - without trusting a hand-written summary.
"""
import re
import sys

PATH = "game/config/M5Content.gd"

FIELDS = [
    ("cap", r'"cap":(\d+)'),
    ("interval", r'"interval":([\d.]+)'),
    ("horde_simple", r'"horde_simple":([\d.]+)'),
    ("ring_min", r'"ring_min":([\d.]+)'),
    ("chase", r'"chase_speed":([\d.]+)'),
    ("elite_cap", r'"elite":\{[^}]*"cap":(\d+)\}'),
]


def grab(body, pattern, default="-"):
    found = re.search(pattern, body)
    return found.group(1) if found else default


def main():
    src = open(PATH, encoding="utf-8").read()
    hordes = {}
    block = re.search(r"const HORDES = \{(.*?)\n\}", src, re.S).group(1)
    for match in re.finditer(r"^\t(\d+):(\{.*\}),$", block, re.M):
        hordes[int(match.group(1))] = match.group(2)

    rows = {}
    for match in re.finditer(r"^\t\t(\d+):\{(\"name\".*)$", src, re.M):
        rows[int(match.group(1))] = match.group(2)

    def show(stages, title):
        print(title)
        print(f"{'st':>3} {'cap':>4} {'interval':>8} {'h_simple':>8} {'ring_min':>8} "
              f"{'chase':>5} {'elite':>5} | horde(batch,window,step,floor,windows)")
        for stage in stages:
            if stage not in rows:
                continue
            body = rows[stage]
            values = [grab(body, pattern) for _, pattern in FIELDS]
            print(f"{stage:>3} {values[0]:>4} {values[1]:>8} {values[2]:>8} {values[3]:>8} "
                  f"{values[4]:>5} {values[5]:>5} | {hordes.get(stage, '(none)')}")

    show([s for s in range(1, 31) if s in rows], "Normal 1-30 (21-29 are the B8 calibration surface):")
    print()
    show([s for s in range(31, 41) if s in rows], "Hell 31-40 (values frozen for B8):")
    return 0


if __name__ == "__main__":
    sys.exit(main())
