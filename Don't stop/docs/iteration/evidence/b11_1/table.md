## Scenario C dense laser + root
build before=e22168f220f5 after=e05d7ada54d7
| metric | BEFORE | AFTER | delta |
|---|---:|---:|---:|
| **FRAME (user-visible, vsync-capped)** | | | |
| avg frame ms | 16.77 | 16.76 | -0.1% |
| p95 frame ms | 16.67 | 16.67 | +0.0% |
| p99 frame ms | 16.67 | 16.67 | +0.0% |
| max frame ms | 147.19 | 148.00 | +0.6% |
| frames >25ms | 8.00 | 6.00 | -25.0% |
| frames >33ms | 5.00 | 5.00 | +0.0% |
| frames >50ms | 4.00 | 4.00 | +0.0% |
| longest slow run ms | 185.00 | 148.00 | -20.0% |
| **PHYSICS CPU (vsync-independent)** | | | |
| phys avg ms | 5.64 | 5.36 | -4.9% |
| phys p95 ms | 8.12 | 8.04 | -1.1% |
| phys p99 ms | 12.44 | 13.15 | +5.7% |
| phys max ms | 21.20 | 22.75 | +7.4% |
| phys ticks >8ms | 284.00 | 272.00 | -4.2% |
| phys ticks >12ms | 104.00 | 106.00 | +1.9% |
| draw calls peak | 822.00 | 733.00 | -10.8% |
| **ROOTED vs NOT (phys ms)** | | | |
| rooted avg | 5.87 | 5.07 | -13.5% |
| not-rooted avg | 5.57 | 5.45 | -2.1% |
| rooted p95 | 9.07 | 6.43 | -29.1% |
| not-rooted p95 | 7.58 | 8.04 | +5.9% |
| hit+rooted avg | 5.65 | 5.23 | -7.6% |
| hit+rooted p95 | 8.12 | 6.43 | -20.8% |
| **ATTACK PIPELINE COST (ms over the run)** | | | |
| zone step | 617.13 | 504.96 | -18.2% |
| zone draw | 1513 | 1194 | -21.1% |
| clear_line | 585.57 | 338.41 | -42.2% |
| onHit | 340.30 | 268.08 | -21.2% |
| clear_line us / call | 12.17 | 6.77 | -44.4% |
| onHit us / hit | 316.85 | 278.67 | -12.0% |
| **COUNTERS (peak totals over the run)** | | | |
| wall raycasts | 11888 | 4699 | -60.5% |
| redundant clips skipped | 0 | 5655 | new |
| clear_line calls | 48114 | 49988 | +3.9% |
| player hits | 1074 | 962.00 | -10.4% |
| max hits in one frame | 5.00 | 9.00 | +80.0% |
| damage labels | 1133 | 1020 | -10.0% |
| fog pushes | 188054 | 172531 | -8.3% |
| rewards in group | 22.00 | 22.00 | +0.0% |
| fanout width peak | 0.00 | 22.00 | new |
| fanout rebuilds | 0 | 1 | new |
| fanout reuses | 0 | 961 | new |
| raycasts / s | 130.21 | 51.47 | -60.5% |
| clear_line / s | 526.99 | 547.51 | +3.9% |
| hits / s | 11.76 | 10.54 | -10.4% |
| **POPULATION PEAKS** | | | |
| enemies | 84.00 | 84.00 | +0.0% |
| hostile zones | 17.00 | 17.00 | +0.0% |
| firing lanes | 11.00 | 9.00 | -18.2% |
| damage labels live | 24.00 | 26.00 | +8.3% |
| nodes | 1668 | 1679 | +0.7% |
| nodes created | 8113 | 7669 | -5.5% |
| nodes removed | 7512 | 7073 | -5.8% |
| created / s | 88.86 | 84.00 | -5.5% |
| removed / s | 82.28 | 77.47 | -5.8% |

