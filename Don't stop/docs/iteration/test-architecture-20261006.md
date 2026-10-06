# 测试架构计时与覆盖核验（2026-10-06）

产品基线：`v1.3.5 / cb7eed5a13823412f39b3f8e58182d05447c8367`。本轮只修改 workflow、验证工具和文档。没有修改生产 GDScript、场景、正式资源、玩法/性能/存档逻辑。

## 实测基线

以下是 GitHub Actions API 的 job/step wall-clock，包含 job 初始化/恢复/上传；workflow 总等待还包含排队和 job 间调度。完整步骤及原生逐 scene 计时见 [before.json](evidence/ci-20261006/before.json)；case 参数、断言数及 LPT 分片见 `tools/native-cases.json`。同提交取两次运行的最大值用于分配，不按用例数平均。

| 路径 / job | run | 实测秒数 |
| --- | --- | ---: |
| Build and test exact Web artifact | 37428112731 | 97 |
| Gate aim-fault | 37428112731 | 86 |
| Gate aim-core | 37428112731 | 212 |
| Gate smoke | 37428112731 | 141 |
| Gate stages-fair | 37428112731 | 180 |
| Gate menu-return | 37428112731 | 946 |
| Gate save-audit | 37428112731 | 1318 |
| Native candidate preflight | 37428112716 | 26 |
| contracts | 37428112716 | 2513 |
| pressure | 37428112716 | 730 |
| Native candidate preflight | 37423621783 | 28 |
| pressure | 37423621783 | 746 |
| contracts | 37423621783 | 2455 |
| Build and test exact Web artifact | 37423585870 | 102 |
| Gate aim-fault | 37423585870 | 92 |
| Gate stages-fair | 37423585870 | 352 |
| Gate aim-core | 37423585870 | 211 |
| Gate smoke | 37423585870 | 259 |
| Gate menu-return | 37423585870 | 1158 |
| Gate save-audit | 37423585870 | 1526 |
| build-windows | 37423070602 | 67 |
| Build and test exact Web artifact | 37423029708 | 284 |
| Deploy and verify live Pages identity | 37423029708 | 21 |
| Build and test exact Web artifact | 37422547393 | 99 |
| Gate smoke | 37422547393 | 148 |
| Stable preflight | 37422547393 | 3 |
| Gate menu-return | 37422547393 | 169 |
| Web required gate | 37422547393 | 2 |

## save core / durable 的串行成本

| run | core（含服务启动） | durable |
| --- | ---: | ---: |
| 37428112731 | 290.7s | 1002.3s |
| 37423585870 | 338.0s | 1169.0s |

两个脚本分别创建自己的 context/profile，没有跨脚本共享状态；现在各自独立 gate，下载同一个 `web-build`。原 durable 测试仍执行全部 89 项语义检查。CI 原本设置 `E2E_SCREENSHOTS=none`，durable 以前忽略此开关；现在只关闭常规诊断截图，仍保留失败截图、完整 console、结果 JSON、故障注入、真实 IndexedDB 快照和下载原文核验。没有改变 click 的 500ms、持久化等待或故障等待：没有充分证据把这些时间删掉。

## 分片及不可压缩下限

| shard | 调用数 | 历史耗时上界 |
| --- | ---: | ---: |
| contracts-1 | 1 | 1435.6s |
| contracts-2 | 1 | 861.5s |
| contracts-3 | 56 | 241.3s |
| pressure-1 | 1 | 381.5s |
| pressure-2 | 3 | 189.6s |
| pressure-3 | 2 | 170.7s |

contracts 58 个调用及 pressure 6 个调用、参数全部保留，逐调用 PASS 最低数总计 3707。每个 case 仍是新 Godot 进程，防止 Autoload/RNG/clock 泄漏；每个 case 独立 APPDATA/XDG 用户数据，每个 shard 独立可写源码/证据。Full 没有 `--quit-after`。M6 的 `rows=30`、M8 的 `checks=60` 和 R1 的 completion marker 保留；任何非零退出、FAIL、SCRIPT ERROR、缺失 marker、断言不足均失败。单个 shard 失败立即退出，其他 shard 继续收集证据，最终 `Native required gate` 等待所有 shard 并拒绝失败/取消/跳过。

