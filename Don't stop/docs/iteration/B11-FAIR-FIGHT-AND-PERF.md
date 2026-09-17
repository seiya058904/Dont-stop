# B11 — Free Stage Select, Fair Attacks, Hell Rework, Stage 39/40 Performance

**Base commit:** `d97290e50f6fbacbd498a5d87b97cdd9022aeafd` (`origin/main` at the start of this batch)
**Branch:** `b11-fair-fight-and-perf`

状态：`HUMAN_ACCEPTED=false` · `WEB_HUMAN_ACCEPTED=false` · `EXTERNAL_REVIEW_PENDING=true`

---

## 1. What this batch changes, in one screen

| | before B11 | after B11 |
|---|---|---|
| stage selection | two selectors: a "HELL PLAYTEST / 地狱试玩" review entry, plus a formal 31–40 block whose entries were `disabled` and labelled `未解锁` on any save that had not cleared Stage 30 | **ONE** list, 1–40, every entry a real enabled control, no suffix that names a state |
| replay semantics | a playtest departure was a TRIAL departure, so clearing Stage 40 through it recorded nothing | a stage-list departure is a REPEAT departure: it never moves the campaign pointer, and it never claims a completion |
| save handling | `normalize()` rewrote `selected_stage` to 30 for any unfinished save | the table (1–40) bounds a save; progress does not. The 30→31 migration for a completed campaign is kept |
| attack aiming | aim followed the player for 55 % of the warning, then froze carrying a 0.15–0.35 s LEAD of the player's velocity | a short TRACK, then a FREEZE with a lead bounded by a **computed** escape budget |
| laser | at Stage 39 numbers, the lead consumed the whole escape time: standing still on the centreline left ~1 px of margin, and moving along the beam left none | the freeze happens at 0.35 s, the target kind's warning is lengthened until the computed interval fits after it, and the frozen geometry is what fires |
| contact damage | each attacker owned its own 0.8–0.85 s cooldown, so fifty bodies in contact meant fifty hits on one frame | one player-side window (0.6 s) covers the two footprint-less sources; telegraphs are untouched |
| Hell 31–40 caps | 72 · 80 · 88 · 96 · 105 · 114 · 124 · 134 · 146 | 52 · 56 · 60 · 64 · 68 · 72 · 76 · 80 · 84 |
| hotspot cost | `nearest()` scanned all ~677 walkable cells; every spawn candidate allocated two physics objects | bounded ring search over a walkable set; cached query objects; the grid's own answer used for default-size actors |

---

## 2. The stage table is the selectability contract

`ui/CampPanel.gd` now renders one list:

* `stage_list()` draws `关卡选择 1—40` and calls `stage_entries(1,40)` once. There is no second
  selector and no block heading that implies one.
* `stage_entries()` has no `locked` branch and appends no state suffix. Its only per-row label work is
  the region heading every five rows.
* `stage_unlocked(stage)` survives because the save format and audits still call it. Its meaning is
  now "does this stage exist", so it answers `true` for 1–40 on an empty save. `--hell-unlock` is gone
  with the gate it bypassed.
* `depart(stage)` refuses for exactly two real reasons (no equipped weapon, a round already running)
  plus an unknown stage. There is no stage-permission refusal left in the product.
* `depart_campaign()` is the one entry that still writes progression; it is what the `继续` row calls.

`game/config/CampSnapshot.gd`:

* `selected_stage` and `next_stage` are clamped into the real table (1–40) and nothing else.
* The historical 30→31 migration is kept for a save that had already completed the normal campaign.
* The old clamps are removed, with the reason written next to the code: an unfinished save holding a
  Hell selection is a state the product now accepts, and rewriting it was the data-path half of a lock
  that no longer exists.

Stage 40 termination is unchanged and still positional:
`LevelServer.victory()` advances by table index and clamps to the last entry, and no code path can
name Stage 41. `tests/B11Stages.gd` asserts both the clamp and "stage 40's own advance stays at 40".

