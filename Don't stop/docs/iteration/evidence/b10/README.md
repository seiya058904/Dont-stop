# B10 evidence index — Hell playtest access + special enemy threat revision

Everything here was produced by the frozen instrument listed in `freeze.sha256`. Only this index
and the generated files are hand-written.

## Part 1 — Hell playtest access

| file | what it is |
| --- | --- |
| `browser/web-hell-playtest-e2e.json` | the browser acceptance's full token list, phase timings, the game's own reported control rectangles, and the console/page/network error audit |
| `browser/*.png` | real screenshots: the formal Hell section locked, the playtest selector, each Hell stage entered, and the return to camp |
| `normal-*.json` | (B9) not used here |

The blocker and its cause are recorded in `docs/iteration/B10-HELL-PLAYTEST-THREAT.md` §1.

## Part 2 — Special enemy threat

| file | what it is |
| --- | --- |
| `threat-baseline.json` | SpecialThreatAudit on the UNCHANGED enemy behaviour: every special attack, three scenarios, 4 trials each |
| `threat-final.json` | the same audit after the threat revision, same stage, same trials |
| `threat-check.json` | the run that proves movement really changes the outcome (a run where the Hero's physics was accidentally left disabled reported all three scenarios identical, which is how that trap was noticed) |

`threat-*.json` is written by `tests/B10Threat.gd`, which departs a real stage as a trial and, for
each enemy, clears the arena, places the player back at the round's own spawn point, spawns
exactly one actor and runs one scenario for a fixed window. Hits are counted on
`Hero.damage_taken` and attributed to the actor under test by instance id; anything else is
reported as `foreign_hits` rather than credited.

Scenario definitions:

* **standing** — no movement input at all.
* **strafe** — one direction held at full speed for the whole trial, chosen as the direction with
  the most clearance so the trial measures the attack and not a wall.
* **dodge** — the real B9 movement core (`M8Runtime.choose_safe_movement`), the same 16-direction
  danger scan both the boss driver and the ordinary-stage driver use.

## How to reproduce

```
cd "Don't stop"
pwsh -NoProfile -File tools/b10-run.ps1 -Scene B10Playtest
pwsh -NoProfile -File tools/b10-run.ps1 -Scene B10Threat -Args 'trials=4,tag=baseline,stage=24'
pwsh -NoProfile -File tools/b10-web-export.ps1
node tools/b10-static-server.js build/web 8199
node tools/web-hell-playtest-e2e.js http://127.0.0.1:8199/ docs/iteration/evidence/b10/browser
```
