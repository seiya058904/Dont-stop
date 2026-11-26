---
name: dont-stop-rendering-perf
description: Use when editing Camera2D.gd, Warmup.gd, MainUI.gd, web/loader.html, physics interpolation, pixel snapping, performance benchmarks, CDP traces, or B11Perf Stage 40 in Don't stop.
---

# Don't Stop Rendering, Warmup & Performance Evidence

## 1. Camera, Interpolation & Warmup Contracts
- Keep 60 Hz sim with selective physics interpolation, explicit teleport reset sequence, and vertex-only pixel snap (`snap_2d_transforms=false`, `snap_2d_vertices=true`).
- Web first-shot warmup (`MainUI.gd:_warm_web_first_use`, `Warmup.gd:prepare_web_first_shot`) MUST stay in menu-init under the loader behind a `frame_post_draw` barrier, compiling only targeted Canvas/muzzle/BulletSmoke variants (never move warmup to Start/camp).

## 2. Performance Evidence & `RISK-STAGE40`
- Benchmark fresh cold paths across 1080p/4K & refresh targets; align CDP/WebGL/event timelines; keep frame-time, draw-call, GC, and startup metrics distinct; attribute slow samples rather than averaging away spikes; keep Boss mechanism assertions intact.
- **`RISK-STAGE40` (P2 observe)**: Stage 40 node peak (`1522 > 1501.25` at t73 in `B11Perf.gd`) is an open observation — never relax the threshold to force green.