**Honest note:** a direct stage choice does not advance the campaign pointer, and clearing Stage 40
through one does not set `hell_complete`. That keeps repeat challenges from silently writing story
progress, which is what the B10 playtest mechanism was originally trying to express. If the intended
rule is instead "clearing any stage writes progress", that is a one-line change in
`CampPanel._depart_with()` and should be confirmed by the reviewer.

---

## 3. The attack lock: TRACK → LOCK → WARNING → FIRE → RECOVER

One implementation, in `game/monster/DemoEnemy.gd` (the base of both rosters, so they cannot drift).
Constants and the derivation from this build's own numbers are written in the file; the short version:

```
playable radius r = half_extent + PLAYER_RADIUS(7)
escape            = r / (SPEED * cos45)
reaction          = HUMAN_REACTION(0.25) + escape * REACTION_SAFETY(1.2)
warning           = TRACK_SECONDS(0.35) + reaction
lead_cap          = escape - escape * REACTION_SAFETY * LEAD_FRACTION(0.5)
```

* `SPEED` is read from `Utils.player.SPEED`, not assumed.
* `PLAYER_RADIUS` is asserted against the live `CollisionShape2D` by the audit.
* `cos45` is used because an escape at 45° to the beam covers the clearance with only cos(45) of the
  travelled distance; bounding the window by the perpendicular case alone would leave that case short.
* `begin_lock()` **extends** a warning that is too short rather than shortening the window, so an edit
  cannot author an undodgeable attack back in.
* `step_lock()` calls `refresh_zones()` only while the aim is still tracking. From the freeze onward
  the target point, direction, angle, swept arc and clipped length are frozen, and `FIRE` uses them.
* The lead survives because a stationary player must not be able to ignore a telegraph forever, but it
  may only spend the safety margin. Charges and dashes carry **zero** lead.
* `aim_state()` exposes the lock read-only for the audit and the browser probe.

Per-family geometry (lane widths, radii) lives in `TacticalEnemy.clearance()`, which mirrors the
damage test each footprint really uses, and every footprint's own countdown is derived from
`freeze_after()` rather than from a literal, so a telegraph cannot outlive or undercut the wind-up it
belongs to.

Other fairness fixes in the same pass:

* charges and dashes now deal their damage **through the frozen lane** instead of re-testing distance
  at the actor, so the region that damages is the region the warning drew;
* the Stage-gate `shockwave` was two concentric rings 0.5 s apart, which could not be left from the
  centre by any movement - it is now one ring sized to its own wind-up;
* `lockdown`'s three marks each carry their own full warning instead of stacking inside one another's
  reaction interval;
* `E06`'s self-destruct fuse is a readable interval and its blast is at the actor's own feet;
* `E14` / `cross` / `cross_laser` lanes set `pierce`, so Hell's fog cannot hide the direction of a lane
  that starts outside the lit radius;
* the duplicate `CombatTelegraph.paint()` overlays in `DemoEnemy._draw()` - decorative lanes drawn 108
  and 150 px long against real zones of hundreds of pixels - are gone.

---

## 4. Hell 31–40

| stage | cap | interval | elite (start/interval/cap) | ring_min | chase |
|---|---|---|---|---|---|
| 31 | 52 | 0.34 | 22 / 15 / 1 | 120 | 1.10 |
| 32 | 56 | 0.33 | 21 / 14 / 1 | 119 | 1.10 |
| 33 | 60 | 0.32 | 20 / 13 / 2 | 118 | 1.11 |
| 34 | 64 | 0.31 | 19 / 13 / 2 | 116 | 1.12 |
| 35 | 68 | 0.30 | 18 / 12 / 2 | 115 | 1.12 |
| 36 | 72 | 0.29 | 17 / 12 / 2 | 114 | 1.13 |
| 37 | 76 | 0.28 | 16 / 11 / 3 | 113 | 1.14 |
| 38 | 80 | 0.27 | 15 / 11 / 3 | 112 | 1.14 |
| 39 | 84 | 0.26 | 14 / 10 / 3 | 110 | 1.15 |
| 40 | 24 (boss) | 1.40 | — | — | — |

