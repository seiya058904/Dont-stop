# Don't Stop v1.3.3

本版接续 v1.3.2 的完整性能/发布收口，修复附加确认的 **DS-001**。既有 v1.3.2 tag 与资产保留，不改写已发布历史。最终 main SHA、Actions、验证结果、正式 ZIP 哈希与 Pages payload identity 以 [v1.3.3 Release](https://github.com/seiya058904/Dont-stop/releases/tag/v1.3.3) 附带的 provenance 为准。Web 正式 ZIP 复用 main 实际测试并部署的 bytes。

## DS-001：新档恢复事务

在 v1.3.2 (`55220de`) 的 fresh Chromium / fresh storage 中，用真实鼠标建立新档，并仅延迟真实 IndexedDB 成功确认的回调交付：确认 pending 时仍能关闭恢复弹窗，T01 购买被接受，金币 9999 → 9849、等级 0 → 1；释放较早确认后 `load_camp()` 重载初始新档，金币回到 9999、等级回到 0。普通 revision 防旧确认逻辑没有救下该修改，因为 `save_camp()` 在 `creating_new_save` 时直接返回，已接受修改没有新 revision。

修复让建立新档成为串行恢复事务。pending 时恢复弹窗保持暂停、禁用退出并持有键盘焦点；营地购买、退款、补给、装备/携带栏、出发和离开入口在修改前拒绝请求。事务只能由相符的真实持久化确认成功/失败结束。成功后恢复新档再开放交互；失败仍恢复 `.previous` 并保留坏档原文，允许重试与明确临时退出。正常保存、schema 6、存档目录、IndexedDB 精确快照确认与 dirty/unload 保护保持原有语义。

`R1RecoveryUI` 以真实文件和可控确认覆盖 pending 操作、禁用按钮信号绕过、过期确认、失败恢复/退出/重试、确认后购买及重载。`R1Persistence` 保持原有文件故障矩阵。`web-save-durable.js` 使用实际 canvas 控件与真实 IndexedDB 故障，延迟成功回调期间尝试退出/Escape/T01 购买，断言没有接受随后会被覆盖的修改；确认后购买须实际持久化并跨完整 reload 保留。两项 native 调用纳入完整 active CI（62 → 64）；完整 Web save gate 同时运行 durability/recovery，不以 MEMFS 写入代替持久化。

首轮完整 Web CI 在确认后购买已经实际提交、刷新后等级仍为 1 的情况下，遇到随后启动保存的既有 8 秒确认失败提示。新增回归原先只等待自动成功；修正为观察真实终态，若失败则断言 dirty/unload 保护及已恢复购买仍在，再点击实际重试入口并确认 IndexedDB 提交及唯一付款记录。保留首次失败日志，不更改产品确认超时、不绕过持久化断言，也不把这次未采集 profiler 的慢环境归因为产品性能问题。

后续云端 quota 注入样本在固定 8.5 秒睡眠结束时仍报告 pending，尚未交付失败回调；驱动改为等待实际失败终态后再执行原有 dirty、旧快照和重试断言。保留该失败现场，不能用 wall-clock 睡眠代替游戏状态确认。

另一次云端日志还抓到驱动在刷新后的启动保存 revision 1 尚未确认时已经购买 T01，导致 revision 2 与启动同步重叠；超时现场的磁盘仍保留付款和等级 1。正常购买回归的 setup 改为先完成启动保存（若真实失败，验证 dirty 并走实际重试），然后才发起下一笔购买。pending 恢复事务的对抗操作仍按原样执行，确认后购买及唯一付款记录的原有断言保留，产品保存行为不变。

强制软件渲染的附加诊断还定位到坏档刷新分支在 loader 撤下前点击 Start：菜单坐标已经由 probe 报告，但事件没有进入游戏，磁盘仍是同一坏档。该分支复用正常启动屏障，只有游戏报告 ready 且遮罩实际隐藏后才接受测试点击；未改产品 loader 或存储协议。

同一诊断在已完成 DS-001 和持久化断言后，发现搜索 T07 时驱动仍点了旧列表坐标。搜索会重建 Control；驱动现在等待真实过滤顺序、新 Control identity 和布局再点击，避免依赖固定 400 ms 睡眠。未修改营地 UI 或降低选择/购买断言。

## 保留的性能修复与验收口径

Camera / 60 Hz physics / 选择性插值与 Web shader warmup 方案沿用已验收的 v1.3.2，不扩大优化。[v1.3.2 审计](release-v1.3.2.md) 保留首枪 lit Canvas USE_PRIMITIVE 调用链、shader link 等待证据、单变量对照、输入延迟 A/B、M10 Boss 夹具时序根因及修复过程。

最终版本重新进行完整 active native、DeepQuality/Boss full/pressure/contracts、loader/smoke、20 次 menu-return/soak、save durability/recovery、aim core/fault、Camera/插值、fresh 三枪与 1080p/4K D/P、import/export、diff 与 artifact identity 验收；最终事实以带源码和 payload 身份的 provenance 为准。先前版本通过记录只作为历史证据，不冒充最终版本全绿。

性能观察保留所有有效样本，区分 process interval / rAF / CPU/GPU 工作时间与 framebuffer 首次像素变化。随机慢轮只有复现且同步 trace/profiler/事件完整覆盖时才归因，否则保留为未定环境/调度波动。没有普遍 FPS 提升、零输入延迟或盲测感知结论；没有在本机启动 Windows 游戏 UI。正式资源、fixture、canonical 证据、release provenance、Git 历史与便携启动工具保留，临时材料按逐文件验证清理。
