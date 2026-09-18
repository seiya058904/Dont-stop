## Build identities (hashed from the bytes the browser actually loaded)

| | BEFORE | AFTER |
|---|---|---|
| identity (sha256 of wasm‖pck‖js) | `a3e036d9e014b543…` | `7c61d0724ab7cdb8…` |
| index.wasm | fc74679e3b97 (39514754 B) | fc74679e3b97 (39514754 B) — identical |
| index.pck | 1673d1fa157e (41253380 B) | 1579fbd5c562 (41254564 B) — **differs** |
| index.js | 33c94cb3175f (279815 B) | 33c94cb3175f (279815 B) — identical |

The engine payload is byte-identical on both sides and only the `.pck` (which carries the
scripts) changes — the two builds differ *only* in game code. All runs on one side share one
identity; the two sides share none.

## Noise floor, measured from two runs of the SAME build (BEFORE r1 vs BEFORE r2)

| metric | BEFORE r1 (mean of 4) | BEFORE r2 (mean of 4) | mean abs delta |
|---|---:|---:|---:|
| phys ms/frame | 6.064 | 6.247 | **6.0%** |
| phys p99 ms | 16.584 | 22.921 | **69.5%** |
| frame avg ms | 16.845 | 16.808 | **0.3%** |
| spikes >33 /run | 7.500 | 7.000 | **12.7%** |
| spikes >50 /run | 4.500 | 4.250 | **5.0%** |
| slow run ms | 143.5 | 168.2 | **18.1%** |
| enemies peak | 84.000 | 84.000 | **0.0%** |
| zones peak | 21.250 | 19.750 | **6.4%** |
| draws avg | 612.8 | 622.9 | **2.3%** |
| fog push lines /s | 994.8 | 959.9 | **12.9%** |
| fog entries offered /s | 1966.4 | 1895.7 | **13.0%** |
| fog entries accepted /s | 1962.6 | 1890.8 | **13.1%** |
| fog entries dropped /s | 3.807 | 4.900 | **73.7%** |
| fog dropped share % | 0.175 | 0.231 | **85.5%** |
| fog entries per line | 1.971 | 1.970 | **0.2%** |
| fog child scans /run | 178978 | 172636 | **13.0%** |
| fog canvas hits /run | 178976 | 172634 | **13.0%** |
| fog canvas draws /s | - | - | n/a (absent from the BEFORE build) |
| fog entries drawn /s | - | - | n/a (absent from the BEFORE build) |
| fog drawn share | - | - | n/a (absent from the BEFORE build) |
| fog draw us/s | - | - | n/a (absent from the BEFORE build) |
| fog draw us/frame | - | - | n/a (absent from the BEFORE build) |
| zone draw us/s | 18146.0 | 17941.1 | **10.3%** |
| zone step us/s | 6349.3 | 6503.0 | **10.8%** |
| zone total us/s | 24495.3 | 24444.1 | **10.2%** |
| telegraph draws /s | 360.7 | 356.3 | **10.8%** |
| telegraph draw us/s | 13576.7 | 13383.9 | **10.2%** |
| shots created /s | 8.737 | 8.412 | **9.9%** |
| shot exceptions /s | 722.6 | 695.1 | **10.0%** |
| shot exceptions per shot | 82.907 | 82.791 | **0.2%** |
| shot fog mirrors /s | 664.6 | 630.0 | **14.8%** |
| status walks /s | 4696.1 | 4706.3 | **0.2%** |
| status walks empty % | 100.0 | 100.0 | **0.0%** |
| wall raycasts /s | 58.643 | 58.375 | **12.7%** |
| raycasts skipped /s | 74.044 | 71.818 | **13.6%** |
| path queries /s | 167.9 | 165.8 | **1.7%** |
| path us/s | 2281.9 | 2310.9 | **9.0%** |
| objects peak | 8379.2 | 8344.5 | **0.4%** |
| canvas items peak | 6422.2 | 6723.8 | **8.6%** |
| orphans peak | 0.000 | 0.000 | n/a (reads zero on both BEFORE reps) |
| draws peak | 831.2 | 845.2 | **7.1%** |
| phys max ms | 22.169 | 28.424 | **42.2%** |
| phys frames >8 ms | 309.8 | 509.2 | **78.7%** |
| phys frames >12 ms | 161.0 | 165.8 | **56.5%** |

