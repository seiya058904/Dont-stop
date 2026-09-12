# AI project Workspace Root (8.30)

多仓库总工作区。本目录现在作为公开云端工作区仓库；三个游戏子目录仍各自保留独立 Git repository。

> 更新: 2026-09-12 · 确立“原型冻结、复制迭代、只读参考、分阶段真人验证”的开发策略；公开仓库只同步当前三个游戏，`archive\` 仅保留在本地。

## 目录结构

| 目录 | 定位 | 说明 |
|------|------|------|
| `archive\` | 本地归档区 | 已弃用但暂不删除的 Blutfest、Project Outpost V1/V2；保留完整仓库和工作区内容，但不上传到公开云端仓库，详见 `archive\README.md` |
| `archive\workspace-support\` | 工作区支持资料 | 运行时、官方二进制、缓存/临时目录和候选评审资料；仍保留在本工作区内，详见其下的 `README.md` |
| `TowDownGame/` | 原型基线（冻结只读） | 保留纯净的 TowDownGame 原型；后续不在此目录直接开发 |
| `Godot-GameTemplate/` | 只读参考项目 | 提取模板架构、工程组织和可复用技术思路；不作为本轮开发目标 |
| `Barren-Game/` | 只读参考项目 | 提取玩法、表现和完成度方面的优秀点；不作为本轮开发目标 |
| `TowDownGame-Iteration/` | 唯一开发副本 | 完整复制 `TowDownGame/` 后建立；所有升级和优化只进入此副本（已建立；M2 等待 H1 真人体验） |
| `archive\Blutfest\` | 已归档候选 | 暂时冷藏，不参与当前开发和候选筛选 |

已删除候选 (SOURCE REMOVED AFTER PLAYTEST): top-down-pew-pew / WarZone_2 / Hypersomnia / cdogs-sdl / quiver tiny-wizard-demo / top-down-shooter-core / Godot-Top-down-Shooter-Tutorial。评分与淘汰结论见 `archive\workspace-support\candidate-review\`。

## 公开仓库范围

公开云端仓库用于让云端 AI 直接审计和理解当前候选游戏，因此会包含根目录说明以及以下三个游戏目录的源码、资源、工程文件和试玩启动文件：

- `TowDownGame/`
- `Godot-GameTemplate/`
- `Barren-Game/`

`archive/` 整体明确排除在公开仓库之外，包含其中的归档游戏、Project Outpost V1/V2、工具、缓存、下载物和评审资料。三个游戏目录中的 `.git` 元数据不作为外层仓库内容上传；它们仍在本地保留各自独立的版本历史。

## 当前开发策略

### 主题：原型冻结、复制迭代、参考驱动、真人验证

英文概念可概括为 **Frozen Baseline / Core-Loop-First / Reference-Informed / Human-Validated Iteration**：先冻结原型基线，再在独立复制体中围绕核心体验持续收敛，用参考项目提供证据，用真人试玩决定取舍。

本工作区保留三个原始游戏仓库作为只读参考库。`TowDownGame/` 是被保留的纯净原型基线，不直接修改；现已将它完整复制为独立项目 `TowDownGame-Iteration/`，复制体才是唯一允许发生产品和代码变化的开发项目。每一次改动都应收敛到可试玩、可验证、可回滚的小阶段。

| 原则 | 在本工作区中的具体含义 |
|------|------------------------|
| 三仓库保留 | `TowDownGame/`、`Godot-GameTemplate/`、`Barren-Game/` 原始仓库全部保留，不以开发便利为由删除或替代 |
| 原型冻结 | `TowDownGame/` 只作为纯净基线和参考，不直接写入升级代码 |
| 复制迭代 | 完整复制 `TowDownGame/` 后，只有 `TowDownGame-Iteration/` 承担后续开发 |
| 参考驱动 | 从另外两个项目提取优秀点，但不直接照搬，不修改参考项目 |
| 核心循环优先 | 先打磨移动、战斗、武器、敌人、奖励和关卡推进，再扩展外围内容 |
| 垂直切片迭代 | 每个阶段都形成一段从开始到结束的可试玩体验，而不是只堆积孤立功能 |
| 真人验证 | 自动化检查只能辅助判断，是否保留或继续迭代必须经过实际试玩和用户确认 |
| 可逆与可控 | 采用 P0/P1/P2 优先级，小范围修改；重大方向先出方案，未经确认不执行 |

### 推荐工作流

1. 冻结并只读盘点三个原始游戏仓库，确认真实玩法、系统和技术约束。
2. 对三个项目进行横向比较，记录“来源、收益、适配度、成本和风险”。
3. 在用户确认后，完整复制 `TowDownGame/` 为独立开发副本，保留原型不动。
4. 为复制体制定核心循环优先的升级路线和验收标准。
5. 只在复制体中分阶段实现，每阶段都进行真实试玩、问题复现和回归验证。

归档项目只保留历史价值，不参与当前设计决策；三个原始仓库只提供基线、证据和灵感；复制体才是唯一的开发分支。

## 一键试玩

3 个当前保留游戏的原始仓库根目录都有 `PLAY_GAME.bat`，双击即可启动。`TowDownGame-Iteration/PLAY_GAME.bat` 是体验版独立启动入口；`archive\workspace-support\candidate-review\launchers\` 下的旧入口现在只是兼容包装器。

| 游戏 | 一键启动文件 | 启动方式 |
|---|---|---|
| TowDownGame 原型 | `TowDownGame\PLAY_GAME.bat` | Godot 4.7.2；冻结基线 |
| Godot Game Template | `Godot-GameTemplate\PLAY_GAME.bat` | Godot 4.7.2；只读参考 |
| Barren | `Barren-Game\PLAY_GAME.bat` | 自带 Windows 导出版本；只读参考 |
| TowDownGame 复制体 | `TowDownGame-Iteration\PLAY_GAME.bat` | 独立体验版入口 |

## 当前整理状态

- 当前保留的原始游戏仓库：`TowDownGame`、`Godot-GameTemplate`、`Barren-Game`
- 冻结原型基线：`TowDownGame`
- 唯一开发副本：`TowDownGame-Iteration`（已建立；M2 等待 H1 真人体验）
- 只读参考项目：三个原始仓库全部只读；其中 `TowDownGame` 是复制基线，另外两个用于提取优秀点
- 已弃用冷藏：`archive\Blutfest`、`archive\project-outpost-v1`、`archive\project-outpost-v2`
- 候选试玩记录和历史评审仍保留在 `archive\workspace-support\candidate-review\`

是否保留候选由用户试玩决定；历史评分见 `archive\workspace-support\candidate-review\PLAYTEST_FEEDBACK.md`。

## 工作区结构规则

> 根目录顶层只保留游戏仓库和统一的 `archive\` 容器；依赖和评审资料仍保留在本工作区的 `archive\workspace-support\` 内。

- `archive\workspace-support\_tools\` = Godot 运行时和候选官方二进制
- `archive\workspace-support\candidate-review\` = 试玩记录、评审资料、截图和兼容启动包装器
- `archive\workspace-support\_downloads\`、`_cache\`、`_tmp\` = 仍保留在工作区内的支持目录
- **禁止项目专用全局安装**: 不要默认 `winget` 全局安装 / `pip` 全局安装 / `npm -g` / 写入系统 PATH / 安装到 `C:\Program Files` / 散落到 `D:\tmp`。优先 portable ZIP、local executable、Python venv（`_tools\python-envs\<name>\`）、npm local dependency。
- **正式游戏存档**继续使用 Godot `user://` / AppData，不为了完全自包含而硬塞进 Git 工作区。

## TowDownGame 体验增强版

迭代源码由外层仓库以普通文件跟踪。启动 `TowDownGame-Iteration/PLAY_GAME.bat`；当前进度、验证及 H1 真人关口见 `TowDownGame-Iteration/docs/iteration/STATUS.md`。