M8 的两次同提交实测为 1396/1436 秒；夹具连续经过 30 关，bot clock、RNG 和跨关状态携带。M6 为 761/862 秒。把一条 30 关连续运行拆成多条独立运行会改变验证含义，本轮不这样做。不使用 time-scale、少关数、无敌、减少压力或修改生产 Boss。并行后 native 的预计 critical path 为共享 import/setup 约 26–28 秒 + M8 约 24 分钟 + runner 调度，而不是 15 分钟。原来约 42 分钟的等待主要来自 M6 与 M8 串行。

20-cycle menu-return 仍是一个 browser/context 内连续 20 次加最后 restart，保留全部 pause、blocked-input、存档 reload 和 liveness 断言。两次历史 gate 为 946/1158 秒；Release/monthly 的循环数和 watchdog/job timeout 未减小。它会决定 full Web 的下限，不能保证 10–15 分钟。PR 仍是 1-cycle（加 restart）快速门禁，main 使用与 PR 相同的独立 smoke（含 loader/identity）和 1-cycle menu-return gates。已有 PR 约 4m39s、main 约 5m13s（含排队）已在目标范围内。

## 重复工作与缓存决策

- native import 一次分享给所有消费者；打包/上传约 3 秒、下载 2–3 秒，远小于重新 import 的 10–19 秒，继续复用并校验 `candidate-sha`。
- 采样 29 次 Godot/browser cache 恢复均命中、零 cache miss；保持按 OS/engine/browser 版本固定的键，不引入跨 commit `.godot` cache。
- Web full 的 save core/durable 不再串行；所有门禁依旧测试同一 Web artifact，main 仍只 export 一次、分享同一目录 bytes，所有 browser gates 与最终 required gate 成功才部署；不再把 smoke 留在 build runner 串行运行。
- native 不上传副本源码、`.godot`、用户 profile；只上传逐 case 日志、结果、准备计时和生成/改变的夹具证据。
- 本地 `--candidate` 校验同 commit 和运行时资源 hashes 后复用 import；消费者不复制 `.godot/editor` 折叠布局缓存（避免 Windows 长路径），保留 imported 资源/script/UID 缓存。
- Godot 的独立场景启动通常约 1 秒，合并进程会泄漏全局状态，收益不足以改变独立性。

## 本地验证层级

从 Git 根执行 `python "Don't stop/tools/verify.py" <tier>`；可通过 `--godot` 和 `--node` 指定已有固定版本工具，不安装依赖。

- `verify-fast --base origin/main`：基础 B194/P0Save/Baseline 加变更相关原生回归；未知产品 `.gd/.tscn/.tres` 改动保守选择全部短 contracts。PR 也追加这些相关回归，保留既有核心预检。
- `verify-web`：fast + 导出一次 + loader/smoke/1-cycle menu-return/identity，验证同一目录 bytes 未变。
- `verify-native`：全部 64 调用，本地默认一个 worker 调度六个 CI shard，可在实测资源允许时提高 `--jobs`；可用 `--shard contracts-3` 等精确选择。
- `verify-full`：本地完整 native 后运行完整 Web；CI 两条 workflow 在独立 runner 并行启动（monthly cron 也对齐）；Web 保留 20-cycle、save core、89-check durable、aim core/fault、stages-fair、loader/smoke/identity。
- `verify-release`：full 加独立 Windows headless export/文件 SHA-256；不创建 tag、发布、推送或部署。签发 Release 仍须按既有 provenance/下载回验/线上身份规则执行。

需要复用一次 import 时，在后续命令增加 `--candidate <上次证据目录>/candidate`。每次新建独立 evidence 目录，默认在 ignored `output/verify-时间/`；旧结果不会覆盖。`--list-fast --base <ref>` 仅打印选择，不运行引擎。

## 验证状态

6 项结构/失败传播测试、3 项 menu-soak policy、12 项 stress completion 和 JavaScript syntax/YAML parse 检查通过。本地首次 fast（复制+import+3 个场景）实测 68.781 秒。下面保留本地尝试，包括失败；正式远端 CI 结果另列，不把失败尝试转记为通过。历史失败：console launcher CreateProcess 193；首次 full 在复制 `.godot/editor` 的长文件名时触发 Windows MAX_PATH；均没有计为 acceptance 通过，原日志保留。


### 新候选本地尝试（不计为完整通过）

