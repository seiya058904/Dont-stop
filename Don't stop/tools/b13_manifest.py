#!/usr/bin/env python3
"""Regenerate the B13 growth-benchmark measurement-input manifest.

The required set is parsed out of tests/B13Strength.gd (REQUIRED_MEASUREMENT_INPUTS),
so the generator and the verifier share one source of truth and cannot drift: if the
test's list changes, rerun this script before re-freezing the evidence.

Hashes are LF-normalised SHA-256 over the whole file, matching
B13Strength.sha256_lf() (every 0x0D byte is dropped, so the digest does not depend on
the checkout's autocrlf).

Usage:  python tools/b13_manifest.py
"""
import hashlib
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
STRENGTH = ROOT / "tests" / "B13Strength.gd"
MANIFEST = ROOT / "docs" / "iteration" / "evidence" / "b13" / "manifest.json"


def required_set() -> list:
    text = STRENGTH.read_text(encoding="utf-8")
    block = re.search(r"const REQUIRED_MEASUREMENT_INPUTS := \[(.*?)\n\]", text, re.S)
    if not block:
        sys.exit("REQUIRED_MEASUREMENT_INPUTS not found in tests/B13Strength.gd")
    paths = sorted(set(re.findall(r'"([^"]+)"', block.group(1))))
    if not paths:
        sys.exit("no paths parsed from REQUIRED_MEASUREMENT_INPUTS")
    missing = [p for p in paths if not (ROOT / p).is_file()]
    if missing:
        sys.exit("required measurement inputs missing on disk:\n  " + "\n  ".join(missing))
    return paths


def sha256_lf(path: Path) -> str:
    return hashlib.sha256(path.read_bytes().replace(b"\r", b"")).hexdigest()


def main() -> None:
    entries = [{"path": rel, "sha256": sha256_lf(ROOT / rel)} for rel in required_set()]
    MANIFEST.write_text(json.dumps(entries, indent=1) + "\n", encoding="utf-8")
    print(f"wrote {len(entries)} manifest entries -> {MANIFEST.relative_to(ROOT.parent)}")


if __name__ == "__main__":
    main()
