# Don't Stop：项目与验证指南

## 1. 入口、工具链与按需 Skills
- 仓库根与 Godot 工程 `Don't stop/project.godot` 分离，命令一律在仓库根执行且路径必须加引号（含空格与单引号）。
- 工具链锁定：Godot `4.7.2-stable`、Python 3、CI Node `22`、Playwright `1.60.0`。**本地原便携 Godot exe 已去重外移**，运行 `"Don't stop/tools/verify.py"` 须传 `--godot <path>` 或设 `$GODOT`（不要跑全量验收替代局部回归）。
- **按任务加载项目 Skills**：
  - 测试、导出、原生分片与浏览器门禁：`.agents/skills/dont-stop-verify/SKILL.md`
  - 存档耐久、跨进程恢复与 Web 坏档 UX：`.agents/skills/dont-stop-save-recovery/SKILL.md`
  - 相机插值、Web 预热、性能证据与 Stage 40：`.agents/skills/dont-stop-rendering-perf/SKILL.md`
  - Release、tag、ZIP 校验与 Pages 验收：`.agents/skills/dont-stop-release/SKILL.md`

## 2. 必须保留的不变量与安全边界
- **存档与数据隔离**：保留玩法/平衡/RNG/存档兼容；开发存档目录 `TowDownGame-Iteration` 与发布 `TowDownGame` 分离；测试必须用隔离 userdata，严禁覆盖真实存档。
- **Web 持久性红线**：仅 IndexedDB 事务提交且回读快照一致才算保存成功；失败保留 dirty 并提供重试/导出，严禁将 MEMFS 写/sync 等同持久化。`creating_new_save` 为串行锁定事务，确认或回滚前拒绝所有写入。
- **隐性导出陷阱**：`SceneManager` 动态拼装 `shader_patterns` 路径，保留 `Boot.gd` 预加载与 `export_presets.cfg` include filter，严禁按“未引用”删除（无静态检查保护）。
- **清理保护边界**：删除前逐项核验路径；严禁误删正式素材与 `.import`、权威文档/证据/溯源、测试夹具、`PLAY_GAME.bat`/`PLAY_WEB.bat`、根目录 `archive/` 及存档恢复文件（`.previous`、`.recovery`、`.recovered-*`）。
- **线上身份红线**：严禁仅凭最新 Git SHA、预设版本号或 HTTP 200 推断线上 Pages/Release 身份；必须核验 `"Don't stop/tools/stamp-build-identity.py"` 与 `"Don't stop/tools/verify-pages-deployment.js"` 的 SHA 及 `index.wasm || index.pck || index.js` 组合哈希。
- **变更与授权**：不因已知残余风险自发启动大重构；完成前跑适用检查与 `git diff --check`；发布、打 tag、改远端配置或重写历史须获明确授权。