- Windows headless export 成功，65.598 秒，EXE/PCK 长度与 SHA-256 已记录。
- 六路 native + 两个软件浏览器在同一电脑并行：density 两个变体都在 stage 31 出现 `FAIL the round resolves 31`；new runner 返回失败并保留原文。durable 在第 13 项慢确认断言失败。其余单片继续记录，因整体已失败而停止此高负载实验，未假称完成 30 关或 3707 项。
- 独立真实 browser 对照：同一 stamped Web artifact、新 context、相同 Playwright 1.60.0；原 v1.3.5 durable 驱动 43.341 秒、优化驱动 42.688 秒，均在相同慢确认断言失败，均仅完成前 12 项。这些失败耗时不是完成耗时，不能作为加速百分比。
- density 独立重跑：相同产品源码/参数/断言，`M10Density stages=22,31` 100.730 秒、11 PASS、0 FAIL，说明该 density 失败可随负载条件变化；durable 独立对照仍失败，不能一并归因于并发。
- `pressure-2` 独立完整重跑成功：density 100.730 秒 / 11 PASS、B11 stage 39 原 `seconds=75` 调用 81.070 秒 / 6 PASS、M10Bosses full 49.114 秒 / 39 PASS；完整层含准备/证据用时 253.630 秒。最终 fast 复用 import，45.868 秒、20 PASS、0 FAIL。
- 本地默认改为 `--jobs 1`，原生完成后运行单浏览器 gates；CI 的分布式 shard 保留。没有放宽 55 秒、18 秒或任何原有断言/故障语义。

实现时的预计值为 native critical path ~42 分钟 → ~24 分钟、Web save 去掉 core+durable 的串行叠加；下节记录完成后的实测。预计值不能代替完整 gate 结果。

### 完成后的 GitHub Actions 实测

