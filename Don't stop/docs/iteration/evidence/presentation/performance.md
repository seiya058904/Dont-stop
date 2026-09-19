# Hardware performance comparison

Measured with Playwright Chromium / AMD RX 7900 XT / ANGLE D3D11, 1280x760, seed 20260918.
Each row retains the exact 15..105 combat-second window. Original production BASE_SHA is
`c2ace9c99419a87746e1809517336bdab5ce9d0f`. Normal/mixed/Stage40 AFTER is
`0ad7c98` (v11); dense AFTER is `5d5d3eb` (v12). v12 changes only Camp cache
reuse/RNG preservation; its transition-heavy dense profile was remeasured.

**Not an all-pass report.** No thresholds were changed. Historical failed v6/v10 runs
are included in `performance-raw.json.gz`, alongside final raw data. CPU values are
frame-weighted samples of one-second maxima, not individual frame CPU durations.
See [monitor semantics](cpu-monitor-semantics.md).

| Pair | Frame p95 B/A ms | p99 B/A ms | >33.3 B/A | >50 B/A | Physics p95 B/A ms | Process p95 B/A ms | Failed numeric gates |
|---|---:|---:|---:|---:|---:|---:|---|
| normal-1 | 16.67/16.67 | 16.67/16.67 | 0/0 | 0/0 | 7.74/6.47 | 15.73/9.51 | none |
| normal-2 | 16.67/16.67 | 16.67/16.67 | 0/0 | 0/0 | 7.53/6.82 | 11.98/11.23 | none |
| normal-3 | 16.67/16.67 | 16.67/16.67 | 0/0 | 0/0 | 8.29/7.24 | 12.18/12.43 | none |
| dense-1 | 16.67/16.67 | 19.37/16.86 | 4/5 | 0/1 | 7.70/7.03 | 22.62/29.34 | process_p95 |
| dense-2 | 18.06/16.67 | 22.41/18.06 | 5/6 | 0/0 | 7.05/6.93 | 36.07/27.69 | none |
| dense-3 | 18.06/16.67 | 22.22/20.00 | 4/4 | 0/0 | 7.86/8.27 | 27.33/23.74 | none |
| mixed-1 | 17.99/16.67 | 24.23/18.06 | 12/8 | 4/1 | 13.99/20.14 | 49.12/47.09 | physics_p95 |
| mixed-2 | 16.67/16.67 | 24.76/18.06 | 14/5 | 3/2 | 15.69/9.30 | 45.38/48.84 | process_p95 |
| mixed-3 | 18.06/16.67 | 25.00/18.06 | 13/6 | 5/1 | 10.27/10.24 | 46.58/34.63 | none |
| stage40-1 | 16.67/16.67 | 16.67/16.67 | 0/1 | 0/1 | 2.98/3.13 | 8.50/8.24 | none |
| stage40-2 | 16.67/16.67 | 16.67/16.67 | 0/1 | 0/1 | 3.35/3.29 | 8.31/8.30 | none |
| stage40-3 | 16.67/16.67 | 16.67/16.67 | 0/0 | 0/0 | 3.21/3.21 | 8.30/7.30 | none |

All 12 pairs meet p95/p99 and extra->33.3 numeric frame gates. Dense row 1 and Stage40 rows 1/2
still require the separate new->50ms review; passing the other columns does not waive it.
Dense/mixed individual CPU proxy failures remain failures. Dense clean run 1 has
one 78.834ms hot hitch; clean runs 2/3 have none, so a new repeatable hitch is not
established by those three samples. This does not erase the single-run failure.
No GPU improvement claim is made.

The first v12 dense run overlapped evidence compression and is retained as a
protocol-interference record. Its replacement was selected before its outcome
was known and also failed its process proxy gate. See `performance-protocol-notes.json`.
The complete preceding v11 comparison is retained in `performance-comparison-v11.json`.

## Stage40 early-hitch timeline

The fixed window contains one >50ms frame in two AFTER runs and zero in BEFORE.
Full-run traces show the same early long-frame class in every original run:

| Side/run | Late early-hitch time / duration |
|---|---:|
| BEFORE 1 | 14.902s / 132.544ms |
| BEFORE 2 | 12.133s / 131.574ms |
| BEFORE 3 | 12.249s / 132.672ms |
| AFTER 1 | 15.018s / 131.452ms |
| AFTER 2 | 17.350s / 127.206ms |
| AFTER 3 | 12.922s / 127.574ms |

This supports an existing early-hitch class crossing the warmup boundary; it does
not prove the source of that hitch or justify deleting the two hot-window flags.
All three final Stage40 runs reach three phases and actual ultimate activations.
Mixed runs also retain absolute 60-142ms AFTER hitches, versus original 133-149ms;
relative improvement does not mean hitch-free gameplay.

## Camp and lifecycle

Native Compatibility, same 290 synchronous UI calls / ten reopen cycles:

| Call metric | Original | Final v12 |
|---|---:|---:|
| p50 | 7.240ms | 3.213ms |
| p95 | 10.904ms | 6.734ms |
| max | 14.002ms | 7.531ms |

This measures method time, not physical-input or GPU completion latency. 242 assertions
pass on both sides. Warmed closed nodes stay at 281/283 and orphans at zero. Each
observer retains the same 152672 bytes while collecting samples; cleanup files show
the post-release state. This is not a zero-allocation claim.

## Reproduction and missing counters

`performance-raw.json.gz` is a JSON object mapping original filenames to exact original UTF-8 report
strings. Decompress and write each string verbatim to its filename, then run
`tools/summarize-presentation-perf.js` and `tools/compare-presentation-perf.js`.
`performance-source-index.json` records the source file byte hashes. The full reports
include cold frames, per-frame samples, load counters, driver arguments, GPU and build hashes.

GPU time, true per-frame CPU time and Web release static memory: **N/A**, unavailable
in this configured monitor/export. Peaks are full-run peaks, including warmup.
The report does not equate absent counters to zero or infer a global performance pass.