## Scenario C dense laser + root (repeat)
build before=e22168f220f5 after=e05d7ada54d7
| metric | BEFORE | AFTER | delta |
|---|---:|---:|---:|
| **FRAME (user-visible, vsync-capped)** | | | |
| avg frame ms | 16.76 | 16.76 | +0.0% |
| p95 frame ms | 16.67 | 16.67 | +0.0% |
| p99 frame ms | 16.67 | 16.67 | +0.0% |
| max frame ms | 144.02 | 143.90 | -0.1% |
| frames >25ms | 6.00 | 7.00 | +16.7% |
| frames >33ms | 6.00 | 5.00 | -16.7% |
| frames >50ms | 4.00 | 4.00 | +0.0% |
| longest slow run ms | 144.00 | 144.00 | +0.0% |
| **PHYSICS CPU (vsync-independent)** | | | |
| phys avg ms | 5.36 | 5.04 | -6.0% |
| phys p95 ms | 7.37 | 7.95 | +7.8% |
| phys p99 ms | 10.73 | 11.84 | +10.2% |
| phys max ms | 22.43 | 22.43 | +0.0% |
| phys ticks >8ms | 91.00 | 253.00 | +178.0% |
| phys ticks >12ms | 37.00 | 46.00 | +24.3% |
| draw calls peak | 775.00 | 793.00 | +2.3% |
| **ROOTED vs NOT (phys ms)** | | | |
| rooted avg | 5.48 | 5.07 | -7.5% |
| not-rooted avg | 5.33 | 5.03 | -5.6% |
| rooted p95 | 7.37 | 10.47 | +42.1% |
| not-rooted p95 | 7.25 | 7.95 | +9.5% |
| hit+rooted avg | 5.56 | 5.12 | -8.0% |
| hit+rooted p95 | 7.25 | 6.22 | -14.3% |
| **ATTACK PIPELINE COST (ms over the run)** | | | |
| zone step | 637.40 | 491.11 | -23.0% |
| zone draw | 1264 | 1184 | -6.3% |
| clear_line | 487.58 | 298.32 | -38.8% |
| onHit | 348.45 | 244.16 | -29.9% |
| clear_line us / call | 12.02 | 7.28 | -39.4% |
| onHit us / hit | 292.33 | 272.19 | -6.9% |
| **COUNTERS (peak totals over the run)** | | | |
| wall raycasts | 12071 | 5169 | -57.2% |
| redundant clips skipped | 0 | 6531 | new |
| clear_line calls | 40581 | 40958 | +0.9% |
| player hits | 1192 | 897.00 | -24.7% |
| max hits in one frame | 6.00 | 6.00 | +0.0% |
| damage labels | 1250 | 956.00 | -23.5% |
| fog pushes | 170707 | 158273 | -7.3% |
| rewards in group | 22.00 | 22.00 | +0.0% |
| fanout width peak | 0.00 | 22.00 | new |
| fanout rebuilds | 0 | 1 | new |
| fanout reuses | 0 | 896 | new |
| raycasts / s | 132.07 | 56.55 | -57.2% |
| clear_line / s | 443.99 | 448.12 | +0.9% |
| hits / s | 13.04 | 9.81 | -24.7% |
| **POPULATION PEAKS** | | | |
| enemies | 84.00 | 84.00 | +0.0% |
| hostile zones | 21.00 | 18.00 | -14.3% |
| firing lanes | 13.00 | 9.00 | -30.8% |
| damage labels live | 38.00 | 31.00 | -18.4% |
| nodes | 1680 | 1679 | -0.1% |
| nodes created | 8456 | 7354 | -13.0% |
| nodes removed | 7855 | 6759 | -14.0% |
| created / s | 92.52 | 80.46 | -13.0% |
| removed / s | 85.94 | 73.95 | -14.0% |

