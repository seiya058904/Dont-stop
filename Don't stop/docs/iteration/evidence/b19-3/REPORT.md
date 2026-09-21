# B19.3 Performance Closure with Startup

**Status:** NOT_ATTAINED
**ENGINEERING_PERF_ACCEPTED:** false
**HUMAN_ACCEPTED:** false

本报告记录对附加规格 CODEX-B19.3-PERFORMANCE-CLOSURE-WITH-STARTUP.md 及其 R2 focused closure continuation 的仓库内执行结果。文档内容作为实现、验证和证据边界；没有执行推送、合并、部署或发布。

结论先行：本轮最终 weakref2 导出已完成 Boss 生命周期收口，Web/Windows Stage40 B 的完整相位证据和无脚本错误复核通过，B191/B4/B19/B192 受影响回归也通过。Web P 在 180 敌人/180 投射物正式压力下 p95=20.0 ms，高于 18.5 ms 阈值；Web 冷启动仍有三段 long task。因此本轮不能把 ENGINEERING_PERF_ACCEPTED 标为 true。HUMAN_ACCEPTED 仍必须由用户完成真实视觉和游玩验收。

## Scope and source identity

- Godot 4.7.2-stable official。
- native 默认 Forward+；Web 使用 Compatibility、Web 单线程配置；没有迁移渲染器、减少敌人/投射物/寿命/伤害/碰撞/分辨率或视觉质量。
- Windows Release 和 Web Release 使用同一当前源代码；最终 weakref2 导出的 Windows PCK 与 Web index.pck SHA-256 均为 00A70FB6D93DFD56C4C8B359CA44B16A82A0A7E7079691D4E592E8723A64EEFA。
- 最终构建身份：
  - Windows Don't stop.exe：DDACA81DEF3824832BD659CFDA86E9D78CF2B2317743D58FC99BD545A6151655
  - Web index.wasm：FC74679E3B97F76878947FCD4FBE1268CBFA6188182A2E33BBC3F5DC9BFA57D0
  - Web index.pck：00A70FB6D93DFD56C4C8B359CA44B16A82A0A7E7079691D4E592E8723A64EEFA
  - Web index.js：33C94CB3175F3333B82E2A3BE5E8E86F77986F0AA2042B1631F6367A4E5BB6BA
  - Web index.html：F9C6E8DD7B98FFB536658AE95BB557435543EAA15F0102D16489AEFFA0666918
  - Web driver identity：ac75000280b84a6bc870e5f963ef1aa164ba2783371617756a9a1ad3cfaea288

## Implemented changes

1. P0 Boss lifecycle

   LevelServer.return_to_camp() 和 Demo.release_session_nodes() 清除 Boss 的 weak reference 与兼容 ID；BossHUD、B11Stress 和启动 lesson 通过有效 weak reference 读取 Boss；victory 使用 round epoch 防止 deferred death 读到旧实例。TacticalEnemy 的召唤子节点和 MechanismProjectile 的 visited 目标也保留 weak reference，避免离开战斗后再次访问失效 slot。这样修复了旧流程离开战斗返回菜单后再次访问失效 slot 的问题，同时保留完整 Stage40 行为。

2. Spawn hotspot

   CombatArena 保留随机候选顺序、动态 occupancy、clearance、wall/actor geometry 和路径语义，只把静态且 immutable 的 reachability topology 做一次缓存。动态 clearance 仍每次检查，未将静态缓存误用为运行时碰撞结论。B11Probe 和 B11Stress 增加 ordinary request、elite request/promotion、geometry、clearance、path hit/miss、arena failure、group peak 等计数。

3. Startup and warmup

   Boot 等待 Warmup.finished 的真实状态；Utils、MainUI、Boot 和 loader 记录阶段、首个可见菜单、hover、Settings 和 Start feedback。Warmup 保持完整生产 warmup 场景，但用同一 Monster 贴图构建 lit Canvas 的 SpriteFrames，避免为预热重复实例化完整 gameplay actor；粒子仍以真实 GPUParticles2D 预热。Web warmup 使用有界批次并记录 effect_scenes_ms、weapon_scenes_ms 和 slowest_item。

