# B批 证据目录

本目录中的每个数字都由本分支上的真实运行产生，命令与断言在
`docs/iteration/../B-BATCH.md`（`docs/iteration/B-BATCH.md`）中逐条对应。

| 文件 | 内容 | 产生者 |
| --- | --- | --- |
| `gate-summary.json` | 每个场景的 PASS/FAIL/SCRIPT ERROR 计数与失败行 | `tools/b-final.ps1` |
| `raw-measurements.txt` | 各场景打印的测量行，逐字保留 | 同上，从运行日志抽取 |
| `density.json` | `M10Density` 全部行（typical/strong × probe/drive） | `tests/M10Density.gd` |
| `density-baseline-b0.json` | **改动前** `origin/main` 的 density 基线（strong, 22/26/29） | B0 审计 |
| `density-baseline-b0-typical.json` | **改动前** 的 typical+probe 基线（7/13/17/22/26/29） | B0 审计 |
| `bosses-authored.json` | `M10Bosses` 在 authored 8 HP 难度下的 TTK / clear / 受击 | `tests/M10Bosses.gd` |
| `bosses.json` | `B5Bosses`：10/20/30/40 的三阶段契约、真实火力击杀、百分比终极、阶段切换 | `tests/B5Bosses.gd` |
| `fog-*.png` | 同一张地图、同一玩家位置的 A/B/A2 对照，以及产品态 Stage 31 | `tests/B4Fog.gd`（gl_compatibility） |
| `fog-read-*.png` | charge / beam / poison 三种关键预警在迷雾下的可读性 | 同上 |
| `region-R2..R8.png` | R2–R8 同视口地图辨识度 | `tests/BVisual.gd` |
| `ui-*.png` | charge / detonate / beam / artillery / root / sweep / shock / poison / frost 的 warning、将发、生效三态 | 同上 |
| `boss-B03/B04-*.png` | Normal 终局 Boss 与 Hell 终局 Boss 的 Phase III 与百分比终极 | 同上 |
| `telegraph-host-R6.png` / `telegraph-hell-R7.png` | 攻击 UI 在普通亮度与迷雾下的同视口对照 | 同上 |

## 关于测试装置的两条说明（写在证据旁边，避免误读）

1. **原生 rig 的瞄准坐标**会解析到 root viewport，而战斗场地在
   `(10000+N*1000,-6000)`。`Camera2D._process()` 于是追一个失控的偏移，
   并把作为其子节点的原版视野灯一起拖走。`tests/B8Runtime.gd` 冻结这个追随并用一台
   放在玩家身上的相机渲染，复现的是**产品里真实的关系（玩家→灯在屏幕中心）**，
   而不是测试窗口的产物。这是装置调整，不是产品改动。
2. **Fog 的亮度断言只在渲染运行中生效**（`--rendering-method gl_compatibility`，Web 用的渲染器）。
   `--headless` 下 SubViewport 的 render target 是关闭的，读不到像素；
   此时 `B4Fog` 仍然执行全部契约断言，只是跳过像素部分，并在日志里明说。