## Scenario A high count
build before=e22168f220f5 after=e05d7ada54d7
| metric | BEFORE | AFTER | delta |
|---|---:|---:|---:|
| **FRAME (user-visible, vsync-capped)** | | | |
| avg frame ms | 16.76 | 16.76 | +0.0% |
| p95 frame ms | 16.67 | 16.67 | +0.0% |
| p99 frame ms | 16.67 | 16.67 | +0.0% |
| max frame ms | 144.67 | 147.88 | +2.2% |
| frames >25ms | 6.00 | 6.00 | +0.0% |
| frames >33ms | 5.00 | 5.00 | +0.0% |
| frames >50ms | 5.00 | 5.00 | +0.0% |
| longest slow run ms | 145.00 | 148.00 | +2.1% |
| **PHYSICS CPU (vsync-independent)** | | | |
| phys avg ms | 5.42 | 5.34 | -1.6% |
| phys p95 ms | 7.64 | 7.84 | +2.6% |
| phys p99 ms | 19.32 | 12.08 | -37.5% |
| phys max ms | 20.29 | 21.15 | +4.3% |
| phys ticks >8ms | 159.00 | 220.00 | +38.4% |
| phys ticks >12ms | 73.00 | 71.00 | -2.7% |
| draw calls peak | 746.00 | 756.00 | +1.3% |
| **ROOTED vs NOT (phys ms)** | | | |
| rooted avg | 5.75 | 5.56 | -3.3% |
| not-rooted avg | 5.36 | 5.29 | -1.4% |
| rooted p95 | 9.36 | 7.84 | -16.2% |
| not-rooted p95 | 7.64 | 7.73 | +1.2% |
| hit+rooted avg | 5.86 | 5.49 | -6.3% |
| hit+rooted p95 | 9.36 | 7.84 | -16.2% |
| **ATTACK PIPELINE COST (ms over the run)** | | | |
| zone step | 489.06 | 466.45 | -4.6% |
| zone draw | 1227 | 1124 | -8.4% |
| clear_line | 489.75 | 284.64 | -41.9% |
| onHit | 272.20 | 283.18 | +4.0% |
| clear_line us / call | 11.72 | 7.46 | -36.4% |
| onHit us / hit | 308.27 | 288.96 | -6.3% |
| **COUNTERS (peak totals over the run)** | | | |
| wall raycasts | 8489 | 3758 | -55.7% |
| redundant clips skipped | 0 | 5238 | new |
| clear_line calls | 41781 | 38171 | -8.6% |
| player hits | 883.00 | 980.00 | +11.0% |
| max hits in one frame | 3.00 | 3.00 | +0.0% |
| damage labels | 926.00 | 1027 | +10.9% |
| fog pushes | 124254 | 129054 | +3.9% |
| rewards in group | 22.00 | 22.00 | +0.0% |
| fanout width peak | 0.00 | 22.00 | new |
| fanout rebuilds | 0 | 1 | new |
| fanout reuses | 0 | 979 | new |
| raycasts / s | 92.98 | 41.16 | -55.7% |
| clear_line / s | 457.62 | 418.08 | -8.6% |
| hits / s | 9.67 | 10.73 | +11.0% |
| **POPULATION PEAKS** | | | |
| enemies | 84.00 | 84.00 | +0.0% |
| hostile zones | 13.00 | 13.00 | +0.0% |
| firing lanes | 7.00 | 6.00 | -14.3% |
| damage labels live | 25.00 | 23.00 | -8.0% |
| nodes | 1666 | 1641 | -1.5% |
| nodes created | 7126 | 7142 | +0.2% |
| nodes removed | 6522 | 6543 | +0.3% |
| created / s | 78.05 | 78.23 | +0.2% |
| removed / s | 71.43 | 71.66 | +0.3% |

## Scenario B dense laser
build before=e22168f220f5 after=e05d7ada54d7
| metric | BEFORE | AFTER | delta |
|---|---:|---:|---:|
| **FRAME (user-visible, vsync-capped)** | | | |
| avg frame ms | 16.76 | 16.76 | +0.0% |
| p95 frame ms | 16.67 | 16.67 | +0.0% |
| p99 frame ms | 16.67 | 16.67 | +0.0% |
| max frame ms | 149.25 | 148.93 | -0.2% |
| frames >25ms | 6.00 | 7.00 | +16.7% |
| frames >33ms | 5.00 | 4.00 | -20.0% |
| frames >50ms | 4.00 | 4.00 | +0.0% |
| longest slow run ms | 149.00 | 149.00 | +0.0% |
| **PHYSICS CPU (vsync-independent)** | | | |
| phys avg ms | 6.06 | 5.73 | -5.4% |
| phys p95 ms | 10.37 | 9.22 | -11.1% |
| phys p99 ms | 21.78 | 21.88 | +0.5% |
| phys max ms | 21.78 | 21.88 | +0.5% |
| phys ticks >8ms | 458.00 | 399.00 | -12.9% |
| phys ticks >12ms | 116.00 | 56.00 | -51.7% |
| draw calls peak | 739.00 | 810.00 | +9.6% |
| **ROOTED vs NOT (phys ms)** | | | |
| rooted avg | 6.27 | 5.94 | -5.3% |
| not-rooted avg | 6.01 | 5.68 | -5.5% |
| rooted p95 | 11.10 | 11.66 | +5.0% |
| not-rooted p95 | 9.04 | 8.76 | -3.2% |
| hit+rooted avg | 6.32 | 5.92 | -6.3% |
| hit+rooted p95 | 11.93 | 9.63 | -19.3% |
| **ATTACK PIPELINE COST (ms over the run)** | | | |
| zone step | 587.89 | 612.88 | +4.2% |
| zone draw | 1243 | 1259 | +1.3% |
| clear_line | 569.29 | 280.65 | -50.7% |
| onHit | 326.01 | 348.38 | +6.9% |
| clear_line us / call | 12.24 | 7.66 | -37.4% |
| onHit us / hit | 308.43 | 278.92 | -9.6% |
| **COUNTERS (peak totals over the run)** | | | |
| wall raycasts | 12106 | 5745 | -52.5% |
| redundant clips skipped | 0 | 7125 | new |
| clear_line calls | 46510 | 36617 | -21.3% |
| player hits | 1057 | 1249 | +18.2% |
| max hits in one frame | 8.00 | 8.00 | +0.0% |
| damage labels | 1103 | 1300 | +17.9% |
| fog pushes | 168519 | 175628 | +4.2% |
| rewards in group | 22.00 | 22.00 | +0.0% |
| fanout width peak | 0.00 | 22.00 | new |
| fanout rebuilds | 0 | 1 | new |
| fanout reuses | 0 | 1248 | new |
| raycasts / s | 132.60 | 62.92 | -52.5% |
| clear_line / s | 509.42 | 401.06 | -21.3% |
| hits / s | 11.58 | 13.68 | +18.2% |
| **POPULATION PEAKS** | | | |
| enemies | 84.00 | 84.00 | +0.0% |
| hostile zones | 16.00 | 18.00 | +12.5% |
| firing lanes | 9.00 | 10.00 | +11.1% |
| damage labels live | 27.00 | 27.00 | +0.0% |
| nodes | 1662 | 1679 | +1.0% |
| nodes created | 7751 | 8374 | +8.0% |
| nodes removed | 7158 | 7771 | +8.6% |
| created / s | 84.90 | 91.72 | +8.0% |
| removed / s | 78.40 | 85.12 | +8.6% |