4. Web rendering diagnosis

   web/loader.html 在两个 WebGL 原型上只缓存确认的 SCISSOR_TEST 查询状态；其他 getParameter 查询、参数、this、返回值和错误行为保持原样。B192_TRACE=1 时的 getParameter/viewport/texture/shader 诊断仅写 bounded JSON，不在正式运行中逐调用打印。

5. Regression coverage

   B192Spawn 增加同半径 actor/wall、普通/wall-only、排除 actor 以及调用顺序变化的真实回归断言；静态解析、导出、启动、Web 交互和三平台压力均使用当前源代码或最终导出验证。

6. R2 focused closure

   当前源代码保留 EnemyShot 的精确线段命中测试与 layer-32 合同；M5Content 只为 E01 保留旧 Area2D 接触合同，其他生产角色关闭空闲接触传感器；B11Stress 使用真实 EnemyShot、180 上限、3.2/5.2 秒寿命和压力采样。当前热路径没有通过降低内容密度取得性能收益。

## Startup evidence

下面的 native/Windows 行是上一轮 final export 的启动快照；最终 weakref2 Web 冷启动、阶段和交互证据使用当前导出，避免把旧导出哈希冒充为当前导出。

| Surface | Evidence | Result |
|---|---|---|
| native | output/b19-3/r2-final-native-startup/native-start.log | scene-load-100 593 ms since_utils；warmup 138 ms；menu-first-visible 1012 ms；all-frame max 39 ms，over50=0；菜单窗口 p95/p99/max=7/7/34 ms，over50=0 |
| Windows Release cold | output/b19-3/r2-final-windows-startup/cold-start.log | scene-load-100 209 ms；warmup 162 ms；menu-first-visible 636 ms；all-frame max 36 ms，over50=0；菜单 10 秒 p95/p99/max=7/7/30 ms |
| Windows Release warm | output/b19-3/r2-final-windows-startup/warm-start.log | warmup 163 ms；menu-first-visible 665 ms；all-frame max 37 ms，over50=0；菜单 10 秒 p95/p99/max=7/7/31 ms |
| Web cold Chromium final weakref2 | output/b19-3/r2-final-weakref2-web-startup/b193-web-startup.json | ready 11302 ms；download 228.9 ms；warmup 3252 ms；scene-prep 3288.2 ms；menu-first-visible 5689.4 ms；warmup-done 10747.4 ms |
| Web interaction final weakref2 | same Web startup report | real mouse hover、Settings open/close、Start 全部 ok；page_errors=[]，http_errors=[] |
| Web long tasks final weakref2 | same Web startup report | 230.7+5459 ms、5689.9+3312 ms、9035.4+1477 ms；未闭合 |
| Web menu frames final weakref2 | same Web startup report | samples=600，p95/p99/max=16.8/16.8/16.8 ms，over50/100/250/1000=0 |

上一轮 Web 冷加载的 long-task 证据仍存在；当前源代码的新鲜 R2 证据见“R2 current-source closure rerun”。发布版没有可用的逐项 C++ 调用栈，因此这里只报告实际阶段归属，不编造函数级根因。

## Spawn A/B evidence

证据位于 output/b19-3/r2-spawn-before 和 output/b19-3/r2-spawn-after-seed。两次使用相同 Stage39、scenario B、seed=20260920 和武器集合；运行间动态战斗数量允许自然波动。

| Run | path checks / queries / cache hits | dynamic checks | result |
|---|---:|---|---|
| no cache | 760 / 760 / 0 | geometry rejected 276422；clearance queries 11808；arena_failed=0；ordinary_added=48 | 所有可达候选 760/760，path_rejected=0 |
| topology cache | 759 / 618 / 141 | geometry rejected 278404；clearance queries 11096；arena_failed=0；ordinary_added=48 | 静态 A* miss 约减少 18.7%；path_rejected=0 |

同一段 B11 scoped spawn_path 从 832 calls / 6673 usec 降为 661 calls / 5355 usec。此优化只缓存静态 topology；正式 P 运行仍记录动态 clearance 和 ordinary/elite 请求，未通过减少内容来取得收益。

## Same-source pressure evidence (prior R2 snapshot)

本表保留上一轮 R2 final export 快照。正式阈值按规格使用 p95、p99 和 >33.3 ms 占比；表中 over33 是实际帧数，百分比按该次 frame count 计算。当前源代码复测见下节。B 在 Boss 完整三阶段完成后自然结束，requested=150 s、实际 combat 约 80 s；这不是把未完成流程提前结束。