## BEFORE → AFTER over the four core scenarios, judged against that floor

| metric | BEFORE | AFTER | delta | noise | multiple | verdict |
|---|---:|---:|---:|---:|---:|---|
| phys ms/frame | 6.155 | 5.884 | -4.2% | 6.0% | 0.0–2.5× | NOISE |
| phys p99 ms | 19.753 | 15.493 | -18.9% | 69.5% | 0.0–0.5× | NOISE |
| frame avg ms | 16.826 | 16.797 | -0.2% | 0.3% | 0.0–4.6× | NOISE |
| spikes >33 /run | 7.250 | 6.125 | -12.5% | 12.7% | 0.0–2.8× | NOISE |
| spikes >50 /run | 4.375 | 4.250 | -2.8% | 5.0% | 0.0–2.2× | NOISE |
| slow run ms | 155.9 | 161.8 | +4.0% | 18.1% | 0.1–0.7× | NOISE |
| enemies peak | 84.000 | 84.000 | +0.0% | 0.0% | 0.0–0.0× | NOISE |
| zones peak | 20.500 | 21.750 | +6.3% | 6.4% | 0.0–2.0× | NOISE |
| draws avg | 617.8 | 613.6 | -0.4% | 2.3% | 0.6–5.0× | NOISE |
| fog push lines /s | 977.3 | 1063.4 | +11.0% | 12.9% | 1.1–1.8× | NOISE |
| fog entries offered /s | 1931.1 | 2103.1 | +11.2% | 13.0% | 1.1–1.8× | NOISE |
| fog entries accepted /s | 1926.7 | 2099.7 | +11.2% | 13.1% | 1.0–1.8× | NOISE |
| fog entries dropped /s | 4.353 | 3.458 | -4.9% | 73.7% | 0.1–0.9× | NOISE |
| fog dropped share % | 0.203 | 0.150 | -18.0% | 85.5% | 0.1–0.7× | NOISE |
| fog entries per line | 1.970 | 1.974 | +0.2% | 0.2% | 0.0–1.7× | NOISE |
| fog child scans /run | 175807 | 96739.1 | -43.8% | 13.0% | 2.9–4.3× | directionally consistent, within noise |
| fog canvas hits /run | 175805 | 96737.1 | -43.8% | 13.0% | 2.9–4.3× | directionally consistent, within noise |
| fog canvas draws /s | - | 57.381 | — | — | — | not measured on the BEFORE build |
| fog entries drawn /s | - | 2099.0 | — | — | — | not measured on the BEFORE build |
| fog drawn share | - | 1.000 | — | — | — | not measured on the BEFORE build |
| fog draw us/s | - | 2059.0 | — | — | — | not measured on the BEFORE build |
| fog draw us/frame | - | 34.954 | — | — | — | not measured on the BEFORE build |
| zone draw us/s | 18043.5 | 11831.7 | -34.2% | 10.3% | 2.7–4.4× | directionally consistent, within noise |
| zone step us/s | 6426.1 | 9236.7 | +44.4% | 10.8% | 2.0–5.7× | directionally consistent, within noise |
| zone total us/s | 24469.7 | 21068.4 | -13.6% | 10.2% | 0.5–2.6× | directionally consistent, within noise |
| telegraph draws /s | 358.5 | 252.5 | -29.4% | 10.8% | 1.9–3.8× | directionally consistent, within noise |
| telegraph draw us/s | 13480.3 | 11107.8 | -17.6% | 10.2% | 0.8–3.0× | directionally consistent, within noise |
| shots created /s | 8.575 | 8.485 | +1.4% | 9.9% | 0.2–2.5× | NOISE |
| shot exceptions /s | 708.8 | 0.000 | -100.0% | 10.0% | 10.0–10.0× | ATTRIBUTABLE |
| shot exceptions per shot | 82.849 | 0.000 | -100.0% | 0.2% | 625.7–625.7× | ATTRIBUTABLE |
| shot fog mirrors /s | 647.3 | 644.1 | +2.9% | 14.8% | 0.7–1.7× | NOISE |
| status walks /s | 4701.2 | 4711.3 | +0.2% | 0.2% | 0.2–5.0× | NOISE |
| status walks empty % | 100.0 | 100.0 | +0.0% | 0.0% | 0.0–0.0× | NOISE |
| wall raycasts /s | 58.509 | 54.774 | -5.9% | 12.7% | 0.1–1.5× | NOISE |
| raycasts skipped /s | 72.931 | 68.907 | -5.0% | 13.6% | 0.0–1.3× | NOISE |
| path queries /s | 166.9 | 172.8 | +3.6% | 1.7% | 0.3–4.1× | NOISE |
| path us/s | 2296.4 | 2431.6 | +5.9% | 9.0% | 0.0–1.2× | directionally consistent, within noise |
| objects peak | 8361.9 | 8474.9 | +1.4% | 0.4% | 1.0–7.2× | NOISE |
| canvas items peak | 6573.0 | 6748.1 | +3.3% | 8.6% | 0.4–0.9× | NOISE |
| orphans peak | 0.000 | 0.000 | — | — | — | reads zero on both sides at this load |
| draws peak | 838.2 | 854.1 | +2.5% | 7.1% | 0.5–2.8× | NOISE |
| phys max ms | 25.296 | 20.774 | -16.3% | 42.2% | 0.0–0.8× | NOISE |
| phys frames >8 ms | 409.5 | 334.6 | -9.5% | 78.7% | 0.1–0.5× | NOISE |
| phys frames >12 ms | 163.4 | 120.5 | -6.1% | 56.5% | 0.3–1.3× | NOISE |

