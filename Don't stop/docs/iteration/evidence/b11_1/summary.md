## Build identities (hashed from the bytes the browser actually loaded)

| | BEFORE | AFTER |
|---|---|---|
| identity (sha256 of wasm‖pck‖js) | `e22168f220f5506b…` | `e05d7ada54d79afb…` |
| index.wasm | fc74679e3b97 (39514754 B) | fc74679e3b97 (39514754 B) — identical |
| index.pck | 2efddda8d7c7 (41244244 B) | 8a9f5316f62b (41245188 B) — **differs** |
| index.js | 33c94cb3175f (279815 B) | 33c94cb3175f (279815 B) — identical |

## Percent of physics frames that issued at least one wall-clip raycast

`raycast_frame` vs `no_raycast_frame` is the one mutually exclusive pair in the census.

| scenario | BEFORE r1 | BEFORE r2 | AFTER | r1→r2 noise | r2→AFTER |
|---|---:|---:|---:|---:|---:|
| C | 84.1% | 84.8% | 52.5% | 0.7 pt | **-32.3 pt** |
| C-rpt | 83.5% | 85.4% | 56.3% | 1.9 pt | **-29.1 pt** |
| A | 81.4% | 75.9% | 50.0% | 5.5 pt | **-25.9 pt** |
| B | 73.0% | 84.3% | 63.6% | 11.3 pt | **-20.7 pt** |
| D | 88.2% | 86.1% | 60.5% | 2.1 pt | **-25.6 pt** |
| **mean** | **82.0%** | **83.3%** | **56.6%** | **1.3 pt** | **-26.7 pt** |

## Spike census, split by window (over 5 scenarios, 2 rounds each)

| window | BEFORE o25/o33/o50 | max ms | AFTER o25/o33/o50 | max ms |
|---|---:|---:|---:|---:|
| round start (t<5 s of each round) | 26/22/19 | 149 | 26/23/19 | 149 |
| steady combat (t≥5 s) | 6/4/1 | 59 | 5/1/1 | 65 |

Totals from `spikes.*` (what the raw field reports) are the sum of the two rows above, so the
raw `over33`/`over50` counts are ~80% round-start hitch and not the reported phenomenon.

## Noise floor, measured from two runs of the SAME build

| metric | BEFORE r1 | BEFORE r2 | mean abs delta |
|---|---:|---:|---:|
| wall raycasts / run | 11002.20 | 11640.60 | **11.8%** |
| raycasts / s | 120.85 | 127.87 | **11.8%** |
| wall raycasts skipped / run | 0.00 | 0.00 | **nan%** |
| clear_line us / call | 12.43 | 12.30 | **7.9%** |
| onHit us / hit | 301.51 | 302.44 | **1.9%** |
| phys ms / frame | 5.36 | 5.57 | **5.5%** |
| phys p99 ms | 12.59 | 15.65 | **30.2%** |
| zone step us / frame | 109.70 | 114.28 | **12.4%** |
| zone draw us / frame | 176.53 | 250.51 | **42.9%** |
| reward fanout reuses / run | 0.00 | 0.00 | **nan%** |
| enemies peak | 84.00 | 84.00 | **0.0%** |

## BEFORE → AFTER, five scenarios, judged against that floor

| metric | BEFORE | AFTER | delta | noise | multiple | verdict |
|---|---:|---:|---:|---:|---:|---|
| wall raycasts / run | 11640.60 | 5001.60 | -56.9% | 11.8% | 4.5–5.1× | ATTRIBUTABLE |
| raycasts / s | 127.87 | 54.93 | -56.9% | 11.8% | 4.5–5.1× | ATTRIBUTABLE |
| wall raycasts skipped / run | 0 | 6175 | new | — | — | only the AFTER build can raise this |
| clear_line us / call | 12.30 | 7.32 | -40.4% | 7.9% | 4.6–5.6× | ATTRIBUTABLE |
| onHit us / hit | 302.44 | 276.84 | -8.4% | 1.9% | 3.4–6.5× | ATTRIBUTABLE |
| phys ms / frame | 5.57 | 5.32 | -4.4% | 5.5% | 0.3–1.1× | directionally consistent, within noise |
| phys p99 ms | 15.65 | 14.17 | -7.2% | 30.2% | 0.0–1.2× | noise |
| zone step us / frame | 114.28 | 99.33 | -12.2% | 12.4% | 0.3–1.8× | noise |
| zone draw us / frame | 250.51 | 226.52 | -9.0% | 42.9% | 0.0–0.5× | noise |
| reward fanout reuses / run | 0 | 1071 | new | — | — | only the AFTER build can raise this |
| enemies peak | 84.00 | 84.00 | +0.0% | 0.0% | 0.0–0.0× | noise |

Two metrics are 0 in BEFORE for opposite reasons, and it matters which is which:

* `wall raycasts skipped` is 0 because the BEFORE build had no skip: it re-clipped every frame,
  so the work shows up in `wall raycasts` instead. Its AFTER value is the work REMOVED.
* `reward fanout reuses` is 0 because BEFORE re-classified the group on every hit and therefore
  never had anything to re-use. Its AFTER value counts re-uses of a cache that did not exist.

## Per-scenario detail

| metric | C | C-rpt | A | B | D |
|---|---:|---:|---:|---:|---:|
| wall raycasts / run | -60.5% | -57.2% | -55.7% | -52.5% | -58.7% |
| raycasts / s | -60.5% | -57.2% | -55.7% | -52.5% | -58.7% |
| wall raycasts skipped / run | n/a | n/a | n/a | n/a | n/a |
| clear_line us / call | -44.4% | -39.4% | -36.4% | -37.4% | -44.3% |
| onHit us / hit | -12.0% | -6.9% | -6.3% | -9.6% | -7.3% |
| phys ms / frame | -4.9% | -6.0% | -1.6% | -5.4% | -4.2% |
| phys p99 ms | +5.7% | +10.2% | -37.5% | +0.5% | -15.0% |
| zone step us / frame | -18.2% | -23.0% | -4.6% | +4.3% | -19.7% |
| zone draw us / frame | -21.1% | -6.3% | -8.4% | +1.3% | -10.7% |
| reward fanout reuses / run | n/a | n/a | n/a | n/a | n/a |
| enemies peak | +0.0% | +0.0% | +0.0% | +0.0% | +0.0% |

