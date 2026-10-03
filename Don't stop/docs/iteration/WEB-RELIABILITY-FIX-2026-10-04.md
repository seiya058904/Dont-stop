# Web 存档与独立审计修复 · 2026-10-04

基线为 `seiya058904/Dont-stop` 的 `main@13caef0709019dff34359015270985517cc937fa`。工作在本地分支 `codex/web-durable-save-and-audit-fixes`，没有推送或部署。最初所在的 `codex/fix-nightly-menu-soak-budget@c770036` 保留，未混入本次提交。

验收标准：Web 只有提交后的 IndexedDB 快照与待保存文本完全一致才能显示成功；写入失败保留内存进度、显示原因、支持重试与下载；刷新恢复真实已提交档。压力请求必须用有效物理 tick 和逐轮记录证明时长。满奖励、Boss 与关键读数分区清楚。W6 仅准备实测冷路径，保持 RNG 和菜单启动路径。

## 根因与改动

| 项目 | 修复前证据 | 修复与当前证据 |
| --- | --- | --- |
| Web 保存 | 审计的存储故障下仍报告成功；原实现只回读 MEMFS | `CampSaveStore` 保留原子文件替换，Web 返回 pending；独立 IndexedDB 只读事务 **oncomplete** 后确认精确快照。确认前与失败后保持 dirty。事务中止、额度耗尽、存储禁用均显示原因；重试不重购；前两种重试后刷新恢复拥有权和槽位 |
| B11Stress 假通过 | 请求 90s，硬限一轮，实测约 45s 仍有 summary | 移除一轮上限，记录每轮有效 tick、未暂停战斗秒数和 epoch；原始完成证明与请求对齐，缺失、短时长、超时、空轮次均失败。旧 13caef07 导出重跑得到 45s，新驱动返回 1；当前 Web D 达到 90s / 5400 ticks / 两轮；Web P 稳态 90.009s、有效战斗 92.267s / 5536 ticks |
| 奖励 / Boss HUD | `output/playwright/boss/075.png` 显示满奖励把 Boss 面板挤进威胁区 | 22 项永久奖励完整保留在底部 280×12 的一行，Boss 面板固定顶部；渲染回归与真实流程截图检查 |
| 受伤后处理 | 世界层和地图时间/关卡读数处于同层，后处理采样污染读数 | 世界特效 layer 1，地图读数 2，战斗 HUD / 营地 / 恢复对话框 3。同时修复真实 Windows 截图暴露的地图时钟叠到营地面板上的相邻问题 |
| W6 首枪 | 审计 60fps 条件下 66.6ms；本机同条件新浏览器对比为 87.54ms | GPU trace 与程序源码观察定位首用 canvas shader 变体，包含 primitive / instancing；只在装备 W6、营地反馈绘制后准备其线、粒子渲染变体与枪口。使用惰性 MultiMesh，避免 CPUParticles 构造消耗 RNG。当前最终导出复测首枪 6.350ms，无 long task；窗口内真正消耗弹药 |
| 损坏档导出 | 原实现只复制到 Web 虚拟文件系统，没有下载 | Web 原始二进制读取 + `JavaScriptBridge.download_buffer`；真实 download 事件与落盘文件逐字节比较，包括 `FF 00` 非法 UTF-8 字节 |

`JavaScriptBridge.force_fs_sync()` 无完成返回值，因此不把调用本身视为成功。8 秒超时表示“持久化未确认”，并不声称事务绝无可能迟到提交；可以重试和导出。旧 revision 的确认不能清除新进度的 dirty。卸载前显示浏览器的未保存提示。明确放弃变化会恢复上次确认的原始字节，避免下一次进入误读 MEMFS 的未提交档。建立新档期间阻止重复接管，失败保留原文，成功确认后才加载新档。

玩法、经济、伤害、掉落和数据配置没有修改。P 测试增加生存时间只在显式 B11 诊断路径，保障请求的稳态窗口，不改变正常关卡计时。

