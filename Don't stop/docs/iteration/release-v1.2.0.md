# Don't Stop v1.2.0 — Release Verification

Release candidate: `0422fdde97addba2d53eb3c163b8367e1b557d20`.

This closeout preserves the candidate's presentation and gameplay behavior. It sets the Windows product version to 1.2.0 and removes an unused root-level debug scene, its loose PNG, and the PNG import sidecar. Both export presets also exclude those exact debug paths, along with the existing test, evidence, documentation, tools, output, and build directories.

## Verification

| Area | Result |
| --- | --- |
| Godot 4.7.2 import | Two consecutive imports succeeded after source cleanup. |
| Native regression | 670 assertions passed across BaselineRegression, B194Contracts, B17Contracts, M3Weapons, CampPresentation, PresentationContracts, PresentationRng, PresentationLifecycle, FinalPolish, BeamPerformance, and M9Beam. |
| Windows Release | Export succeeded. The unpacked portable ZIP completed the camp-to-combat smoke with exit code 0. The 2,400-frame steady sample reported p50/p95/p99/max of 6.3 ms. Weapon first-shot maxima ranged from 6.3 to 6.7 ms. |
| Web Release | Export and build-identity stamping succeeded. Playwright smoke passed loading, live canvas, camp, combat, weapon switch, fire, HTTP, and browser-console checks. |
| Web real-input path | Bought and equipped four weapons, departed for stage 39, fired each, and entered stage 40. Screenshots showed the full camp panel and combat HUD at 1280×720. |
| Boom Boi first use | On RX 7900 XT / Chromium D3D11, three cold shots and the first dash each had a maximum RAF gap of 16.8 ms; no browser long tasks were recorded in those measurement windows. |
| Web save and lifecycle | Fresh profile, reload, browser restart, IndexedDB persistence, profile isolation, pause/resume, two real menu returns and session recreation all passed. No page, engine, or HTTP errors were reported. |
| Export contents | Windows and Web PCKs exclude the test scene, loose debug PNG, tests, docs, tools, evidence, output, and build paths. |

The Windows startup trace recorded one 1,007 ms frame gap around the automated first camp transition at approximately 3.9 seconds. Trace markers place the title menu at 1.42 seconds from the trace origin, 400 ms after Utils initialized; no comparable gap appeared in the Windows firing or steady-state measurements. The hardware-rendered Web entry to camp had no RAF gap over 50 ms. This isolated native startup observation did not block the game flow, so it was not expanded into a late presentation change.

## Review boundary

The existing rendered menu, camp, Boss HUD, reward, and result captures were inspected, and the FinalPolish UI regression passed 50/50. These are automated and rendered checks, not human aesthetic sign-off. A complete manual 40-stage campaign clear was not performed; the Web playtest reached stages 39 and 40, while reward/result callbacks and cleanup were covered by the targeted regression suite.

The Windows portable package contains the Release executable and its matching PCK. The Web deployment is verified separately against the exact `main` commit and the Pages build identity after CI completes.