## Scenario D rooted inside coverage
build before=e22168f220f5 after=e05d7ada54d7
| metric | BEFORE | AFTER | delta |
|---|---:|---:|---:|
| **FRAME (user-visible, vsync-capped)** | | | |
| avg frame ms | 16.74 | 16.74 | +0.0% |
| p95 frame ms | 16.67 | 16.67 | +0.0% |
| p99 frame ms | 16.67 | 16.67 | +0.0% |
| max frame ms | 144.04 | 148.68 | +3.2% |
| frames >25ms | 6.00 | 5.00 | -16.7% |
| frames >33ms | 5.00 | 5.00 | +0.0% |
| frames >50ms | 3.00 | 3.00 | +0.0% |
| longest slow run ms | 181.00 | 199.00 | +9.9% |
| **PHYSICS CPU (vsync-independent)** | | | |
| phys avg ms | 5.38 | 5.16 | -4.2% |
| phys p95 ms | 7.08 | 7.14 | +0.8% |
| phys p99 ms | 13.99 | 11.90 | -15.0% |
| phys max ms | 21.98 | 22.44 | +2.1% |
| phys ticks >8ms | 253.00 | 218.00 | -13.8% |
| phys ticks >12ms | 112.00 | 51.00 | -54.5% |
| draw calls peak | 767.00 | 726.00 | -5.3% |
| **ROOTED vs NOT (phys ms)** | | | |
| rooted avg | 5.34 | 5.14 | -3.7% |
| not-rooted avg | 5.39 | 5.16 | -4.3% |
| rooted p95 | 8.58 | 8.15 | -5.0% |
| not-rooted p95 | 7.08 | 6.94 | -2.0% |
| hit+rooted avg | 5.58 | 5.17 | -7.4% |
| hit+rooted p95 | 7.08 | 7.14 | +0.8% |
| **ATTACK PIPELINE COST (ms over the run)** | | | |
| zone step | 739.25 | 593.84 | -19.7% |
| zone draw | 1484 | 1326 | -10.7% |
| clear_line | 418.20 | 342.20 | -18.2% |
| onHit | 413.76 | 337.90 | -18.3% |
| clear_line us / call | 13.37 | 7.45 | -44.3% |
| onHit us / hit | 286.34 | 265.44 | -7.3% |
| **COUNTERS (peak totals over the run)** | | | |
| wall raycasts | 13649 | 5637 | -58.7% |
| redundant clips skipped | 0 | 6324 | new |
| clear_line calls | 31287 | 45942 | +46.8% |
| player hits | 1445 | 1273 | -11.9% |
| max hits in one frame | 8.00 | 8.00 | +0.0% |
| damage labels | 1504 | 1333 | -11.4% |
| fog pushes | 172442 | 141950 | -17.7% |
| rewards in group | 22.00 | 22.00 | +0.0% |
| fanout width peak | 0.00 | 22.00 | new |
| fanout rebuilds | 0 | 1 | new |
| fanout reuses | 0 | 1272 | new |
| raycasts / s | 151.49 | 62.56 | -58.7% |
| clear_line / s | 347.25 | 509.90 | +46.8% |
| hits / s | 16.04 | 14.13 | -11.9% |
| **POPULATION PEAKS** | | | |
| enemies | 84.00 | 84.00 | +0.0% |
| hostile zones | 22.00 | 19.00 | -13.6% |
| firing lanes | 10.00 | 9.00 | -10.0% |
| damage labels live | 39.00 | 29.00 | -25.6% |
| nodes | 1674 | 1675 | +0.1% |
| nodes created | 8910 | 7756 | -13.0% |
| nodes removed | 8307 | 7153 | -13.9% |
| created / s | 98.89 | 86.08 | -13.0% |
| removed / s | 92.20 | 79.39 | -13.9% |

