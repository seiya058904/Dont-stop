# M9 final evidence

`M9 FINAL POLISH COMPLETE / READY FOR FINAL HUMAN ACCEPTANCE`

`HUMAN_ACCEPTED = false`

[Final report, limitations and short human route](../../M9-FINAL-POLISH.md)

[Engineering gates](summary.json): all 11 true; human acceptance false.
[Source contracts](source-contracts.json), [24-weapon audit and screenshots](WEAPON-AUDIT.md), [CSV](weapon-matrix.csv), [JSON](weapon-matrix.json).

Authoritative runs:
- beam-final-camera: 312 checks; presentation-final-v1: 144 cases; paths-final-v1: 8 checks.
- power-raw-v2 / power-final-v1: final single and Boss dummy data.
- crowd-raw-final / crowd-build-final: final complete crowd data, superseding earlier crowd rows.
- barrage-final-v2: 9 checks / 30 patterns; bosses-high-v2 / bosses-full-v2: six live clears.
- regions-final-v3: 27 checks and six PNGs; weapons-visual-final-v2: 24 PNGs.
- beam-visual-final-v1 and barrage-visual-final: native presentation captures.
- catalog-final-v2: 50 checks, native shop PNG, exit 0.
- summary.json regression: 22 passing entries, including regression-10-R1LegacyRestore-recheck.
- perf-baseline-* / perf-final-* and perf-confirm/third projectile pairs: sequential native performance.

Each run retains execution.json source hashes, command, isolated snapshot path and raw run.txt. Input substitutions are listed. Headless wall-clock time is not rendering performance. All unsuccessful and superseded evidence remains available; the final report explains sampler corrections, burn/level/crowd fixture corrections, initial barrage failures, legacy restore setup, paused catalog capture, known MP3 teardown diagnostics and the retained 55.126ms stress spike. No human acceptance is inferred from screenshots or robots.
