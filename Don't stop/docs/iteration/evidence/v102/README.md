# v1.0.2 evidence — Web Pointer Lock input repair and release verification

This directory is the release evidence for **TowDownGame v1.0.2**. It exists because
the v1.0.1 Web build shipped with `CI green` while a human could not play it, so
every claim below is tied to the command that produced it and to the class of
verification it belongs to:

| Class | Meaning | What it can prove |
|---|---|---|
| `AUTOMATED_CI` | GitHub Actions on a hosted runner | build/export/boot/console/network/smoke/save-audit only |
| `REAL_BROWSER` | `tools/*.js` driven Chromium on real hardware | the input chain works in a real browser |
| `HUMAN` | a person playing | whether the game is actually good to play |

`CI_PASS`, `REAL_BROWSER_PASS` and `HUMAN_ACCEPTED` are **not** interchangeable.
v1.0.2 has `REAL_BROWSER_PASS` and is **not** human-accepted; see
`READY_FOR_HUMAN_WEB_ACCEPTANCE` in `summary.json`.

## What was wrong in v1.0.1

`%ROOT%/TowDownGame-Iteration/autoload/Utils.gd` set `Input.MOUSE_MODE_CAPTURED`
on Web (browser Pointer Lock) while all gameplay aiming still read
`get_global_mouse_position()` / `get_viewport().get_mouse_position()`. Under
Pointer Lock the browser freezes absolute pointer coordinates, so aim stayed
stuck at the lock point until Escape released it — which matches the reported
"mouse does not move, but Escape partially restores it".

## What v1.0.2 changes

`Utils` now owns one gameplay aim provider:

* `get_aim_viewport_position()` — Web + Pointer Lock returns a virtual cursor
  advanced by `InputEventMouseMotion.relative`; otherwise the native viewport
  mouse position (desktop behaviour is unchanged).
* `get_aim_world_position()` — the same value through the viewport canvas
  transform.

Every gameplay aim site (Hero, BaseGun and all gun scripts, MechanismGun beams,
GrenadeLauncher, BaseEquip, GunSprite, the hero camera and the right-click
grenade lob) reads the provider. UI-only absolute-mouse use (`ui/Inventory.gd`,
`ui/BuildIcon.gd`) is untouched, and the v1.0.1 Web software cursor sprite is gone.

## Commands and results

```
# 1. Desktop parity of the provider — proves Windows was not redirected
godot --headless --path TowDownGame-Iteration res://tests/AimProvider.tscn
  AIM_PROVIDER_AUDIT checks=14 failures=0
  desktop: get_aim_world_position() == Player/Gun get_global_mouse_position()  3/3
  crosshair.get_global_mouse_position() == viewport mouse position (neutral)    3/3

# 2. Every weapon class, not just the default gun
godot --headless --path TowDownGame-Iteration res://tests/AimWeaponCoverage.tscn
  AIM_WEAPON_COVERAGE checks=27 failures=0
  every weapon class reads the unified aim provider into gun.direction        24/24
  every weapon class points along the provider direction                      24/24

# 3. Real Chromium, real Pointer Lock, real relative mouse, real buttons/keys
E2E_HEADED=1 node tools/pointer-lock-e2e.js http://127.0.0.1:PORT/index.html <out>
  RESULT=PASS — 43/43 required tokens (evidence: pointer-lock-e2e-headed.json)
```

Measured in that run: 240 CSS px of real mouse movement produced exactly
76.94 design units of aim (scale 0.3206 = 410/1279, i.e. 1:1 on screen), the
perpendicular axis moved 0.00, each sweep was exactly reversible, the aim
accumulated 1606° over a full circle, the product crosshair sat 0.1 unit from the
provider, and all four projectile directions matched the provider's own aim angle
within 0.5°. Escape released Pointer Lock and paused, a real gesture re-captured
it, a lost tab focus released input and paused, and refocusing did **not**
self-recapture. `document.pointerLockElement` and the engine's `mouse_mode` were
cross-checked at every phase so the game cannot report a capture it does not have.

## Release-artifact audit

```
python tools/pck-audit.py build/web/index.pck build/windows/TowDownGame-Windows-x64.pck
  entries=2623 payload=38.42 MiB — no leakage patterns matched
```

The audit parses the real pack directory and refuses to report success unless it
finds `project.binary`, so a broken parse cannot look like a clean pack. It
verifies that no build output, save file, evidence, docs, tests, tooling, log or
screenshot is embedded.

## Save isolation (measured with the exported production binary)

```
build/windows/TowDownGame-Windows-x64.exe -- --smoke
  [smoke] user_dir=C:/Users/admin/AppData/Roaming/TowDownGame   <- public_release
  [smoke] renderer=forward_plus                                  <- desktop renderer kept
  [smoke] result=PASS
```

Development runs use `%APPDATA%\TowDownGame-Iteration`; the exported production
build uses `%APPDATA%\TowDownGame`; Web uses IndexedDB in the browser profile.
The two desktop directories were backed up before the runs and restored after.

## Honest limitations of this evidence set

* The pointer-lock E2E and the visual/perf tour were run on one Windows machine
  with an AMD Radeon RX 7900 XT. The CI runner cannot reproduce them; CI runs the
  same script and reports `UNTESTED_IN_CI` (exit 3) when the environment never
  grants Pointer Lock, instead of hiding the failure behind `|| true`.
* Web frame times at 1920x1080 and 2560x1440 are `p50 6.3 ms / p99 6.4 ms`
  (vsync-capped at the display's 160 Hz). The 3840x2160 pass is **invalid**: from
  the combat screen onwards Chromium throttled `requestAnimationFrame` to ~1 Hz
  because the headed window was occluded, which shows up as a tight ~1000 ms
  period. One 1080p run showed the same 1 Hz pattern during the boss phase and it
  did not reproduce at 1440p, so it is reported as an environment artefact rather
  than a product spike.
* The visual tour's marker-to-screenshot alignment is unreliable under load
  (browser console delivery lags behind the in-game dwell), so only the loader,
  camp/HUD, camp shop and character-stats captures were confirmed by eye. The
  remaining captures exist but are not claimed to show the screen they are named
  after.
* `WINDOWS_STUTTER=NOT_REPRODUCED_IN_AUTOMATION` is measured with a validated
  method (the windowed run proves shots really fired: `[smoke] fire transient=0->11`),
  but a headless run reports `transient=0->0`, so any frame-time conclusion drawn
  from a headless run is worthless. Do not repeat that mistake.
