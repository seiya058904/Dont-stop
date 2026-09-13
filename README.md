# game-prototype-lab

这是一个基于原始 TowDownGame 项目的独立迭代改进版本。原始项目作为玩法、资源和工程结构的基线保留在本地归档中；所有本轮体验、系统和可玩性改进都在 `TowDownGame-Iteration/` 中完成，不直接修改原始项目。

本迭代重点围绕核心循环进行收敛：移动与射击手感、武器和强化构筑、敌人与 Boss 战斗压力、营地与商店信息呈现、成长与存档流程，以及从战斗到结算再回到营地的完整体验。

## 可玩入口

双击 [`TowDownGame-Iteration/PLAY_GAME.bat`](TowDownGame-Iteration/PLAY_GAME.bat) 启动。入口依赖本机保留的 Godot 4.7.2 portable runtime，本仓库不是独立发行包。

## 仓库结构

- `TowDownGame-Iteration/`：当前唯一公开的游戏迭代源码、资源、测试、工具和正式文档。
- `README.md`、`.gitignore`、`.gitattributes`：仓库级说明与配置。
- `archive/`：本地归档、运行时、正式证据和支持资料，已由 `.gitignore` 排除，不上传云端。

原始项目副本已从公开云端目录移除；本地 `archive/` 中的原始项目、运行时和验证资料仍保留。

## 游戏玩法

TowDownGame 是一款俯视角 2D 生存射击游戏。玩家在持续刷新的敌人和限时战斗中移动、瞄准、射击、换弹与冲刺，收集资源并完成遭遇，随后回到营地购买武器和永久强化，保存成长并继续推进。

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

## 当前状态

TowDownGame 迭代已收尾于 M12：`M12 CLOSED / HUMAN ACCEPTED WITH KNOWN LIMITATIONS`。

最终接受记录、已知限制和试玩路线见 [`TowDownGame-Iteration/docs/iteration/STATUS.md`](TowDownGame-Iteration/docs/iteration/STATUS.md) 与 [`TowDownGame-Iteration/README-PLAY.md`](TowDownGame-Iteration/README-PLAY.md)。
