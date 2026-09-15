# R3 — 第六次真人试玩反馈修订（当前状态）

状态：`WEB_DEPLOYED_FOR_HUMAN_REVIEW`；`HUMAN_ACCEPTED = false`，`WEB_HUMAN_ACCEPTED = false`。
基线：`feat/dont-stop-revision` 分支，起点 `811fc66`（本地）；本轮改动合并进 `main` 后部署到
<https://seiya058904.github.io/Dont-stop/>。

用户本次实际测试的是**本地源码运行版**与**已部署的浏览器版**；Windows 正式发行包本次没有真人
测试，因此本记录不声称 Windows 上这五项问题已获用户确认。

## 1. 怪物出界 / 卡墙 / 不可达（最高优先级）

**根因（实测，不是推断）**：所有敌人都实例化同一个 `game/monster/Monster 2/Monster2.tscn`，
它的 `CollisionShape2D` 是 `CapsuleShape2D`（半径 7、高 20）且相对角色原点偏移 `(1,-9)`；而每一处
出生点校验都用一个**半径 7、圆心在角色原点**的圆去问物理世界。于是候选点可以通过校验，胶囊体
却还能有最多约 19 px 埋在墙里。上一次已修的是另一半（`Vector2.INF` 哨兵被当成坐标用）。

**修改点**

- `M5Content.radius_for(id)`：按真正会生成的场景测出包围半径（碰撞体偏移 + 形状外接），按 id 缓存；
  `default_radius()` 是普通怪物体型。数据来自场景，不会和碰撞体脱节。
- `CombatArena.spawn_near()`、`Town.spawn_point()`/`spawn_near()` 的默认半径改成这个实测值，忘记传
  半径的调用者也不会退回固定 7。
- `Town.monsterCreate()` 先决定 role 再取点；Boss 与延迟重试用 Boss 的半径；`TacticalEnemy.summon()`
  用被召唤者的半径。
- `Town.spawn_point()` 的城镇导航分支补上竞技场同款的形状查询：它的 A\* 网格只按 7 px 圆建过一次，
  对大体型敌人等于把「格点合法」误当成「身体放得下」。

没有减少敌人数量、没有降低刷怪频率、没有删除边缘刷怪、没有关闭墙碰撞、没有把敌人传送给玩家；
无效候选仍然有限重试，找不到合法点仍然明确延后并计数。

**采样证据**（`tests/R3SpawnAudit.gd`，37 轮、12 个区域/阶段、10 类生成入口、3 个固定种子、
连续战斗 → 回营 → 再出发 → 切图；用每个敌人自己的碰撞体做物理形状查询）：

| | samples | invalid_candidates | rejected | deferred | illegal_final | wall_overlap | out_of_bounds_during_play | unreachable |
|---|---|---|---|---|---|---|---|---|
| 修复前 | 135 | 54551 | 54425 | 18 | **19** | **14** | 0 | 0 |
| 修复后 | 135 | 55857 | 55731 | 18 | **0** | **0** | 0 | 0 |

覆盖入口：`town_nav, wave, rush, elite, arena, horde, boss, summon, dense, region_switch`。
回归：`M11Spawn 4/0`、`M11Navigation 25/0`、`M9Bosses 18/0`、`M10Density 9/0`。

**未关闭**：`tests/M5World.tscn` 在本轮代码上是 159 项断言 5 失败，而在未改动的 `811fc66`
工作树上同样的测试是 4 失败 —— 多出来的一项是 `boss actual weapon hit B03`（测试把枪口放到
Boss 左侧 25 px 处向 +X 射击，Boss 出生点因半径变大而改变后这一枪没打中）。其余 4 项
（`schema4 completed campaign snapshot`、`old schema defaults without invented completion 1/2/3`）
在基线上同样失败，来自 `tests/M7Fixtures.gd` 读取已不存在的 `attachments` 键，与本轮无关。
这一项是本轮引入的、尚未定位完的回归，如实列出。

## 2. 玩家属性页的天赋与武器配件取消图标

`ui/BuildIcon.gd` 新增 `text_only`；`ui/StatPanel.gd` 的 `make_owned()` 对
`kind in ["upgrade","talent"]` 置 `text_only` 且不再设置 `picture`，图标占位与左侧留白一并去掉。
名称、等级、激活状态、数值、条件、贡献明细与 Tooltip 全部保留（Tooltip 仍挂在文本条目上）。
未删除任何资源文件，商店/武器/奖励/背包/战斗 HUD 的图标不受影响。
契约测试 `tests/M12UX.gd` 双向更新（旧契约要求这两类必须有图标）：**591 项断言 0 失败**。

## 3. 启动时闪出的巨大游戏图标

`project.godot` 已移除 `boot_splash/image` 并置 `boot_splash/show_image=false`，只保留同色背景
（`bg_color` 与 shell/加载场景同色），EXE/任务栏/窗口图标与网页 favicon 全部保留。
本轮新增 `tools/capture-windows-launch-frames.ps1`：从进程启动那一刻起只抓**游戏窗口自身的客户区**
（绝不抓桌面），逐帧记录毫秒时间戳与「非背景色像素占比」，因此可以证明脚本运行之前那段没有整屏
图标；`-SplashProbe` 是反向对照（临时把启动图放回去，证明这个打分器确实能抓到大图）。

