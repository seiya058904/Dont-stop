# M12 — Final UX Polish & Local Test Snapshot Cleanup

起点：`feat/towdown-experience-upgrade@8be5eb4`。第五轮真人反馈要求的 UI 与清理改动已经实现；本报告不把自动输入或截图视为真人验收。

**M12 CLOSED / HUMAN ACCEPTED WITH KNOWN LIMITATIONS**

`H1_STATUS = FIFTH_FEEDBACK_ADDRESSED`

`HUMAN_ACCEPTED = true`

## 当前状态：最终接受记录

- 接受依据是用户本次实际试玩反馈：整体完成度已达到收尾要求。
- 用户接受当前少量体验瑕疵，不要求继续迭代；本轮开发在 M12 结束，不进入 M13，不增加功能，不调整玩法或平衡。
- OS 鼠标逐项自动验收因工具初始化失败而未执行。该检查缺口不再作为本轮收尾阻断，但绝不标记为 PASS，也不把视口输入测试写成 OS 鼠标验收。
- 本报告不宣称零 Bug、所有原始验收门槛均已实测通过或所有硬件均已验证。历史测试 JSON、历史失败日志及此前 `HUMAN_ACCEPTED=false` 的历史记录原样保留。
- `PLAY_GAME.bat` 依赖本机工作区保留的 portable Godot 4.7.2 运行时；本次不是独立发行包。已有 Cephalopod MP3 音频退出诊断等已知限制继续保留，未声称已经修复。

## 清理

| 精确删除目标 | 运行副本 | BEFORE 逻辑 GiB | AFTER |
|---|---:|---:|---:|
| `archive/workspace-support/m9-runs` | 65 | 7.40 | 0 |
| `archive/workspace-support/m10-runs` | 102 | 11.62 | 0 |
| `archive/workspace-support/m11-runs` | 79 | 9.01 | 0 |
| 合计 | 246 | **28.03** | **0** |

FREED 逻辑体积：30,093,538,453 bytes（28.03 GiB）。删除期间磁盘可用空间净增 15,013,937,152 bytes（约13.98 GiB）；原 runner 对素材使用硬链接，且期间有其他测试活动，不能把逻辑体积当作精确物理释放量。

删除前检索当前脚本、launcher、Python、PowerShell、GDScript 和文档工具；发现旧 runner 的 `--baseline` 硬依赖，先改为 Git 重建再删除。核对绝对路径、全部246项 `project.godot`、reparse/link 边界；仅逐文件删除这三个明确目录。Git HEAD 的 archive tree 为空，没有制造历史源码删除提交。

保留 `_tools`、当前项目、`.git`、tests、`docs/iteration`、全部正式 benchmark/截图/JSON、`tests/fixtures/m10-mature-save.json` 及其他未授权目录。`workspace-support` 仍含开发依赖，未删除。旧副本的正式证据此前已由 runner 导出；历史正式证据保持不动。

详见 [cleanup.json](evidence/m12/cleanup.json)、[依赖检索](evidence/m12/dependency-search.txt)、[生命周期边界测试](evidence/m12/lifecycle-tests.json)。

## 生命周期

`tools/run-m9.py`、`run-m10.py`、`run-m11.py` 是持续创建完整 copy 的来源。现在通过 `snapshot_lifecycle.py` 在本工作区 `workspace-support/test-temp` 分配独立临时目录。

- 成功或失败：先导出日志、截图、JSON、profiler/崩溃终端输出与源码 SHA256，再清理完整副本。默认保留 **0** 份失败完整快照。
- Python 正常异常/退出通过 atexit 补做清理；删除器拒绝所有者目录、越界路径及链接/目录联接。不声称 atexit 能处理强制杀进程、系统崩溃或断电。
- `--baseline` 从 Git 固定锚点 `b2f8f48` / `3946250` / `928db1c` 重建；M11 的 Git 基线运行已通过52项 `M8Contracts`。
- [基线来源审计](evidence/m12/baseline-provenance.json) 显示历史执行的源码 hash 与 Git 锚点并非全部相同。因此新的 --baseline 明确代表固定 Git 里程碑基线，不承诺逐字重放已删除的历史工作副本；原历史测量和 hashes 继续保留。M9 测量夹具从现有正式 tests 注入，避免因旧提交尚无 M9Perf 而丢失入口。
- 运行标签不可覆盖已有证据。输出中的 `snapshot_retained=false` 与实际不存在检查对应；历史 JSON 的旧 snapshot 路径只是执行记录，不是运行依赖。

## 玩家属性页面