## Point-3 ledger: did the fog side grow enough to eat the redraw saving?

The acceptance rule set for this round was: *"if the Fog push clearly doubles and eats the
redraw saving, do not accept this implementation."* So the four required numbers are printed
together for the worst-load scenario D, each against its own noise floor.

| metric | BEFORE D | AFTER D | delta | noise | multiple | verdict |
|---|---:|---:|---:|---:|---:|---|
| fog push lines /s | 1071.8 | 1319.9 | +23.1% | 12.9% | 1.8× | directionally consistent, within noise |
| fog entries accepted /s | 2111.9 | 2606.8 | +23.4% | 13.1% | 1.8× | directionally consistent, within noise |
| fog entries dropped /s | 8.396 | 9.267 | +10.4% | 73.7% | 0.1× | directionally consistent, within noise |
| fog dropped share % | 0.394 | 0.353 | -10.3% | 85.5% | 0.1× | directionally consistent, within noise |
| fog draw us/s | - | 2408.7 | — | — | — | not measured on the BEFORE build |
| zone draw us/s | 21406.1 | 15463.4 | -27.8% | 10.3% | 2.7× | directionally consistent, within noise |
| zone step us/s | 7357.8 | 11871.9 | +61.3% | 10.8% | 5.7× | ATTRIBUTABLE |
| zone total us/s | 28764.0 | 27335.2 | -5.0% | 10.2% | 0.5× | directionally consistent, within noise |

## Per-scenario delta detail (AFTER mean vs BEFORE mean)

