# Don't Stop v1.3.2

正式 patch：保留高刷新率运动连续性，消除已定位的 Web 首枪 Canvas 冷路径，收口此前 combat presentation、分配与精确寻路缓存工作。玩法数值、RNG 序列、敌人/弹幕上限、碰撞与存档协议保持原有约束。本版不宣称所有场景的整体 FPS 提升。

正式版本、最终 main SHA、Actions runs、Windows/Web ZIP 哈希与 Pages payload identity 以 [v1.3.2 Release](https://github.com/seiya058904/Dont-stop/releases/tag/v1.3.2) 附带的 provenance 为准。Web Release ZIP 复用 main 已测试并部署的 artifact；同一源码重新 export 的 PCK 不能自动当作同 bytes。

## 最后一个 blocker

`49f8400` 与 `709aaae` 的 Boss、Hero、Camera、武器配置和 M8/M10 夹具 Git blobs 相同。后者只改变 Web 菜单预热；native/headless 时间线中该入口调用次数为零。

旧 M10 bot 按渲染帧开火/决策，固定 RNG seed 不固定输入与 physics 的相位。满配 124 的真实伤害可以在 windup 完成前跨过 70%/35% 阈值，生产 Boss 正确取消该阶段未完成攻击。一次失败记录：B01 tick 990 windup_cleave，tick 1066 在 HP=2445.34 时进入 Phase III（max HP=7000）；2.655 秒 windup 只进行约 1.267 秒，随后阶段切换取消 cleave。测试却在战斗结束后无条件要求 cleave 已执行。历史候选还有 ultimate_activated=0 的失败，该旧记录没有逐 tick trace，不能替它虚构具体取消时刻。

单独固定模拟 render 步长为 120 Hz 的初次对照三场一致，但后续十次完整运行仍有一次 stage 30 提前死亡。它没有完全解决连续用例共享状态的问题：M8 的 stop/configure 不重置 bot clock、dash cooldown；Demo 的合法战斗 cooldown、已消耗 RNG 及 epoch 派生 hazard seed 也会沿用。最终仅修 M10 夹具：每场启动独立 headless 进程和用户数据目录，保留既有 boot seed 808，并用 `--fixed-fps 120` 固定 bot 与 60 Hz physics 的相位。没有挑选新 seed、手工重置生产状态或给产品加 FPS 上限。

自由开火、真实武器/移动、8 HP、原有 Boss/伤害/阶段/210 秒模拟预算和全部原有断言保持不变。每场增加 clock contract 与真正 perform_attack 的三个断言，full 加三个子用例完成检查（24 → 39 项）。budget/TTK 使用 physics ticks，wall_seconds 独列；初始状态和阶段/攻击/ultimate/physics tick/render frame 时间线保留。[五轮交替对照](evidence/release-v1.3.2/boss-blocker.json) 的 10 次 full、30 场 Boss 战全部通过，行为字段完全相同。stage 10 都是 27.65 秒、468 枪后通关；stage 20 都是 51.033 秒、852 枪后通关；stage 30 都是 25.2 秒、427 枪后死亡且已完成全部机制。这保留原有 clear-or-death 约束，真正的四 Boss 通关由 B5Bosses 验证。正式候选全部 active suites 的最终结果见 provenance。

先等待攻击再允许 DPS 的夹具尝试已撤回：延长战斗后，基线的 8 HP bot 也出现提前死亡，说明仅等待机制不能消除 render-clock 竞争。失败记录保留，不通过加血、放宽断言或暂停真实战斗制造通过。

## 首枪根因与修复

真实鼠标触发 `BaseGun._process → GunSprite._shoot → _shootAnim/play_shot_feedback → WeaponIdle.cycle_action → _draw → draw_action`。正宽度 `draw_line` 首次使用 Godot GLES3 Canvas **lit USE_PRIMITIVE** variant；program LINK_STATUS 查询阻塞 Chromium 主线程等待 shader/program 完成。一次同步 WebGL/CDP 记录中 `getProgramParameter(35714)` 为 105.3 ms，`GLES2Implementation::GetProgramiv` 为 105.258 ms，等待落在 `GetBucketContents → WaitForCmd → CommandBufferHelper::Finish → CommandBufferProxyImpl::WaitForGetOffset`，不是对 GPU 硬件忙时长的测量。

仅关闭该绘制的诊断单变量实验把首枪 200 ms 降到 66.6 ms，并使相应 program 消失；生产版本没有删除这项动作。剩余冷 variants 来自 TierMuzzle 的 unshaded primitive/polygon 和首次碰撞的 BulletSmoke particle-animation instancing/material。

修复在 Web loader 覆盖层仍存在时，实际绘制这些已定位 variants 并等待 `frame_post_draw`，再报告菜单 ready。预热 primitive 带真实 Canvas light；muzzle 保持至实际绘制；烟尘从真实 SceneState 读取 texture/material，用惰性 MultiMesh 触发 attributes/instancing，不实例化粒子 emitter，也不推进玩法 RNG。受 Web 条件与幂等保护，不在 Start、营地或转场同步执行。修复前后 shader source SHA-256 对应一致，最终首枪复用 loading 阶段已链接的 program。

`49f8400 → 709aaae` 的 fresh browser/storage 实测：1080p/4K、60 Hz 首枪 166.6–200 ms → 16.8 ms，第二/第三枪仍 16.8 ms；高刷新首枪约 162–164 ms → 6.5 ms。Start 的已有 4K 50–66.7 ms 样本没有接收 166 ms 首枪停顿，营地关闭 16.8 ms。正式 bytes 重测结果见 Release provenance，不将以上诊断候选的记录伪称为最终包结果。

## 运动与输入证据

保留 `49f8400` 的选择性插值。60 Hz 物理保持不变，Hero/敌人/敌弹/跟踪 Camera roots 开启插值，render-time artwork、翻面、recoil、UI 不插值。最终 screen vertices 像素对齐；中间 logical transform 不量化。传送按 align/reset_smoothing/reset_physics_interpolation/force_update_scroll 重置快照。

4K、160 fps 浏览器中，实际 Hero 头部不变帧占比从 `4c1b1bc` 约 60.64% 降至 `49f8400` 约 0.72%，camera/actor root 从约 62.43% 降至 0%。709aaae 独立复核头部约 1.08%、root 0%；正式包继续复核。

`4c1b1bc ↔ 49f8400`，两分辨率各三轮交替，每 action 36 个样本（projectile 专项各 24 个）；同时记录 browser event/DOM timestamp、Godot input timestamp、physics tick、rAF 与实际 framebuffer pixel 首次变化。下表为 **median / P95 ms**，含观察成本，不是显示器 input-to-photon 或盲测感知结论。

| 首个可见变化 | 1080p baseline → interpolation | 4K baseline → interpolation |
| --- | --- | --- |
| 键盘 → Hero | 16.0 / 33.4 → 18.9 / 35.0 | 16.45 / 32.3 → 20.45 / 33.3 |
| dash → Hero | 17.55 / 24.0 → 16.95 / 23.6 | 16.15 / 23.3 → 16.7 / 24.0 |
| 鼠标 → aim | 15.3 / 22.7 → 13.6 / 22.9 | 13.75 / 23.0 → 12.8 / 22.9 |
| 鼠标 → Camera | 35.8 / 47.4 → 14.7 / 27.5 | 36.75 / 46.6 → 12.75 / 24.3 |
| 开火 → muzzle | 8.65 / 10.6 → 9.15 / 11.2 | 9.25 / 12.4 → 9.55 / 13.0 |
| 开火 → 遮挡外 projectile | 36.7 / 44.9 → 38.5 / 43.6 | 38.05 / 46.3 → 38.85 / 46.1 |

Hero median 额外约 2.9–4.0 ms，P95 约 1.0–1.6 ms；physics tick/插值相位证据不支持固定增加完整 16.7 ms。projectile 首个可辨识像素还包含出枪口遮挡与飞行时间。错误 ROI 与高开销 readback 的早期样本独立排除，原始失败保留；不能据该表宣称零延迟或所有人都无法感知。

## 发布验收与边界

正式发布条件：同一最终产品代码的 62 个 active native 调用（DeepQuality、Boss full/B5/pressure/contracts、Camera、插值、武器、RNG、HUD、save 等）；import/export；stress duration 校验；Web loader/smoke、20 次连续 menu-return/soak、durability/recovery、aim core/fault、stages-fair；fresh 三枪、1080p/4K D/P 与高刷新连续性；最终完整 diff/diff-check；PR checks、main CI、Release 产物下载回验、Pages commit/aggregate/单文件 hash 与在线输入/save smoke。历史提交通过不能代替最终源码验证。

性能按有效物理 tick 和独立稳定窗口记录。仅复现慢轮且完整 trace/profiler/事件同步覆盖时归因；此前 1080p 随机慢样本的 trace 缓冲提前结束，后续 1 GiB trace 完整覆盖 90 秒却未复现该慢轮。因此没有据它改生产代码。4K D 的不同轮次仍有波动，不将其包装成普遍 FPS 收益。

退出时既有 ObjectDB/resource RID 诊断与失效的历史 evidence 场景，不等同于 active assertion 失败或持续运行泄漏；需保留真实日志、基线反证与生命周期检查结果。另一次 first-damage screen Glitch shader 查询约 9.6 ms、发生在首枪后约 1.98 秒，是独立冷路径；原长窗口后续因角色死亡而未真正开出的枪不计有效样本，另做三枪均存活的短窗口验收。未据这些边界扩大优化或改变画质。

维护者应先读根 `AGENTS.md` 与当前 workflows。旧迭代报告保留当时的失败、未完成状态和局部验证；本版收口状态以正式 Release provenance 和实际运行身份为准。缓存/临时副本清理不删除 canonical 证据、正式资源、fixture、release provenance、历史原件或便携启动依赖，不重写 Git 历史。