默认“我的构筑”保留8项最终属性，三列分别展示武器强化、天赋、原型奖励及持有数量。每列独立滚动；Reward 为4列正式图标 grid。图标只在显示时裁切透明边缘，底层仍引用原素材，没有新增第二套图片。

`BuildIcon.gd` 统一 icon 尺寸、边框、nearest、hover 与 tooltip。全部持有项有名称/层数/说明；天赋读取实际等级、冷却与连杀层数；条件效果不混入常驻合计。tooltip 在视口内换向并夹紧边缘，离开即关闭。

最终值仍直接来自 `EffectiveStats.inspect()`。`StatPanel` 不计算伤害、暴击、RPM 公式；合计仅按账本操作展示非零系数，并明确 `%`、`pp`、`×`。配件的“当前贡献”调用同一 `calculate()` 比较移除该配件前后差值；明确这属于边际贡献，有交互项，不能将全部边际贡献直接相加。拾取范围也补齐了天赋/Reward 来源显示，未改数值计算。

点击最终属性先显示 Category，点击 Category 才展开 Source。M11 玩家、武器、条件和等级页保留为二级信息；历史存档差额仍标为历史来源，不伪造归属。

## 束缚攻击训练

入口显示完整名称与副标题；先说明目的、约0.5秒行动限制、仍可攻击和正式战斗应躲避，再选择开始或取消。训练只调用正式 B02 巨卵与真实碰撞，不直接调用 apply_root 冒充命中。

训练中目标持续可见；命中后文字和正式 Root FX/HUD倒计时反馈，恢复显示“束缚结束”，随后进入完成页。用户点击返回营地即可结束，无需击杀 Boss。漏掉第一发会重试，且不能落入普通 Boss pattern，也不会按计时器伪装完成。

## 商店

武器卡增加正式枪图、Tier边框与原有类型/价格/持有状态。详情固定枪图、名称、Tier页头；当前→候选对比集中为两列，伤害/射速使用相对比例、弹匣使用发数、暴击使用百分点，底部CTA固定。换弹列的下降表示用时更短。

经济、Tier规则、武器平衡、备用弹匣和永久强化模型均保持。24 Guns / 24 Attachments / 24 Talents / 24 Rewards / 12 Enemies / 3 Bosses / 6 Regions / 30 Encounters 保持；没有修改尸潮主曲线、HP、全局伤害或成长参数。

## 验证与限制

最终通过 **40个游戏用例 / 2247项断言**：32个核心用例1446项，8个专项用例801项；另有4项生命周期检查。详见 [汇总](evidence/m12/summary.json)、[核心](evidence/m12/core-regression.json)、[专项](evidence/m12/ux-regression.json)。M9/M10固定Git基线各通过3项且临时副本已删除，见 [基线复跑](evidence/m12/baseline-smoke.json)。最终产品源码与通过用例的hash一致，见 [源码核对](evidence/m12/final-source-check.json)。一键复跑：`python tools/verify-m12.py`，需要可见原生窗口时加 `--visible`。

首轮 UI 存在 label 参数错误和控件在信号发出期间被释放的问题；修正后147项 M11Clarity 路径走通。新夹具曾错误读取未购买的124号枪，原生夹具曾过早向忙碌的根节点加子节点；修正后的原生窗口流程通过。所有失败日志与之后复测保留，不把失败记录删除或计为通过。旧套件已记录的 Cephalopod MP3 退出诊断仍按原白名单区分，不修改音频系统掩盖它。

补充复测：训练夹具改为等待第一发巨卵实际消失后再回到弹道，最终7项通过；原生商店夹具从真实商店列表选择候选枪，最终原生流程通过。首轮失败保留于 ux-initial-assessment.json，最终专项汇总使用修正后的定向复测。

[最终原生商店截图](evidence/m11/m12-native-final-v2/m12/native-shop-comparison.png)。已实际运行1366×768原生窗口并保存游戏 framebuffer；为保持410:230比例，内容区为1366×766。自动视口事件检查覆盖所有70项持有物的鼠标进入、来源、边界和离开；它与操作系统真实鼠标不同。

**已知限制：操作系统真实鼠标逐项验收缺口。** Computer Use 的 node_repl 两次初始化（含重置重试）均报 `failed to write kernel assets: 系统找不到指定的路径。 (os error 3)`，因此该项未执行且不标记为 PASS。用户本次实际试玩接受当前版本后，该缺口不再阻断 M12 收尾；它不改变本报告对自动检查、硬件覆盖或零 Bug 的表述边界。
