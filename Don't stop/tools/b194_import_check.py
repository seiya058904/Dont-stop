"""Validate one import, including two known pre-import project boot resources.

Godot loads the custom font/cursor before importing an empty cache. Only their
exact early diagnostics may resolve during import; later/errors elsewhere fail.
The following B194Contracts runtime step loads both generated resources.
"""
import re
import sys
from pathlib import Path

SOURCES = ("Sprites/1 cursor.png", "fonts/fusion-pixel.otf")

def validate(log, root):
    allowed = set()
    generated = []
    for source in SOURCES:
        remap = root / (source + ".import")
        match = re.search(r'^path="res://([^"\n]+)"', remap.read_text(encoding="utf-8"), re.M)
        if not match:
            return ["Missing import destination: " + source]
        destination = match[1]
        generated.extend((root / source, root / destination))
        for resource in (source, destination):
            allowed.add("ERROR: Failed loading resource: res://" + resource + ".")
        allowed.add("ERROR: Unable to open file: res://" + destination + ".")
        allowed.add("ERROR: Cannot open file 'res://" + destination + "'.")
    allowed.add("ERROR: Error loading custom project font 'res://fonts/fusion-pixel.otf'")
    scanned = False
    pending = []
    failures = []
    for line in log.splitlines():
        line = re.sub(r"\x1b\[[0-9;]*m", "", line).strip()
        if "first_scan_filesystem" in line:
            scanned = True
        if not line.startswith(("ERROR:", "SCRIPT ERROR:")):
            continue
        if not scanned and line in allowed:
            pending.append(line)
        else:
            failures.append(line)
    if pending and (not scanned or not all(p.is_file() and p.stat().st_size for p in generated)):
        failures.extend(pending)
    return failures

if __name__ == "__main__":
    failures = validate(Path(sys.argv[2]).read_text(encoding="utf-8"), Path(sys.argv[1]))
    for failure in failures[:20]:
        print(failure)
    print("IMPORT_VALIDATION", "FAIL" if failures else "PASS", "errors=" + str(len(failures)))
    raise SystemExit(bool(failures))