## 当前验证与证据

证据根目录为外层仓库 `output/playwright/repair/`，原审计 `output/playwright/audit-evidence.json` 完整保留。下列 JSON、日志和截图位于本机忽略目录，未将大体积导出/trace 混入 Git。最终汇总及完整文件哈希见 `repair/final-evidence.json`。

| 验证 | 实际结果 | 本机证据（相对于证据根目录） |
| --- | --- | --- |
| Web 真实控件 + 故障注入 | 19 检查通过：abort、QuotaExceededError、SecurityError；失败可见/旧档保留/重试不重购/刷新恢复；显式放弃；失败新档接管原文完整；成功接管后刷新；两个真实下载 | `durable-save-complete/result.json`、`console.log`、下载文件与截图 |
| Windows 两个真实发布进程 | 11 检查通过：购买、退出、重启恢复、Win32 文件锁制造替换失败、旧档逐字节保留、重试、真实鼠标开火、物理 R 装填、退出无引擎错误 | `windows-flow-final/result.json`、`input-*.log`、`replacement-failed.png`、`practice.png` |
| 原生存档 / 恢复 UI | R1Persistence 51，R1RecoveryUI 9 检查；均 exit 0、无引擎错误 | 项目 `evidence/visual-upgrade-20260919/repair-save-native-final.log`、`repair-recovery-native-final.log` |
| HUD / RNG | CombatReadability headless 30；Windows 真渲染 32（含真实第 40 关 Boss 与峰值生产受伤 shader 截图）；PresentationRng 8；全局 RNG 序列一致 | 同目录 `repair-hud-native-final.log`、`repair-hud-render-final.log`、`repair-rng-native.log`；`native-hud/full-boss*.png` |
| Web 实际 Boss / 受伤 | 满构筑 22 项永久奖励，第 40 关观察到 46 次生产伤害事件；30 张连续截图中世界发生色散，HP、Boss 面板、关卡时间和弹药读数仍清楚；采集后主动结束，**没有算作完整压力请求** | `web-hud-live/result.json`、`console.log`、`hit-05.png` / `hit-10.png` |
| 完成证明回归 | 10 断言拒绝缺失、短时长、中断、不一致和零 tick | `node tools/stress-completion.test.js` |
| Web 压力请求 | 旧导出 90s 请求仅 45s 被拒绝；当前 D90、P90 exit 0，原始完成证明有效，无脚本 / 浏览器异常 | `stress-baseline-rejected/`、`stress-D90-final/`、`stress-P90-final/` |
| Windows 压力的负例 | 空战斗轮次 exit 1；另一 D90 请求因失焦暂停 114.833s，仅完成 20.117s，超时 exit 1，确实不被算作通过 | `native-stress-final/incomplete-idle.log`、`combat-D90.log` |
| Windows 压力完成 | 实际输入关闭 5 次失焦营地面板后，有效战斗累计 90s / 5400 ticks / 三轮（2700 + 2699 + 1），exit 0，无引擎错误。未把暂停时间混进战斗时长 | `native-stress-complete/result.json`、`combat-D90.log` |
| W6 冷路径 | 同条件首枪 87.54 → 最终导出 6.350ms；先前两次修复测量为 6.315ms；当前二枪 6.385、三枪 12.485、冲刺 6.340ms，均无 long task；真实开火/装填/出营，不是计数器赋值 | `before-headless/`、`first-shot-closeout/`、`after-headless/`、`before-first-shot/trace.json.gz`、`after-necessary-first-shot/trace.json.gz`、`gl-cost/result.json` |
| 启动 | 交替三个全新 Chromium 进程/版本；最终导出菜单首屏中位数 5691 → 5451ms，since_utils 2735 → 2668ms；先前一组为 5491 → 5521ms、2693 → 2699ms。购买前均没有武器预热。两组小样本未见明显启动退化，不把自然波动称为启动加速 | `startup-closeout/result.json`、`startup-final/result.json` 及启动日志 |
| 导出 | Godot 4.7.2 Web / Windows Release exit 0，无脚本解析错误 | `web-export-closeout.log`、`windows-export-closeout.log` |