用户授权测试分支、测试架构 PR、完整 CI、合并和 Pages 部署后，候选 `d54deeaffc8c32d7bd2589f81c9916efd5be4456` 经 [PR #36](https://github.com/seiya058904/Dont-stop/pull/36) 合并为 `20ca5e95db58eed18068082fbb8581e0545d0325`。临时 `codex/test-architecture-closeout` 本地/远端分支已删除。没有发布新 Release；正式产品 tag 仍为 v1.3.5，原正式源码/资源/fixture 与封板代码逐文件一致。

`evidence/ci-20261006/after.json` 保存每个 job/step 和全部 64 个 scene 的真实 wall-clock、覆盖结果、构建身份、Windows ZIP 回验摘要。原始日志及下载回来的 gate/fixture evidence 保存在本次工作区的外部审计目录，历史本地失败材料仍保留。下面总等待使用 GitHub `created_at → updated_at`，包含调度；job 秒数使用 `started_at → completed_at`，不能混为一谈。

| 路径 | 优化前实测总等待 | 优化后实测总等待 | 结果 / run |
| --- | ---: | ---: | --- |
| PR | 4m39s | 5m53s | PASS / [37446526323](https://github.com/seiya058904/Dont-stop/actions/runs/37446526323) |
| main → verified Pages | 5m13s | 5m39s | PASS / [37449480517](https://github.com/seiya058904/Dont-stop/actions/runs/37449480517) |
| full Web | 23m43s（Release）；33m58s（manual，含调度） | 21m30s | PASS / [37446541314](https://github.com/seiya058904/Dont-stop/actions/runs/37446541314) |
| full native | 42m25s（Release）；41m40s（manual） | 25m26s | PASS / [37446546587](https://github.com/seiya058904/Dont-stop/actions/runs/37446546587) |
| Windows headless package / 下载回验 | 1m11s | 1m13s | PASS / [37447338134](https://github.com/seiya058904/Dont-stop/actions/runs/37447338134) |
| Release-equivalent（full Web/native 并行 + Windows package） | longest gate 42m25s | longest gate 25m26s | 以上同候选全部通过；未发布新 Release |

PR/main 已满足快速路径目标，但该组样本没有证明它们比历史样本更快：main 补回了 menu-return，PR 保留完整 loader/identity。完整验收的主要等待缩短来自 native 并行（约 40%），不是 PR/main 的速度宣称。Full Web 的两个历史运行受到不同 runner 调度影响，不能把 manual 的全部 12m28s 差额归功于脚本优化。

| job / shard | 优化前 job 秒数 | 优化后 job 秒数 |
| --- | ---: | ---: |
| native setup | 26–28 | 30 |
| native contracts 串行 / 三片 | 2455–2513 | 1486 / 815 / 264 |
| native pressure 串行 / 三片 | 730–746 | 428 / 210 / 185 |
| full Web build | 97–102 | 112 |
| save core + durable 串行 / 独立 gates | 1318–1526 | core 355；durable 1163（并行） |
| 20-cycle menu-return | 946–1158 | 1142 |
| smoke（含 loader/identity） | 141–259 | 250 |
| aim core / fault | 211–212 / 86–92 | 282 / 98 |
| stages-fair | 180–352 | 368 |
| Windows build | 67 | 70 |
| main build / deploy+live identity | 284 / 21 | 49 / 24（browser 在独立 gate） |

64 个 native 调用全部完成，PASS 总计 **3707**：M8 60、M6 60、短 contracts 3353、三片 pressure 166/56/12。全部正常退出，无 FAIL/SCRIPT ERROR，完成标记齐全。M8 单场景实测约 1473 秒，M6 约 792 秒，参数、30 关连续状态、真实 physics tick 和原 timeout 均保留。Native job critical path 从 contracts 2513 秒降至最慢 shard 1486 秒；完整 workflow 2545 秒 → 1526 秒。

Web durable **89/89**，真实 IndexedDB 确认、18 秒故障边界、坏档恢复、失败/重试/退出及原文下载断言均执行。Menu 是 **20 个连续 cycles + 最后 restart**，456 个 token 全部成功，脚本 wall-clock 1126.666 秒；driver 保持一个 continuous session，没有降成短循环。固定 700/500ms 的拒绝输入观察及 1 秒暂停稳定窗口维持原语义；启动/菜单返回已等游戏状态/日志，40/120ms polling 不是长时间固定 sleep。没有充分依据删除真实观察窗口。

本次 24 次 cache restore 全部命中，0 miss。Native import 19 秒，只做一次，分享 imported candidate 上传 2 秒、下载 1–4 秒，继续共享比重导入快。Web export 每条 workflow 一次；main build 49 秒，smoke/menu-return 在独立 runner 并行后部署同一 Pages artifact。所有失败 gate 仍阻止正式 gate/部署，full tests 没有 continue-on-error、fake success、帧数提前退出、time-scale 或放宽断言。

**没有达到 full Web/native/Release 15 分钟目标。** 当前真实下限是 M8 连续 30 关约 24.5 分钟；full Web 的 durable 约 19 分钟和 continuous soak 约 18.8 分钟也超过 15 分钟。不能通过拆散跨关状态、缩短真实故障观察或减少 soak 覆盖宣称达标。下次仍优先 `verify-fast`/targeted 与 fast Web；完整 Release 门禁保持完整。

Pages 已部署并由 CI 和本机第二次独立下载核验：SHA **20ca5e95db58eed18068082fbb8581e0545d0325**，payload digest **36df5e57a11d18a1d8eb91a089171e32d8c2b6b15574ede902f503b5ad494421**，wasm/pck/js 长度及各 SHA-256 全部匹配同次受测 artifact。Windows ZIP 下载回验 SHA-256 **5b5897f5cc9b02b5c652193ddc70f376eba47b92d0503b4d92b7bfdc995d8dbc**，包内 EXE/PCK 为 109197312/41575964 bytes。后续仅报告提交不重新部署游戏，不能据最新文档 SHA 推断 Pages 身份。

### 仓库清理状态

用户授权保留待清理项、继续本轮测试优化。删除操作被自动审批策略 `blocked by policy` 拒绝，没有绕过，实际删除文件/目录均为 0，释放空间为 0。待删除逐文件清单共 8,323 文件、1,517,487,597 logical bytes；先归档的 347 个独特历史证据逐文件 SHA-256 验证成功，归档 `archive/cleanup-20261006-historical-evidence.zip` 为 44,477,569 bytes。Git 原本已只有 main、一个主 worktree、无 stash，远端仅 main；3 个旧 Git 临时对象未删除。旧唯一大归档、便携工具、所有原 tracked 正式源码/资源/fixture/provenance/tags 均保留，新增测试证据同样保留。
