# B8 evidence index

Everything in this directory was produced by the frozen instrument described in
`freeze.sha256`. That file lists 19 sha256 hashes (probes, fixtures, driver, launch tooling and
the nine player-damage call sites); it was re-verified after the last batch and reported
`frozen files verified: 19, changed: 0`.

## Files

| File | What it is |
| --- | --- |
| `freeze.sha256` | The frozen instrument: base commit, validation result, and one hash per file |
| `normal-pre5-s{22,26,29}.json` | 5-seed batch against the PRISTINE 21-29 table (deliverable A.1) |
| `normal-final-s{22,26,29}.json` | The same 5 seeds against the tuned table (deliverable A.4) |
| `normal-pre-sequence-sequence.json` | The reproduction run: the B批 stage order 7/13/17/22/26/29 with the level left to grow, which reproduced "22 death, 26 death, 29 death" |
| `normal-sanity-s{21,24,25,27,28}.json` | The §14 sanity sweep, one seed each |
| `normal-quick{,2,3}-s{22,26,29}.json` | The four bounded adjustment rounds (2 seeds each); kept because they are the trend evidence behind the knob choice |
| `boss-fair-final-s30.json`, `boss-fair-final-s40-verdicts.json` | B03 x3 and B04 x3 real authored-8HP fights with the fairness verdict (deliverable B) |

## Reproducing any single number

```
tools/b8-run.ps1 -Scene B8Contracts                                  # the instrument's own contracts
tools/b8-run.ps1 -Scene B8Normal -CaseArgs @('stage=22','mode=batch','seeds=9101','pin_level=7','tag=x')
tools/b8-run.ps1 -Scene B8BossFair -CaseArgs @('stage=40','seeds=4201,4202,4203','tag=x')
tools/b8-batch.ps1 -Tag x -Levels '22:7,26:7,29:8' -Seeds '9101,9102,9103,9104,9105'
tools/b8-summary.py docs/iteration/evidence/b8 normal-final-s22 normal-final-s26 normal-final-s29
tools/b8-tuning-table.py     # the live 21-29 / 31-40 table, read straight out of M5Content.gd
tools/b8-diff-table.py       # field-by-field diff of that table against the pristine revision
```

Every launcher prints its resolved argv before starting the process and takes its arguments as
an explicit array; there is no string concatenation and no heredoc anywhere in `tools/b8-*.ps1`,
because the B批 batch lost about 21 minutes to an inline heredoc that split `--headless` into
`- - h e a d l e s s`.

## How to read the JSON rows

Each row is one real round. The fields the report quotes:

- `outcome` — `clear` / `death` / `truncated`. `truncated` is a failure of the fixture, and the
  scene asserts it never happens.
- `damage_by_tag` — the mechanism **as the call site states it**: `contact`, `line`, `cone`,
  `circle`, `artillery`, `beam`, `shot:projectile`, `control_shot:root`, `detonate`, `toxin`,
  `hazard_poison`, `hazard_laser`, `hazard_vent`, `boss_percentage`, …
- `damage_by_category` — the same damage rolled up to the brief's classification list.
- `death_snapshot` — captured **inside the damage handler** at the killing blow, so the arena is
  provably still alive. Holds the lethal event, the last 3 s of incoming attacks, the live
  footprints, the projectile count each actor family was fielding, the fog state, and the escape
  probe's verdict at that instant.
- `denial_streak_peak` / `denial_events` — consecutive 10 Hz samples in which the escape probe
  found **no** reachable point outside every footprint that was legally allowed to open. Three
  consecutive samples (0.3 s) is the confirmation threshold, the same debounce convention
  `tests/M10Density.gd` uses. This is the number the fairness verdict is built on.
- `geometric_denial_samples` / `strict_denial_samples` — the stricter variants. Outside Hell the
  fog gate is off, so all three coincide there; `B8Contracts` asserts that equivalence.
