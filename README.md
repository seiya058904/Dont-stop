# Don't stop

[Play in Browser](https://seiya058904.github.io/Dont-stop/) · [Download Windows x64](https://github.com/seiya058904/Dont-stop/releases/latest)

正式版本：**v1.0.2**（本轮的候选构建见下方“本轮修订”，尚未发布到稳定 Release）

Don't stop 是一款俯视角 2D 生存射击游戏：移动、瞄准、射击、换弹与冲刺，完成遭遇后回到营地购买武器和永久强化。

## 本轮修订（分支 `feat/dont-stop-revision`）

来源是用户 2026-09-14 的实际试玩反馈。全部改动都在 `Don't stop/`（原 `TowDownGame-Iteration/`）内。

- **统一命名**：显示名 `Don't stop`，GitHub 技术仓库名 `Dont-stop`，本地游戏工程文件夹 `Don't stop`，Windows 制品 `Don't stop.exe` / `Don't stop.pck`。存档命名空间**故意保持不变**（正式版 `%APPDATA%\TowDownGame\`，开发版 `%APPDATA%\TowDownGame-Iteration\`），避免改名让玩家丢进度。
- **Web 只保留一次开始**：删除了网页外壳多余的“点击开始”按钮。加载资源与初始化完成后，外壳自动移除遮挡，露出游戏自己的主菜单；玩家点原菜单“开始游戏”进入营地。重复点击只会初始化一局。
- **Web 鼠标恢复普通瞄准**：不再使用 Pointer Lock，改为画布绝对坐标瞄准（隐藏系统箭头、显示产品准星）。进入可操作状态后立即可以瞄准与开火，不需要先按 ESC。ESC 仍然是暂停/恢复。
- **Web 缺字修复**：`ui/theme.tres` 原先把 `px.ttf` 直接当作全局 UI 字体，Web 构建没有系统字体回退，缺字会画成十六进制码框。现在统一走 `fonts/ui-font.tres`（`px.ttf` + `fusion-pixel.otf` 回退链），并把两款字体都覆盖不到的 `✓`(U+2713) 换成覆盖到的 `√`(U+221A)。
- **Windows 真实启动加载动画**：新增 `boot/Boot.tscn` 作为主场景，先画出与 Web 同视觉语言的加载界面，再分阶段完成场景加载与预热（`ResourceLoader.load_threaded_*` + `Warmup` 分步）。不延长假动画，不做假的百分比。
- **测试工具**：`save-audit-web.js` 不再无条件递归删除调用者传入的目录；旧 Pointer Lock E2E 按本轮产品行为退役，替换为 `tools/web-aim-e2e.js`（先走真实入口，再断言鼠标→准星→枪口→弹丸链路）。

## 正式试玩

- **浏览器**：打开上面的 GitHub Pages 链接即可游玩桌面版 Web 构建。
- **Windows x64**：从 [GitHub Releases](https://github.com/seiya058904/Dont-stop/releases/latest) 下载独立 ZIP，解压后运行其中的 `Don't stop.exe`。

> 仓库从 `game-prototype-lab` 改名为 `Dont-stop` 之后，**旧的 Pages 项目地址不会自动重定向**：请使用上面的新地址。旧地址的实际行为以本轮证据记录为准，不做“旧链接仍可用”的承诺。

## 开发环境

开发者可以双击 [`Don't stop/PLAY_GAME.bat`](Don't%20stop/PLAY_GAME.bat) 启动本地试玩；它依赖工作区内的 Godot 4.7.2 portable runtime，不是普通用户的发行入口。

这是一个基于原始 TowDownGame 项目的独立迭代改进版本。原始项目作为玩法、资源和工程结构的基线保留在本地归档中；所有本轮体验、系统和可玩性改进都在 `Don't stop/` 中完成，不直接修改原始项目。

本迭代重点围绕核心循环进行收敛：移动与射击手感、武器和强化构筑、敌人与 Boss 战斗压力、营地与商店信息呈现、成长与存档流程，以及从战斗到结算再回到营地的完整体验。

## 仓库结构

- `Don't stop/`：当前唯一公开的游戏源码、资源、测试、工具和正式文档（2026-09-14 由 `TowDownGame-Iteration/` 原地改名）。
- `README.md`、`.gitignore`、`.gitattributes`：仓库级说明与配置。
- `archive/`：本地归档、运行时、正式证据和支持资料，已由 `.gitignore` 排除，不上传云端。

原始项目副本已从公开云端目录移除；本地 `archive/` 中的原始项目、运行时和验证资料仍保留。

## 游戏玩法

Don't stop 是一款俯视角 2D 生存射击游戏。玩家在持续刷新的敌人和限时战斗中移动、瞄准、射击、换弹与冲刺，收集资源并完成遭遇，随后回到营地购买武器和永久强化，保存成长并继续推进。

核心玩法闭环如下：

`营地配置 → 选择武器与强化 → 进入区域战斗 → 生存或击败 Boss → 获得奖励 → 保存并回到营地`

当前迭代冻结的主要内容规模为：

- 24 把武器
- 24 个全局武器强化
- 24 个持久天赋
- 24 个 Reward（包含一次性物品）
- 12 类普通敌人与 3 个 Boss
- 6 个区域、30 个遭遇

普通遭遇以生存为核心，Boss 遭遇以击败 Boss 为结束条件。武器类型、强化、天赋和奖励共同形成不同构筑；商店、属性来源、训练场和存档系统用于帮助玩家理解并持续调整构筑。

## 历史与当前状态

M12 的收尾记录保持原样：`M12 CLOSED / HUMAN ACCEPTED WITH KNOWN LIMITATIONS`。那是 v1.0.1/v1.0.2 基线的真人验收结论，**不外推给本轮修订**：本轮 Web 反馈判定为未通过并已修复，Windows 现有游玩体验被认可、仅补充启动加载。

- 迭代历史与验收记录：[`Don't stop/docs/iteration/STATUS.md`](Don't%20stop/docs/iteration/STATUS.md)
- 试玩路线：[`Don't stop/README-PLAY.md`](Don't%20stop/README-PLAY.md)
- 本轮缺陷表与验收证据：[`Don't stop/docs/iteration/R2-FEEDBACK-REVISION.md`](Don't%20stop/docs/iteration/R2-FEEDBACK-REVISION.md)
