# B11.2 evidence

Every number in `docs/iteration/B11.2-HIGH-LOAD-PERFORMANCE.md` is derived from this directory.
Nothing here was edited by hand after the runs.

```
build-identity-before.json   sha256 of the three files the browser loaded, BEFORE build
build-identity-after.json    ... and AFTER
summary-source.py            the generator: recomputes every table in the report
summary.md                   its output (generated, do not hand-edit)
stress/before/               BEFORE: 4 core profiles x 2 reps, + 7 visual-isolation runs
stress/after/                AFTER:  the same 15 runs
native/                      native headless suite logs (one per scene)
browser/                     the six CI browser gates: their console output and JSON
visual/                      tests/B11ZoneVisual logs, headless and windowed gl_compatibility
```

Recompute everything:

```bash
python docs/iteration/evidence/b11_2/summary-source.py docs/iteration/evidence/b11_2
```

## Notes that matter for reading the numbers

* **Which build is which.** `stress/before/` was produced by `main` + the test-only probe.
  `stress/after/` was produced by the optimised source, re-exported after the `decor`-gate fix
  described in the report's section 4. `build-identity-*.json` records the sha256 of the bytes the
  browser actually loaded, and every run in a directory shares that side's identity.
* **A first AFTER build was discarded.** Identity `dc9c264d0e15…` was exported and measured before
  that fix was found. Its runs are not in this tree at all, because they describe a source revision
  that is not the delivered one. The delivered AFTER build is `7c61d0724ab7…`.
* **The isolation runs are self-contained.** Each `stress-<side>-iso-<flag>-D.json` is the same
  worst-load profile with exactly ONE purely-visual product switched off (`none` = all on). They are
  a within-side attribution experiment, not a before/after comparison.
* **Counts are per second of measured combat**, not per run: the runs are wall-clock bound and the
  shot count differs between them.
* **`fog_draws` / `fog_entries_drawn` / `fog_draw_usec` / `fog_scans` exist only in AFTER.**
  The B11.1 probe did not have them, so there is no same-instrument BEFORE reading for those four;
  section 3.3 of the report therefore compares the zone tier as `draw + step`, because BEFORE paid
  the fog push inside `_draw()` and AFTER pays it inside `step()`.
