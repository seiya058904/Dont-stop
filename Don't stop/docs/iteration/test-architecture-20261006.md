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

6 项结构/失败传播测试、3 项 menu-soak policy、12 项 stress completion 和 JavaScript syntax/YAML parse 检查通过。本地首次 fast（复制+import+3 个场景）实测 68.781 秒。完整当前候选及远端优化后的实测尚待补入；预计值不是通过记录。历史失败：console launcher CreateProcess 193；首次 full 在复制 `.godot/editor` 的长文件名时触发 Windows MAX_PATH；均没有计为 acceptance 通过，原日志保留。


### 新候选本地尝试（不计为完整通过）

- Windows headless export 成功，65.598 秒，EXE/PCK 长度与 SHA-256 已记录。
- 六路 native + 两个软件浏览器在同一电脑并行：density 两个变体都在 stage 31 出现 `FAIL the round resolves 31`；new runner 返回失败并保留原文。durable 在第 13 项慢确认断言失败。其余单片继续记录，因整体已失败而停止此高负载实验，未假称完成 30 关或 3707 项。
- 独立真实 browser 对照：同一 stamped Web artifact、新 context、相同 Playwright 1.60.0；原 v1.3.5 durable 驱动 43.341 秒、优化驱动 42.688 秒，均在相同慢确认断言失败，均仅完成前 12 项。这些失败耗时不是完成耗时，不能作为加速百分比。
- density 独立重跑：相同产品源码/参数/断言，`M10Density stages=22,31` 100.730 秒、11 PASS、0 FAIL，说明该 density 失败可随负载条件变化；durable 独立对照仍失败，不能一并归因于并发。
- `pressure-2` 独立完整重跑成功：density 100.730 秒 / 11 PASS、B11 stage 39 原 `seconds=75` 调用 81.070 秒 / 6 PASS、M10Bosses full 49.114 秒 / 39 PASS；完整层含准备/证据用时 253.630 秒。最终 fast 复用 import，45.868 秒、20 PASS、0 FAIL。
- 本地默认改为 `--jobs 1`，原生完成后运行单浏览器 gates；CI 的分布式 shard 保留。没有放宽 55 秒、18 秒或任何原有断言/故障语义。

PR/main/full/release 优化后的 GitHub 实测尚未执行：需要发布这份 workflow 候选并运行独立 runner。预计 native critical path ~42 分钟 → ~24 分钟（M8 下限），不是已达成结果；预计 Web save critical path 从 core+durable 变为 max(core,durable)，约省 291–338 秒，20-cycle 与 durable 的实测新结果仍决定下限。main 的原 build-browser 串行步骤迁至独立 fast gates，并补回 1-cycle menu-return；预计按现有同提交 job 样本落在 5–6 分钟附近，尚未验证。

### 仓库清理状态

用户授权保留待清理项、继续本轮测试优化。删除操作被自动审批策略 `blocked by policy` 拒绝，没有绕过，实际删除文件/目录均为 0，释放空间为 0。待删除逐文件清单共 8,323 文件、1,517,487,597 logical bytes；先归档的 347 个独特历史证据逐文件 SHA-256 验证成功，归档 `archive/cleanup-20261006-historical-evidence.zip` 为 44,477,569 bytes。Git 原本已只有 main、一个主 worktree、无 stash，远端仅 main；3 个旧 Git 临时对象未删除。旧唯一大归档、便携工具、所有原 tracked 正式源码/资源/fixture/provenance/tags 均保留，新增测试证据同样保留。
