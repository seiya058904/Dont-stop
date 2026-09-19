# Presentation review evidence

BASE_SHA: `c2ace9c99419a87746e1809517336bdab5ce9d0f`.
Final playable build: `5d5d3eb` (v12). Combat normal/mixed/Stage40: `0ad7c98` (v11);
dense was remeasured on v12 after Camp caching. Earlier images retain their capture revision.
`HUMAN_ACCEPTED=false`. These are tool-operated observations, not human acceptance.

| Evidence | Method and scope |
| --- | --- |
| `camp-before.png`, `camp-after.png` | Playwright + Chromium, actual Camp UI and owned Uzi selection. Five pages, purchase/equip/unequip/filter/save flows have separate local evidence. |
| `weapons-before.png`, `weapons-after.png` | Contact sheets of actual Godot-rendered weapon bodies, integer nearest-neighbor enlargement. IDs match `weapon-matrix.json`; no mockup assets. |
| `warning-before.png`, `warning-after.png` | Actual Godot HostileZone observer during an extended fairness wait. The new warning stays inactive until the real activation flag changes. |
| `web-firing.png` | Playwright + Chromium, purchased and equipped Uzi firing in combat. |
| `weapon-matrix.json` | All 24 decisions and references to local raw body, eight-direction and aimed-fire captures. |

Full raw evidence is under the ignored local directory
`evidence/visual-upgrade-20260919/`. Its `review.html` provides interactive
before/after selection. Raw paths in the matrix are relative to that directory;
they are not claims that every image is committed to Git.

The final firing fixtures use production firing and an existing test-only aim
override. All 24 target cases damaged the actual target; all 24 corresponding
wall cases blocked it. Earlier captures with missing aim are retained locally
but are not the final hit evidence. All 192 held anchor observations match the
baseline. Screenshots alone do not prove gameplay or performance equivalence.

See [the implementation and validation ledger](../../presentation-upgrade.md)
for tests, performance results, known baseline failures and remaining limitations.

The latest RNG check uses the complete production Camp render, after waiting for
its queued initial panel to be freed. `rng-browser-pair.json` compares actual
24/4/5/5/4/6 row counts and random sequences across the original and new builds.
All sequences match, including the real shoot animation. Earlier v7-v9 Camp
observations referenced a queued/freed panel: their zero-draw result and signature
mismatch are observer failures and are not used as gameplay evidence.

Additional selected actual-rendering evidence: `boundaries-after.png` (real hit
footprint overlays), `reduced-flash-after.png` (nine attack families, target/wall),
`elite-coverage.png` (18 role/modifier combinations), and `status-text-*.png`
(readable nonnumeric shield feedback on bright and dark backgrounds).

Final v12 browser images: `camp-final-legendary.png` and
`camp-final-comparison.png`, with `camp-final-flow.json`. Purchased ordinary and
legendary guns survive reload; original startup wallet refill is documented.
`firing-all24-after.png` and `held-directions-after.png` supplement the matrix.

[Hardware results](performance.md) preserve failed gates and distinguish original
hitches from new ones. `performance-raw.json.gz` contains complete original report
text, including historical failures; source hashes are in
`performance-source-index.json`. Build identities and Camp pressure samples are
also committed. Screenshots and performance sampling were separate operations.

B5 observer correction `1121603` keeps its promised stationary payload subject from
dashing. Original/new targeted B02 checks both pass 37; production build remains v12.

`test-logs.zip` preserves 182 original log/fixture/result files, including failed
attempts. `test-log-index.json` supplies exact source hashes. The archive round
trip was verified byte-for-byte. Final B5 targeted results are37 passes on each side.

Final validated gameplay/test revision `1121603`: both native runs35450919275 /
35450915626 and Web35450919484 succeeded. Native contracts and pressure passed;
all six Web gates passed; deploy/online-deployment jobs were skipped. See
`ci-results.json` and the archived CI logs. Final evidence/tool-metadata commits
do not change the playable v12 production code.