| Surface | Case | combat / frames | p95 / p99 / max ms | over33 / frames | Peak coverage | Gate |
|---|---|---:|---:|---:|---|---|
| native | H | 45.0 s / 7167 | 10.19 / 11.95 / 56.87 | 3 / 0.042% | enemies 155 | PASS |
| native | M | 45.0 s / 7166 | 10.39 / 12.59 / 56.17 | 3 / 0.042% | enemies 146 | PASS |
| native | B | 80.3 s / 12798 | 7.48 / 8.17 / 99.35 | 2 / 0.016% | Stage40 boss_complete；phase 1/2/3、continuous barrage、ultimate、safe-zone pause、reflect actions present | PASS |
| native | P | 30.0 s / 3777 | 14.49 / 18.22 / 69.38 | 9 / 0.238% | enemies 180；projectiles 180 | PASS |
| Windows Release | H | 45.0 s / 7168 | 9.33 / 10.56 / 101.80 | 2 / 0.028% | enemies 123 | PASS |
| Windows Release | M | 45.0 s / 7191 | 10.25 / 11.58 / 33.16 | 1 / 0.014% | enemies 153 | PASS |
| Windows Release | B | 80.3 s / 12823 | 7.28 / 7.76 / 73.20 | 1 / 0.008% | Stage40 boss_complete；完整 phase/action evidence | PASS |
| Windows Release | P | 30.0 s / 4676 | 11.23 / 13.16 / 50.76 | 8 / 0.171% | enemies 180；projectiles 180 | PASS |
| Web Release | H | 45.0 s / 5927 | 13.60 / 15.90 / 1188.30 | 3 / 0.051% | enemies 127 | PASS |
| Web Release | M | 45.0 s / 5707 | 14.40 / 17.20 / 57.80 | 3 / 0.053% | enemies 153 | PASS |
| Web Release | B | 80.2 s / 12670 | 7.80 / 9.70 / 1190.90 | 1 / 0.008% | boss_complete=true；Stage40 phase/action evidence | PASS |
| Web Release | P | 30.0 s / 2607 | 19.90 / 24.80 / 71.10 | 14 / 0.537% | enemies 180；projectiles 180 | FAIL |

上一轮 Web P 的失败是实际物理/密度压力，不是启动器错误；当前源代码复测的压力、帧阈值和启动结果见下节，不能通过降低密度来修复。

## WebGL diagnosis evidence

output/b19-3/r2-web-m-trace 和 output/b19-3/r2-web-p-trace 的真实 Chromium ANGLE D3D11 诊断确认，基线最重调用是 pname 3089，即 SCISSOR_TEST：M 1974 次、约 3946.6 ms；P 1383 次、约 3076.5 ms，调用栈稳定落在 offscreen framebuffer commit。生产 shell 加入有限状态缓存后，3089 查询从 M/P trace 中消失；缓存版本的诊断 P 达到 p95/p99=18.2/21.3 ms。最终正式 P 使用全新冷页面和完整场景复测，p95/p99=20.0/25.1 ms，因此没有把诊断版的最好结果冒充正式闭环。

## R2 current-source closure rerun

以下是当前源代码、当前导出和隔离数据目录上的证据。上面的完整 H/M/B/P 表保留为 weakref2 之前的 R2 current-source snapshot；最终 weakref2 对窄范围生命周期改动重新执行 B、P、冷启动和受影响回归，下面的 targeted rerun 不把未重跑的 H/M/native/Windows 行重新标成新鲜结果。

### Current startup

| Surface | Evidence | Result |
|---|---|---|
| Web cold Chromium | output/b19-3/r2-final-weakref2-web-startup/b193-web-startup.json | ready 11302 ms；download 228.9 ms；warmup 3252 ms；scene-prep 3288.2 ms；menu-first-visible 5689.4 ms；warmup-done 10747.4 ms |
| Web long tasks | same report | 230.7+5459 ms、5689.9+3312 ms、9035.4+1477 ms；首个长任务跨 download→engine-init，后两段与 production warmup/effect/weapon/finish 重叠；未闭合 |
| Web interaction | same report | real mouse hover、Settings open/close、Start 全部 ok；page_errors=[]；http_errors=[] |
| Web menu frames | same report | samples=600，p95/p99/max=16.8/16.8/16.8 ms，over50/100/250/1000=0 |

