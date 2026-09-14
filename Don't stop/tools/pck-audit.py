"""List the contents of a Godot 4 .pck and flag release-leakage patterns.

    python tools/pck-audit.py build/web/index.pck [more.pck ...]

Why this exists: `export_filter="all_resources"` ships every file in the project
that Godot recognised as a resource, minus the preset's exclude_filter. That set
is decided at export time from whatever happens to be on disk, so "the PCK only
contains game content" has to be measured, not assumed.

Exit code is 0 when every PCK parses and no leakage pattern matched.
"""
import re
import struct
import sys

PACK_MAGIC = 0x43504447  # "GDPC"
PACK_REL_FILEBASE = 2

# Patterns that must never reach a shipped artifact.
LEAK_PATTERNS = [
    (re.compile(r"^build/"), "generated build output re-exported into the pack"),
    (re.compile(r"(^|/)camp-v1"), "player/developer save file"),
    (re.compile(r"(^|/)config\.cfg$"), "local editor/engine config"),
    (re.compile(r"\.invalid-"), "quarantined bad-save export"),
    (re.compile(r"^evidence/"), "local evidence directory"),
    (re.compile(r"^docs/"), "documentation"),
    (re.compile(r"^tests/"), "test scenes/scripts"),
    (re.compile(r"^tools/"), "tooling"),
    (re.compile(r"screenshot", re.I), "screenshot"),
    (re.compile(r"^\.godot/editor"), "editor state"),
    (re.compile(r"\.log$"), "log file"),
]


_CONTROL = re.compile(r"[\x00-\x1f]")
_SUFFIX = re.compile(r"\.[A-Za-z0-9_]+$")


def _parse_entry_at(blob, cursor):
    """One directory entry: u32 path length, path (4-byte aligned), u64 offset,
    u64 size, 16-byte md5, u32 flags. Paths are stored WITHOUT the res:// prefix."""
    if cursor + 4 > len(blob):
        return None
    (length,) = struct.unpack_from("<I", blob, cursor)
    if not 4 <= length <= 1024:
        return None
    start = cursor + 4
    if start + length > len(blob):
        return None
    try:
        # Project paths include CJK asset names, so decode as UTF-8 rather than
        # ASCII. The stored length is already padded to 4 bytes, so the trailing
        # NULs are part of the field and must be stripped before validation.
        name = blob[start:start + length].decode("utf-8").rstrip("\x00")
    except UnicodeDecodeError:
        return None
    if not name or _CONTROL.search(name) or not _SUFFIX.search(name):
        return None
    after = start + length + (-length % 4)
    if after + 8 + 8 + 16 + 4 > len(blob):
        return None
    offset, size = struct.unpack_from("<QQ", blob, after)
    if offset >= len(blob) or size > len(blob):
        return None
    return name, offset, size, after + 8 + 8 + 16 + 4


def _chain(blob, cursor, limit=100000):
    entries = []
    while len(entries) < limit:
        parsed = _parse_entry_at(blob, cursor)
        if parsed is None:
            break
        name, offset, size, cursor = parsed
        entries.append((name, offset, size))
        if cursor >= len(blob):
            break
    return entries


def read_entries(path):
    """Return (header_fields, entries). The directory table is contiguous, so the
    real table is whichever candidate start yields the longest chain."""
    with open(path, "rb") as handle:
        blob = handle.read()
    if len(blob) < 128:
        raise ValueError("file too small to be a pack")
    (magic,) = struct.unpack_from("<I", blob, 0)
    if magic != PACK_MAGIC:
        raise ValueError("not a Godot pack (magic %08x)" % magic)

    header = struct.unpack_from("<6I", blob, 0)[1:]

    best = []
    window_start = max(0, len(blob) - 4 * 1024 * 1024)
    for cursor in range(window_start, len(blob) - 4):
        if len(blob) - cursor < len(best) * 8:
            break                       # cannot beat the incumbent
        entries = _chain(blob, cursor, limit=20000)
        if len(entries) > len(best):
            best = entries
    if len(best) < 50:
        raise ValueError("could not locate a plausible pack directory table (%d entries)" % len(best))
    if not any(name == "project.binary" for name, _, _ in best):
        raise ValueError("directory table does not contain project.binary; parse is wrong")
    return header, best


def main(argv):
    grep = None
    packs = []
    for arg in argv[1:]:
        if arg.startswith("--grep="):
            grep = re.compile(arg[len("--grep="):])
        else:
            packs.append(arg)
    if not packs:
        print(__doc__)
        return 2
    failures = 0
    for pack in packs:
        print("=== %s ===" % pack)
        try:
            version, entries = read_entries(pack)
        except Exception as exc:                      # noqa: BLE001 - report and continue
            print("  UNREADABLE: %s" % exc)
            failures += 1
            continue
        total = sum(size for _, _, size in entries)
        print("  format=%s entries=%d payload=%.2f MiB" % (version, len(entries), total / 1048576.0))
        if grep is not None:
            for name, _, size in entries:
                if grep.search(name):
                    print("    %-70s %9d" % (name, size))
        findings = []
        for name, _, size in entries:
            for pattern, reason in LEAK_PATTERNS:
                if pattern.search(name):
                    findings.append((name, size, reason))
        if findings:
            failures += 1
            print("  LEAKAGE (%d):" % len(findings))
            for name, size, reason in findings:
                print("    %-60s %9d  %s" % (name, size, reason))
        else:
            print("  no leakage patterns matched")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