| metric | A normal | B dense enemies | C dense attacks | D worst visual |
|---|---:|---:|---:|---:|
| phys ms/frame | +0.3% | -3.2% | -14.7% | +1.0% |
| phys p99 ms | +1.1% | -35.3% | -34.0% | -7.4% |
| frame avg ms | +0.0% | -0.0% | -1.1% | +0.5% |
| spikes >33 /run | +0.0% | -8.3% | -35.0% | -6.7% |
| spikes >50 /run | +0.0% | +0.0% | -11.1% | +0.0% |
| slow run ms | +12.7% | +1.9% | -2.5% | +3.8% |
| enemies peak | +0.0% | +0.0% | +0.0% | +0.0% |
| zones peak | +0.0% | +10.7% | +12.8% | +1.7% |
| draws avg | -1.4% | +3.5% | -11.3% | +7.7% |
| fog push lines /s | +17.7% | +16.9% | -13.8% | +23.1% |
| fog entries offered /s | +17.9% | +17.3% | -13.9% | +23.4% |
| fog entries accepted /s | +17.9% | +17.3% | -13.7% | +23.4% |
| fog entries dropped /s | +0.0% | +43.7% | -68.8% | +10.4% |
| fog dropped share % | +0.0% | +20.2% | -63.8% | -10.3% |
| fog entries per line | +0.2% | +0.3% | -0.0% | +0.2% |
| fog child scans /run | -40.4% | -40.5% | -56.5% | -37.8% |
| fog canvas hits /run | -40.4% | -40.5% | -56.5% | -37.8% |
| fog canvas draws /s | n/a | n/a | n/a | n/a |
| fog entries drawn /s | n/a | n/a | n/a | n/a |
| fog drawn share | n/a | n/a | n/a | n/a |
| fog draw us/s | n/a | n/a | n/a | n/a |
| fog draw us/frame | n/a | n/a | n/a | n/a |
| zone draw us/s | -34.7% | -28.8% | -45.5% | -27.8% |
| zone step us/s | +45.4% | +49.2% | +21.7% | +61.3% |
| zone total us/s | -13.0% | -9.4% | -27.1% | -5.0% |
| telegraph draws /s | -29.5% | -26.5% | -40.7% | -20.9% |
| telegraph draw us/s | -19.2% | -12.2% | -30.2% | -8.6% |
| shots created /s | +2.0% | +7.9% | -24.7% | +20.6% |
| shot exceptions /s | -100.0% | -100.0% | -100.0% | -100.0% |
| shot exceptions per shot | -100.0% | -100.0% | -100.0% | -100.0% |
| shot fog mirrors /s | +11.7% | +10.7% | -25.3% | +14.4% |
| status walks /s | +0.0% | +0.1% | +1.2% | -0.4% |
| status walks empty % | +0.0% | +0.0% | +0.0% | +0.0% |
| wall raycasts /s | -2.7% | -3.8% | -18.7% | +1.6% |
| raycasts skipped /s | -5.3% | +0.6% | -17.6% | +2.2% |
| path queries /s | +5.7% | +2.4% | +7.0% | -0.6% |
| path us/s | +10.6% | +1.9% | +10.8% | +0.4% |
| objects peak | +2.6% | +2.9% | -0.4% | +0.4% |
| canvas items peak | +6.1% | +8.0% | -4.4% | +3.5% |
| orphans peak | +0.0% | +0.0% | +0.0% | +0.0% |
| draws peak | -3.8% | +7.2% | -13.6% | +20.1% |
| phys max ms | +1.0% | -32.0% | -13.5% | -20.5% |
| phys frames >8 ms | -42.8% | +11.5% | -39.7% | +32.9% |
| phys frames >12 ms | -16.5% | +34.1% | -74.3% | +32.4% |

## Visual isolation, AFTER build, worst-load profile D

Each column switches ONE purely-visual product off and leaves damage, collision, timing, AI
and spawning running. A column that moves nothing is a cost already hidden by vsync, and is
reported as such rather than dressed up.

| metric | all on | vfx | labels | trails | fogcore | tddecor | particles |
|---|---:|---:|---:|---:|---:|---:|
| phys ms/frame | 6.858 | -4.3% | -7.6% | -5.6% | -11.5% | -10.5% | -10.2% |
| frame avg ms | 16.820 | +0.2% | +0.2% | +0.3% | +0.2% | +0.1% | +0.1% |
| draws avg | 648.7 | +6.1% | +1.3% | +2.3% | +2.7% | -3.6% | +1.3% |
| zone draw us/s | 15289.0 | -1.8% | -2.4% | -2.5% | -5.9% | -9.5% | -10.6% |
| telegraph draws /s | 344.8 | +0.2% | -6.1% | -4.7% | -3.2% | -9.0% | -6.6% |
| telegraph draw us/s | 14374.0 | -2.0% | -2.4% | -2.8% | -6.1% | -9.4% | -10.7% |
| zone total us/s | 27574.2 | +0.8% | -3.7% | -3.5% | -4.9% | -11.1% | -10.7% |

