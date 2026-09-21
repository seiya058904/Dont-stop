# B19 performance / enchantment delivery record

Status: `B19_CANDIDATE_FOR_HUMAN_REVIEW`

`HUMAN_ACCEPTED=false`.

This record follows `Dont-stop-B19-performance-enchantment.zip` (SHA-256:
`9D63BDBE1D54F4A2A59BB5BA939A3FC2C7E91CCEE053399C7FCF1FF7A940C170`). The
package audit and evidence archives were treated as read-only delivery
instructions; they were not treated as B19 results.

## Scope delivered

- B19 ordinary final-HP axis and explicit B04 final HP reference.
- Stage 31-39 cumulative enchantment allocation, tier-2 absolute ratios, rare
  giants, and an independent giant HP axis.
- Shared `B19EnchantmentLayer` for the ring/HP/rune/flame identity. The flame
  remains orange/purple, pixel-shaped and animated, but no longer creates one
  animated CanvasItem per enchanted actor.
- Boss/elite continuous barrage with telegraph, pause-safe-zone handling,
  projectile capacity admission, and action metrics.
- Per-process-frame monster/reward group caches in the combat hot paths.
- Stage-tour gate ordering, semantic UI contract checks, and B19 contract
  coverage.

## Evidence

| Check | Result |
| --- | --- |
| B19 contracts | 24 checks, 0 failures |
| B18 contracts | 87 checks, 0 failures |
| B15 stage matrix | 1,131 checks, 0 failures |
| B17 contracts | 20 checks, 0 failures |
| B12 UI contracts | 75 checks, 0 failures |
| Web stage-tour | 46 tokens, 0 failures; stages 31/35/39/40 each reached COMBAT, spawned enemies, allowed movement, and simulated at least 9 seconds |
| Exported Windows stage-tour | exit 0; stages 31/35/39/40 reached COMBAT and simulated 9.000-9.033 seconds |

The Web stage-tour JSON and screenshot are under
`output/playwright/b19-stage-tour/`. The A/B/C/D stress JSON and sustained
Web-perf JSON are under `output/playwright/b19-performance/`.

## Performance gate

The final build was measured in headed Chromium using AMD D3D11. The four
scenario runs each covered roughly 45 seconds of real combat with a peak of
180 enemies:

| Scenario | Frames | Avg ms | p95 ms | p99 ms | >33 ms | >50 ms |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| A normal | 2,670 | 16.87 | 16.67 | 16.67 | 7 (0.26%) | 5 |
| B dense bodies | 2,663 | 16.91 | 16.67 | 17.55 | 8 (0.30%) | 5 |
| C dense attacks | 2,674 | 16.84 | 16.67 | 17.33 | 6 (0.22%) | 3 |
| D worst visual load | 2,675 | 16.83 | 16.67 | 17.01 | 7 (0.26%) | 3 |

The separate headless sustained-load probe is retained as a limitation rather
than hidden: final B19 recorded 30 samples at 24.91 ms average and 28.13 ms
p95, while the exact branch HEAD baseline recorded 24.74 ms average and 25.25
ms p95. Therefore this candidate does not claim a universal 60 FPS or a
universal p95 <=18.5 ms result; human review should decide which real-browser
measurement path is release-significant for this project.

The initial per-actor animated marker implementation measured 34.20 ms average
and 40.24 ms p95 in the same sustained probe. The shared layer is the scoped
performance fix that removed that regression; the intermediate evidence is
kept in the same evidence directory.

## Delivery boundary

Web and Windows release builds were generated under `build/web/` and
`build/windows/`. No commit, push, merge, PR update, deployment, publication,
or human acceptance was performed. Godot still reports exit-time ObjectDB/
resource leak diagnostics in some test/export runs; they did not produce test
failures, but remain part of the human-review boundary.