### Current pressure matrix (weakref2 前的 R2 snapshot)

| Surface | Case | combat / frames | p95 / p99 / max ms | over33 / frames | Physics p95 ms | Peak coverage | Gate |
|---|---|---:|---:|---:|---:|---|---|
| native | H | 45.0 s / 7142 | 13.58 / 14.64 / 77.79 | 4 / 0.056% | 17.461 | enemies 180；projectiles 7 | PASS |
| native | M | 45.0 s / 7141 | 13.81 / 15.74 / 101.64 | 4 / 0.056% | 19.732 | enemies 180；projectiles 13 | PASS |
| native | B | 80.3 s / 12820 | 6.25 / 7.88 / 67.10 | 1 / 0.008% | 3.056 | boss_complete；phase 1/2/3、continuous barrage、ultimate、safe-window evidence；projectiles 179 | PASS |
| native | P | 30.0 s / 3867 | 13.27 / 16.64 / 104.42 | 6 / 0.155% | 36.417 | enemies 180；projectiles 180；pressure live/visible ratio 0.9965 | PASS |
| Windows Release | H | 45.0 s / 7175 | 12.59 / 13.47 / 71.23 | 2 / 0.028% | 10.828 | enemies 180；projectiles 6 | PASS |
| Windows Release | M | 45.0 s / 7172 | 12.47 / 13.38 / 72.46 | 2 / 0.028% | 10.605 | enemies 180；projectiles 14 | PASS |
| Windows Release | B | 80.3 s / 12820 | 7.43 / 7.88 / 67.10 | 1 / 0.008% | 3.056 | boss_complete；完整 phase/action evidence；projectiles 179 | PASS |
| Windows Release | P | 30.0 s / 4759 | 12.66 / 13.79 / 78.61 | 3 / 0.063% | 26.136 | enemies 180；projectiles 180；pressure live/visible ratio 0.9932 | PASS |
| Web Release | H | 45.0 s / 2688 | 18.40 / 20.20 / 1357.70 | 4 / 0.149% | 11.3 | enemies 180；projectiles 7 | PASS |
| Web Release | M | 45.0 s / 2697 | 18.60 / 20.70 / 54.60 | 2 / 0.074% | 14.5 | enemies 180；projectiles 10 | PASS |
| Web Release | B | 80.2 s / 4806 | 18.10 / 18.80 / 1330.50 | 2 / 0.042% | 3.8 | controlled_boss=true；boss_complete=true；phase 1/2/3、safe-window、continuous、ultimate evidence；projectiles 147 | PASS |
| Web Release | P | 30.0 s / 1792 | 19.00 / 22.40 / 56.50 | 5 / 0.279% | 44.6 | enemies 180；projectiles 180；pressure samples 280；live/visible ratio 0.9964 | FAIL (p95 only) |

该 snapshot 的 Web P 失败为 p95=19.0 ms 对 18.5 ms 的阈值超出；p99=22.4 ms、over33=0.279% 均通过。最终 weakref2 定向复测见下节，压力上限仍达到 enemies/projectiles 180，没有通过削减内容取得结果。

### Final weakref2 targeted rerun

这些证据来自最终 weakref2 源代码和最终导出；Web B/P 与 Windows B 使用同一 driver identity `ac75000280b84a6bc870e5f963ef1aa164ba2783371617756a9a1ad3cfaea288`。

| Surface | Case | combat / frames | p95 / p99 / max ms | over33 / frames | Peak / runtime evidence | Gate |
|---|---|---:|---:|---:|---|---|
| Web Release | B | 80.2 s / 4805 | 18.20 / 18.90 / 1336.50 | 2 / 0.042% | boss_complete=true；errors=[]；console_errors=[]；完整 Stage40 phase/action evidence | PASS |
| Windows Release | B | 80.3 s / 12837 | 7.24 / 7.72 / 18.13 | 0 / 0.000% | boss_complete=true；stderr 仅有 19 ObjectDB leaked-at-exit warning，无脚本错误 | PASS* |
| Web Release | P | 30.0 s / 1778 | 20.00 / 25.10 / 86.80 | 9 / 0.506% | enemies 180；projectiles 180；errors=[]；physics p95=69.30 ms | FAIL (p95 only) |