Rosters, regions, rhythms, fog profiles, hazard plans and the boss are unchanged. `HellMode`'s axes
stay linear and bounded, and its 2^10 `threat_index` remains a reporting-only constant that is never
applied to gameplay.

Contact damage in Hell now uses `CONTACT_DAMAGE_WEIGHT_HELL` (0.35) instead of the normal 0.5, paired
with the player-side window. Telegraph damage is **not** damped: standing in a marked, warned, frozen
footprint still pays what the footprint says.

---

## 5. Performance

### 5.1 Measurements

* **Native (this machine, headless, real physics at 60 Hz)** — `tests/B11Perf.gd`, the real stage, the
  real spawn director, the real hazard director, 75 s per stage. Node and frame numbers only; headless
  has no renderer, so only the frame *cost* is meaningful there.
* **Browser (local Chromium, `--use-angle=d3d11`, real GPU `AMD Radeon RX 7900 XT`)** — the same rig
  through `?perf=1&stage=N&seconds=N`, measuring the game's own frame deltas.
* CI's `gl_compatibility` software renderer is **not** used as performance evidence anywhere.

### 5.2 Hotspots, with the fix each one got

| hotspot | why it scales with the crowd | fix |
|---|---|---|
| `Arena.nearest()` | linear scan of ~677 walkable cells, called from `path_step()` for every monster whose cell the conservative AI grid calls solid - i.e. every wall-hugger, at 5 Hz | bounded ring search over a precomputed walkable set: one dictionary lookup in the common case. **A clamped-index shortcut is NOT valid here** and was caught by `tests/R3SpawnAudit.gd` (78 illegal births, because A* cannot path out of a solid cell) |
| `_is_clear()` / `point_clear()` / `_nav_point_clear()` | allocated a `CircleShape2D` + `PhysicsShapeQueryParameters2D` per call, and `spawn_near()` calls them per candidate cell - up to ~677 allocations for ONE reinforcement | cached per quantised radius; the grid's own answer is used when the actor is no larger than the grid's clearance |
| `nearest()` / `spawn_*` path queries | `get_id_path()` per candidate | unchanged in kind, but far fewer candidates reach it, because the early-out above removes the query for default-size actors |
| `HostileZone._draw()` | `get_nodes_in_group("hostile_zone").size()` per drawn zone per frame | one static sample every six frames |
| `Town.build_navigation()` | one physics query per cell for 1972 cells at scene load, including cells with no ground | cells without ground are already solid; the query is skipped for them, and the shape/query objects are reused |
| `FogPierce` | each frame's list is capped at 128 pushes, and a crowded Hell frame can fill it | the informative long lane is pushed before its decorative bright core, so the cap can only cost ink, never information |

### 5.3 BEFORE / AFTER raw data

Raw data is in `docs/iteration/evidence/b11/` (`perf-before-*.json`, `perf-after-*.json`,
`web-perf-before-*.json`, `web-perf-after-*.json`). The report quotes the numbers verbatim; see the
delivery report for the tables, since they are generated from the runs and not typed by hand.

---

## 6. What this batch did NOT do

* No weapon rarity / tier redesign, no weapon stat rework, no enchant rework, no talent rework
  (B12 / B13).
* No release, no tag, no merge to `main`, no Pages deploy.
* No change to Stages 1–30's encounter tables, rosters, caps or hazard plans.
* No deletion of the difficulty *axes*: `HellMode` still describes HP / damage / speed / density
  ramps. What changed is the encounter caps those axes are applied to.

## 7. Verification boundary

`tests/B11Stages.gd` (57 checks), `tests/B11Fairness.gd` (61 checks) and `tests/B11Perf.gd` are the
automated half. `tools/web-b11-stages-e2e.js` is the browser half. The fairness audit proves
dodgeability **as arithmetic and as geometry** - a window long enough for a modelled reaction plus a
45-degree escape, a lock that does not move after the freeze, and a damage footprint equal to the
telegraph - under a modelled reaction latency. It is a bound, not a human playtest, and it does not
claim that any particular attack feels good.