存档新工具直接运行了提交内的代码。压力驱动的本机副本仅替换 Chromium executablePath 与 helper 的解析路径，算法与提交内脚本一致；`B11_BUILD_DIR` 显式绑定导出目录。P 驱动校验实际服务资源与本地哈希并将同一字节交给页面。较早 `stress-D90/` 运行未设置路径，得到了空构建 identity；该证据已被 `stress-D90-final/` 替代，不用于最终通过结论。

旧 R1Persistence fixture 仍引用已经退出使用的附件实例表，并重复购买只能拥有一次的全局升级，导致断言失败和停滞。本次把它改为当前的四个不同全局升级与有效的历史迁移输入，保留打开、写入、替换、回读故障以及不重复收费的断言。早期失败日志仍在，最终 51 项结果来自修正后的 fixture。

## 限制与未解决风险

- IndexedDB 无法写入时，本次会保留会话进度、提示离开风险并允许真实下载；浏览器强制结束进程、清理站点数据或存储驱逐仍可能丢失未提交数据。卸载提示受浏览器策略控制。
- 尚未解决同源多个游戏页并发覆盖；确认只证明该时刻的指定快照已经提交。未测 Safari、Firefox、隐私模式及低端移动 GPU。
- W6 shader 成本转移到装备后的准备窗口，实测 elapsed_ms 97.8–121ms（包含等待绘制帧）；未把它描述为总工作量消失。菜单前不预热。首枪数字来自本机 160Hz / ANGLE D3D11，不能把审计的 60fps 66.6ms 直接与 6.350ms 拼成严格同条件对比。
- 这里只证明 90s 请求，不宣称 30 / 60 分钟长跑通过。压力性能仍有尖峰：D90 全窗 max 248.38ms（含跨轮窗口），P90 稳态 p95 23.17ms、p99 45.58ms、max 94.52ms、>50ms 60 帧。不同观察时长与测量模式不能用于性能胜负判断。
- 实际输入自动化与渲染截图不等于人工手感、音频质量或各设备主观视觉验收。Windows HUD 的峰值受伤截图是生产 shader 的受控渲染回归；真实 Web Boss 受伤流程另记，不把提前停止的视觉采集计入压力完成。

## 变更范围

- 保存：`autoload/Demo.gd`、`game/config/CampSaveStore.gd`、`ui/SaveDialog.gd`、`ui/CampPanel.gd`。
- 时长证明：`game/diag/B11Stress.gd`、`tools/web-b11-1-stress.js`、`tools/web-b18-stress.js`、新增 `tools/stress-completion.js` / `.test.js`。
- HUD：`ui/GameUI.gd`、`ui/BossHUD.gd`、`ui/ControlUI.gd` / `.tscn`、`game/map/mapTown/Town.tscn`。
- 定向准备：`autoload/Warmup.gd`、`game/guns/BaseGun.gd`。
- 针对性测试与只读定位：`tests/CombatReadability.gd`、`tests/R1Persistence.gd`、`autoload/Smoke.gd`、新增 `tools/web-save-durable.js`、`tools/windows-save-flow.py`。

没有更新依赖、改远程配置、推送或部署。

最终 Web 与 Windows 的 PCK 均为 41,562,540 bytes，SHA-256 `bd8c01932372d09fe7f9d72d528ab656945d78894d1314fb9d59721f596afcb9`；Windows exe 为 109,197,312 bytes，SHA-256 `b724d988271aea216d5b8d98555f8d32a3352d22036f44c1e6ae4a8281fcaa68`。构建模板 wasm / loader 保持原审计哈希。最后只读查询远程 main 仍为 `13caef07`。
