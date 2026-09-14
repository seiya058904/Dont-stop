# TowDownGame v1.0.2

Web Pointer Lock input repair, plus corrections found while independently
re-verifying the in-flight v1.0.2 work. Windows gameplay and visuals are
unchanged by design.

## Verification classes — read this before believing anything below

| Label | What it is | What it proves |
|---|---|---|
| `AUTOMATED_CI` | GitHub Actions hosted runner, real Chromium | build, export, boot, canvas, console, network, in-game smoke, save audit |
| `REAL_BROWSER` | `tools/pointer-lock-e2e.js` and `tools/web-visual-tour.js` on real hardware | the input chain works in a real browser |
| `HUMAN` | a person playing | whether the game is good to play |

**CI green does not mean the mouse is playable.** That is exactly how v1.0.1
shipped broken: the deploy workflow was green while a human could not aim. In
v1.0.2 the CI pointer-lock step is no longer wrapped in `|| true`. It now exits
`3` when the environment cannot exercise the relative-motion path and publishes
`POINTER_LOCK_E2E=UNTESTED_RELATIVE_MOTION` — an explicit "not tested", never a
pass — and any other non-zero exit fails the deploy.

Measured on CI, that distinction is not hypothetical: the `89feb25` run of the
*previous* implementation logged `aimvp=(0.0, 0.0)` and `dAngle=0.0` for the same
sweeps, i.e. the relative-motion assertions have **never** passed on the CI
runner. The old `|| true` hid a permanently red test rather than a one-off
virtual-display hiccup. CI still gates plenty: build, export, boot, canvas,
console, network, in-game smoke, save audit, Pointer Lock *acquisition*, the
engine-vs-browser lock consistency check, Escape/pause/cursor, resume by real
gesture, WASD, crosshair coherence. Only the relative-motion family is untested
there, and `tools/pointer-lock-e2e.js` now records a DOM-level witness of what
the page itself received so the log says which side dropped the deltas.

## What was broken in v1.0.1 (`REAL_BROWSER` + `HUMAN`)

Web set `Input.mouse_mode = MOUSE_MODE_CAPTURED` (browser Pointer Lock) while
gameplay aiming still read `get_global_mouse_position()`. Under Pointer Lock the
browser freezes absolute pointer coordinates, so aim never moved; Escape released
the lock, which "restored" the mouse. That matches the human report exactly.

## Fix

One gameplay aim provider in `autoload/Utils.gd`:

* Web + Pointer Lock → a virtual cursor advanced by
  `InputEventMouseMotion.relative`, clamped to the viewport.
* Everywhere else → the native viewport mouse position, i.e. desktop behaviour
  is bit-for-bit what it was. `tests/AimProvider.tscn` proves this: the provider
  equals the engine's own `get_global_mouse_position()` on the Player and on the
  Gun at three different camera states.

All gameplay aim sites go through it (24/24 weapon classes verified). UI-only
absolute-mouse use is untouched, and the v1.0.1 Web software cursor sprite is
gone.

## Corrections to the in-flight work (found by re-verification, not by CI)

* **Right-click grenade lob was dead.** `autoload/Demo.gd` read
  `Utils.player.Utils.get_aim_world_position()`; `Player` has no `Utils` member,
  so every right-click raised a script error and the lob never fired. This was
  introduced by the v1.0.2 aim-provider rewrite and is now fixed and covered by
  `tests/AimProvider.tscn`.
* **`Smoke` grew an array forever in normal launches** — it appended a frame
  sample on every frame and nothing ever read it outside the test harness.
* **The frame-time probe polluted itself**: it kept a session-long array (an
  allocator inside the measurement) and its window was not armed per
  measurement. It now samples only while a measurement is active.
* **The regression harness had been red since v1.0.1 for a bookkeeping reason**:
  its "known BGM teardown leak" whitelist still named `Cephalopod.mp3` while the
  scenes have loaded `Cephalopod.ogg` since v1.0.1, so ~9 cases were reported as
  failures. Fixed in `tools/verify-m11.py` and `tools/verify-m12.py`.
* **The E2E could pass for the wrong reason**: the vertical aim sweeps were
  measured across an unrelated recenter move, the resume step used neither real
  resume path, and the crosshair sample was taken while the aim was still moving.

## Real-browser acceptance (`REAL_BROWSER`, headed Chromium on Windows)

43/43 required tokens pass. Measured, not asserted:

* 240 CSS px of real mouse movement → exactly 76.94 design units (0.3206 =
  410/1279, i.e. 1:1 on screen); the perpendicular axis moved **0.00** and every
  sweep was exactly reversible.
* Aim accumulated 1606° over a full circle of real movement.
* The product crosshair sits 0.1 design unit from the aim provider.
* Real mouse buttons produced projectiles at 1.5° / 176.1° / 94.0° / −90.1° for
  right / left / down / up, each within 0.5° of the provider's own aim angle.
* Escape released Pointer Lock and paused; a real gesture re-captured it; losing
  tab focus released input and paused; regaining focus did **not** self-capture.
* `document.pointerLockElement` and the engine's `mouse_mode` were cross-checked
  at every phase, so the game cannot report a capture it does not hold.
* Zero console errors, zero HTTP errors.

## Windows (`AUTOMATED_CI` + standalone)

`Windows x64 Release` keeps Forward+ (Vulkan). The exported binary reports
`renderer=forward_plus` and writes to `%APPDATA%\TowDownGame` (production
namespace) while development runs stay in `%APPDATA%\TowDownGame-Iteration`.

Standalone smoke: **PASS**, and shots really fired
(`[smoke] fire transient=0->11`). Frame-time probe across 13 weapon classes plus
first combat / switch / shot / reload: every window `max = 6.3 ms`, steady state
`p50 = p95 = p99 = max = 6.3 ms`. **The reported intermittent micro-stutter did
not reproduce.** Method note: a *headless* run reports
`fire transient=0->0`, i.e. no shots at all, so any frame-time conclusion drawn
from a headless run is worthless — these numbers come from the windowed run.

`WINDOWS_HUMAN_STATE=PASS_WITH_MINOR_INTERMITTENT_STUTTER` is carried over from
v1.0.1; the Windows feel was not re-judged by a human in this round.

## Known open items (disclosed, not hidden)

1. **`M10RewardAudit` fails 7 `real firing` assertions.** Reproduced identically
   with the v1.0.2 changes stashed, so it is pre-existing and unrelated to this
   release. It is the one genuine failure left in the M5–M12 suite; the other
   reported failures were the whitelist bug above or re-ran clean.
2. **Web 3840×2160 performance is unmeasured.** Chromium throttled
   `requestAnimationFrame` to ~1 Hz once the headed window was occluded, giving a
   tight ~1000 ms period. 1920×1080 and 2560×1440 are healthy (p50 6.3 ms).
3. **Web visual coverage is partial.** Loader, camp/HUD, camp shop and character
   stats were confirmed by eye; the other captures exist but the tour's
   marker-to-screenshot alignment is unreliable under load, so they are not
   claimed.
4. **Not human-accepted.** `READY_FOR_HUMAN_WEB_ACCEPTANCE=true`,
   `WEB_HUMAN_ACCEPTED=false`. Whether the Web build actually feels right is a
   judgement only a person can make.

## Artifacts

Canonical artifact, matching the v1.0.0/v1.0.1 release convention (a ZIP plus a
`.sha256` sidecar), built by CI from tag `v1.0.2`:

* `TowDownGame-Windows-x64.zip` — SHA-256 `1155971AE75E41DFFC1961446C642B6533D47AF98D4562BD30E7F17FBCAC209A`
  * `TowDownGame-Windows-x64.exe` — SHA-256 `AA325EAEFB48D2307E5F49C9108305B66D062A0C0BC8991EF91588B11872B84F`
  * `TowDownGame-Windows-x64.pck` — SHA-256 `6586CC935767F8E315A941E50BEFB4B058DCFB668327F09C334EBBEFA4170C8F`
* Web build: `https://seiya058904.github.io/game-prototype-lab/index.html`

The ZIP's `.sha256` sidecar is attached next to it and was re-verified against a
fresh download. A pck rebuilt locally is 256 bytes larger purely because the local
`.godot` cache still lists files that the export filter now excludes; the exe is
byte-identical and both packs contain the same 2631 entries / 39.03 MiB payload.

`tools/pck-audit.py` found the Windows pack shipping **1.78 MB of build output**
(`build/web/index.png`, `build/web/index.icon.png` and three `.import` companions)
because `--editor --import` picks up whatever is in `build/` at import time and the
export filters did not exclude it. Both presets now exclude `build/*`, and both
packs audit clean. This also made the artifact depend on local build state; it is
deterministic again.

Windows and Web are built from the same source commit as tag `v1.0.2`
(`e1365e06441e879f5a4ea77e4f18a99455378d29`).