**未关闭**：该脚本在本次会话里还没有跑完一轮取数（时间预算用尽），因此“原生启动无巨大闪图”
本轮只有配置层证据与既有 `--boot-capture` 证据，**没有**新的窗口级帧序列证据。

## 4. 统一正确标题 Don't Stop

`project.godot` 的 `config/name="Don't Stop"`；主菜单大标题用的纹理 `Sprites/ui/title.png`
已用项目自带字体重新生成，本轮**直接看图核对**：撇号在 n 与 t 之间、Don't 与 Stop 之间一个空格、
Stop 的 S 大写（合成图见 `evidence/r3/work/title-full-dark.png`）。网页 `<title>` 同为 `Don't Stop`；
`PLAY_GAME.bat` 窗口标题与 Windows 制品 `application/product_name` 也改为标准显示名
（导出的**文件名**仍为 `Don't stop.exe`，按用户此前的明确要求不改）。

## 5. Web 退出卡住 → 返回主菜单（本轮只完成一部分）

**已修**（真实浏览器证据）：

- `Demo.leave_after_save()` 是唯一的三端出口；`quit_game()` 与**保存失败对话框**都走它，
  所以坏档/禁写恢复路径不再绕过平台分支直接 `get_tree().quit()`。
- `Demo.return_to_main_menu()` 改为 `await` 场景切换并打印结果。实测日志：
  `[leave] save on the way out success=true web=true` →
  `[leave] returning to the main menu web=true game_start=true` →
  `[leave] main menu is up scene=res://game/map/Main.tscn game_start=false`。
  玩家点「返回主菜单」后画面确实回到主菜单（不是停在最后一帧）。
- 保存失败对话框文案按平台区分（Web：取消返回 / 放弃本次未保存变化并返回）。
- `BaseGun._process()` 不再在场景切换后读已释放的 `player`（此前每次返回都刷 "previously freed"）。
- `tests/R3ReturnMenu.gd` 用同一入口连跑两轮「开始 → 返回」：菜单在屏、无幽灵 HUD、
  无遗留面板、下一次开始仍然有效，**23 项断言 0 失败**。
- 顺带定位并修掉一个会让整站交互失效的资源缺陷：`addons/scene_manager/shader_patterns/*.png`
  被导入成仅含桌面 VRAM（s3tc）的纹理，Web(gl_compatibility) 上加载失败；已改为无损导入，
  并把过渡图案在 `Boot.gd` 里写成真实依赖，另给 `SceneManager.finish_transition()` 兜底。

**未关闭（关键）**：浏览器里**第一次返回之后，主菜单虽然回来了，却不再接受鼠标点击**，
所以第二轮开始不了 —— `tools/web-menu-return-e2e.js` 的 `CYCLE2_START_OPENS_CAMP_PANEL`
稳定失败（区域差值 0.1～0.3，面板根本没开），而同一个序列在原生 `R3ReturnMenu` 里是通过的。
因此本轮的「连续 5 轮返回并重新开始」验收 **没有通过**，也正因为如此它没有进 CI 门禁；
线上入口照常提供给用户复测，但这一项必须继续定位，不能算完成。
另外，第一轮里的「真实开火消耗弹药」也未通过（同一会话内弹药读数不变），
`CYCLE1_SETTINGS_PANEL_OPENED` 的判据也偏弱，都需要继续修。

## 6. 加载健壮性（与本轮第 3 项直接相关）

线上冒烟上一轮失败在「READY notice 20923 ms > 20 s 固定窗口」。本轮把**定时揭盖彻底删掉**：
shell 没有任何兜底揭盖路径，卡住时保留遮罩、说明情况并给可恢复的重试；游戏随后报到仍然生效；
下载 / 引擎启动 / 场景准备 / 预热 / 菜单分别上报阶段（`Utils.notify_web_boot_stage`），
`?noready=1` 故障注入用于证明「没有通知就不揭盖」。`tools/web-aim-e2e.js` 已按新契约更新，
并保留 20923 ms 这个反例作为「不许用计时器决定结果」的理由。

## 7. 仍未验证 / 未关闭

- 第 5 项：浏览器里返回后主菜单不接受点击（见上），以及返回后再次开火的判断。
- 第 3 项：窗口级逐帧启动取证尚未取数。
- 第 1 项：`M5World` 的 `boss actual weapon hit B03`。
- 第 2 项的本地/Web 同状态对照截图：本轮未重拍（契约测试通过，但缺少并排截图）。
- Web 首次开档（无武器）需要走真实 UI 购买/装备武器的那条腿仍未覆盖。
- 暂停/失焦：无头 Chromium 不产生真实窗口失焦，已如实记为环境限制而不是通过。
- 自动化通过不等于真人接受；本记录不声称零 Bug 或所有硬件均已验证。