`PASS*` 表示 Windows B 的运行、Boss 完整结束和脚本错误检查通过，但 stderr 的 19 个 ObjectDB leaked-at-exit warning 保留为未闭合的工程残留；它没有被隐藏或计为零错误。

### Current regression, export and artifact checks

- Headless editor parse check：exit 0，证据位于 output/b19-3/r2-closure-parse/。
- Windows Release export：exit 0，build/b193-r2-closure-windows/。
- Web Release export：exit 0，build/b193-r2-closure-web/。
- weakref2 受影响回归新鲜通过：B191Runtime 55/55、B4Fog 110/110、B19Contracts 24/24、B192Safety 9/9；证据位于 output/b19-3/r2-final-weakref2-regression/。完整范围的上一轮结果仍保留为 prior snapshot：B192Spawn 127/127、B18Contracts 92/92、B12LineOfSightRegression 12/12、B3Hazards 128/128、B6Progression 41/41。
- 当前最终导出构建哈希：Web index.html F9C6E8DD7B98FFB536658AE95BB557435543EAA15F0102D16489AEFFA0666918；index.js 33C94CB3175F3333B82E2A3BE5E8E86F77986F0AA2042B1631F6367A4E5BB6BA；index.wasm FC74679E3B97F76878947FCD4FBE1268CBFA6188182A2E33BBC3F5DC9BFA57D0；index.pck 00A70FB6D93DFD56C4C8B359CA44B16A82A0A7E7079691D4E592E8723A64EEFA。Windows Don't stop.exe DDACA81DEF3824832BD659CFDA86E9D78CF2B2317743D58FC99BD545A6151655；Don't stop.pck 00A70FB6D93DFD56C4C8B359CA44B16A82A0A7E7079691D4E592E8723A64EEFA。
- 最终 Windows B stderr 仍保留 19 个 Godot ObjectDB leaked-at-exit warning；最终 Web B 的 errors=[]、console_errors=[]，没有对应脚本错误。该残留已如实记录。
- 全量 core regression 脚本完成且 script_errors=0，但汇总 fail=53；失败为 M3Energy 1、M8Mechanics 1、M8UI 24、M8R1Telegraphs 12、M10Growth 1、M10RewardAudit 7、M10Bosses-high 7。它们不属于本轮启动/生成/生命周期改动，未被伪装成通过，也未在本轮扩大范围修复。日志位于 TEMP/dontstop-core-r2-final。

## Evidence locations

- Final report: docs/iteration/evidence/b19-3/REPORT.md
- Current Windows build: build/b193-r2-closure-windows/
- Current Web build: build/b193-r2-closure-web/
- Current startup: output/b19-3/r2-final-weakref2-web-startup/
- Current native matrix: output/b19-3/r2-closure-native-matrix/ 和 output/b19-3/r2-closure-native-B/
- Current Windows targeted B: output/b19-3/r2-final-weakref2-windows-B/
- Current Web targeted B/P: output/b19-3/r2-final-weakref2-web-B-formal/、r2-final-weakref2-web-P/
- Current prior full matrices: output/b19-3/r2-closure-native-matrix/、r2-closure-windows-matrix/、r2-closure-web-H/、r2-closure-web-M/、r2-closure-web-B-valid/、r2-closure-web-p-light/
- Current targeted regression and parse: output/b19-3/r2-final-weakref2-regression/、r2-closure-parse/
- Spawn A/B: output/b19-3/r2-spawn-before/ 和 output/b19-3/r2-spawn-after-seed/
- Web GL trace: output/b19-3/r2-web-m-trace/、r2-web-p-trace/、r2-web-m-cache-trace/、r2-web-p-cache-trace/

## Acceptance boundary

ENGINEERING_PERF_ACCEPTED 保持 false，原因是最终 Web 冷启动仍有 230.7+5459 ms、5689.9+3312 ms、9035.4+1477 ms 三段 long task，且最终 Web P 的 p95=20.0 ms 未达到 18.5 ms 正式阈值（p99=25.1 ms、over33=9/1778 已通过）。Windows B 的 19 个 ObjectDB leaked-at-exit warning 也作为残留保留。HUMAN_ACCEPTED 保持 false；仍需用户在目标分辨率完成视觉、音频、Boss、菜单交互和真实游玩确认。本轮没有推送、合并、部署或发布。
