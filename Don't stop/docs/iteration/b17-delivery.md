# B17 review delivery

HUMAN_ACCEPTED=false. Implementation and candidate artifacts are delivered; acceptance is **not all green**. Keep PR15 Draft, do not merge/deploy/release.

## Candidate identity

Production commit: `80aae7255ac16256df944af6e68f04adbdd68696`. Later evidence/test/report commits do not mean the game was rebuilt from their SHA.

|Artifact|Project-relative local path|
|---|---|
|Playable Windows ZIP|`build/b17-windows.zip`|
|Executable and matching PCK|`build/b17-windows/Don't stop.exe`, `build/b17-windows/Don't stop.pck`|
|Local Web export|`build/b17-web/index.html` (serve over HTTP)|
|Final native frames, OFF/ON, 8 directions, clips|`evidence/visual-upgrade-20260919/b17-delivery-native/`|
|Final Web interaction video/screenshots/result|`evidence/visual-upgrade-20260919/b17-delivery-web/`|

ZIP SHA256: `66c3498e43f97d7e3d27f0dada8bd6a7fdece0076f1c510f80a47db473a59f3b`.
Web payload digest: `b3e597c2c451a9693f8c5c98b58f6acd0124dcdc3b1885232c242deb65af2495`.
Per-file hashes are in `evidence/b17/windows-identity.json` and `web-identity.json`. B16 artifacts remain intact. The first B17 candidate ZIP is separately preserved as `build/b17-windows-first-candidate.zip`.

## Verified on this exported candidate

- Windows returned exit0, 50 DPI-aware physical window captures, no `SCRIPT ERROR` or `ERROR`. Actual framebuffers capture all five camp pages and five empty-hand stat tabs at 1280×720, 1366×768, 1536×864 and 1920×1080 requested sizes. Aspect-preserving framebuffer height may be 2–3px shorter; the OS captures include the complete window. No 410×230 post-upscale is used.
- Eleven high-tier weapons plus ordinary0 have dark-background OFF/ON, eight directions and six-second idle/move/fire clips. Eleven high-tier weapons also have normal-background OFF/ON. Shop preview shares the held renderer.
- Web: fresh storage, actual mouse/keyboard, weapon/A9 purchases, T04 paid ranks0–3, T09 upgrades, all five pages at four sizes, normal stage31 shooting/movement, actual meteor descent and impact. `web-validation.json` reports success. Initial relative-root server403 and failed native screenshot/DPI attempts remain in the raw directory, not counted as successful evidence.
- Native exit still reports **16 RefCounted instances, reference count0**. Earlier native observations reported13/17/22; all warning logs remain. No ownership chain was established, no log was suppressed, and these counts alone do not prove cumulative runtime memory growth. Verbose image-format conversion warnings also remain in delivery.json.

## Gameplay / performance / CI boundaries

See `b17-status.md`, `b17-difficulty.md`, `b17-sources.md`, `b17-protocols.md` and `evidence/b17/performance.json`.

Normal-health level20 autonomous observations completed all four bosses, including B04 in30.64s. The earlier non-fixed-level B04 death remains a separate failure. Five ordinary encounters completed. Three-phase barrage observation uses HP refill and is not substituted for either result.

The current source/data gate retains a **FAIL for gun113 late horde:81 kills versus85**. No threshold or weapon power was adjusted to force a pass. The evidence manifest seals313 sources and10 datasets, including actual benchmark implementations. B14 evidence remains frozen. Full 72-source event/lifecycle combinations and human visual/safe-route judgement are not claimed complete.

Current local source gates: growth355 checks pass; weapon475 checks pass and1 fails (the retained rail floor). These counts include manifest checks. Remote CI status is reported in the Draft PR/current task; it is not inferred from local results.

Fixed430-zone p99: B16 7.597ms → B17 7.718ms. Product paired39 three seeds and bounded upper1.5× current settings are separate protocols. True per-frame CPU/GPU are N/A. Raw long-frame failures remain. Sampling was separated from screenshot capture/video compression.
