#!/usr/bin/env python3
"""Stamp a built Web export with its own identity, and record that identity.

usage: stamp-build-identity.py <buildDir> <buildSha> [identityOutJson]

Two identities are written into <buildDir>/index.html:

  dontstop-build     the commit the build came from
  dontstop-artifact  sha256 over index.wasm || index.pck || index.js

The second is the one that answers "did we test A and deploy B". It is a
function of the payload bytes alone, so a rebuild - even of the same commit -
changes it, and a deployed page that carries it can be matched, byte for byte,
against the artifact the gates actually ran on.

The identity is also written to a JSON file, and - when the GitHub Actions
environment files are present - exported to $GITHUB_OUTPUT as `digest` and to
$GITHUB_ENV as ARTIFACT_DIGEST. Keeping this in one script means a local run and
the workflow use the same implementation instead of two that can drift.
"""
import hashlib
import json
import os
import pathlib
import sys

PAYLOAD = ["index.wasm", "index.pck", "index.js"]


def main() -> int:
    if len(sys.argv) < 3:
        print("usage: stamp-build-identity.py <buildDir> <buildSha> [identityOutJson]", file=sys.stderr)
        return 2
    build = pathlib.Path(sys.argv[1])
    sha = sys.argv[2]
    identity_out = pathlib.Path(sys.argv[3]) if len(sys.argv) > 3 else None

    files, rolling = {}, hashlib.sha256()
    for name in PAYLOAD:
        path = build / name
        if not path.is_file():
            print("missing payload file: %s" % path, file=sys.stderr)
            return 1
        data = path.read_bytes()
        files[name] = {"bytes": len(data), "sha256": hashlib.sha256(data).hexdigest()}
        rolling.update(data)
    digest = rolling.hexdigest()

    page = build / "index.html"
    html = page.read_text(encoding="utf-8")
    for meta in ("dontstop-build", "dontstop-artifact"):
        if meta in html:
            print("refusing to stamp twice: %s is already in %s" % (meta, page), file=sys.stderr)
            return 1
    stamp = ('<meta name="dontstop-build" content="%s" />\n'
             '<meta name="dontstop-artifact" content="%s" />\n') % (sha, digest)
    page.write_text(html.replace("</head>", stamp + "</head>", 1), encoding="utf-8")

    identity = {
        "build_sha": sha,
        "artifact_digest": digest,
        "digest_algo": "sha256(index.wasm || index.pck || index.js)",
        "payload": files,
    }
    if identity_out:
        identity_out.parent.mkdir(parents=True, exist_ok=True)
        identity_out.write_text(json.dumps(identity, indent=2) + "\n", encoding="utf-8")

    if os.environ.get("GITHUB_OUTPUT"):
        with open(os.environ["GITHUB_OUTPUT"], "a", encoding="utf-8") as fh:
            fh.write("digest=%s\n" % digest)
    if os.environ.get("GITHUB_ENV"):
        with open(os.environ["GITHUB_ENV"], "a", encoding="utf-8") as fh:
            fh.write("ARTIFACT_DIGEST=%s\n" % digest)

    print("build_sha       %s" % sha)
    print("artifact_digest %s" % digest)
    for name, info in files.items():
        print("  %-10s %9d  %s" % (name, info["bytes"], info["sha256"]))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
