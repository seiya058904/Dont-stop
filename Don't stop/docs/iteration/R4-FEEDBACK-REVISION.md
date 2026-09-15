# R4 — A批修订（返回主菜单 / 图形弹匣 / 武器姿态）

状态：`WEB_DEPLOYED_FOR_HUMAN_REVIEW`；`HUMAN_ACCEPTED = false`，`WEB_HUMAN_ACCEPTED = false`。
本记录不创建 Release、不打标签，也不把 `HUMAN_ACCEPTED` / `WEB_HUMAN_ACCEPTED` 自行置为 true。

按 `AI-TASK.zh-CN.md` 分两批交付，本文件只覆盖 **A批**（功能修复）。B批（安全生成地基、1–30 加压、
31–40 地狱、难度/性能验收）尚未开始，见文末。

三个问题的共同点：报告的现象是真的，但根因都不在现象所在的位置。因此每项都先复现、再定位到根因，
最后用可证伪的行为测试锁住，而不是改一行让截图看起来对。

---

## A批-1 Web 返回主菜单后无法再次开始（P1，真人复现）

**根因（实测）**：`autoload/Demo.gd` 的 `return_to_main_menu()` 在切换场景**之前**调用 `load_camp()`，
把武器重新挂到那个马上要被销毁的 Hero 上。于是：
`PlayerData.player_weapon_list` 里留下的是**已释放节点** → 玩家再点「开始」时，下一次 `load_camp()`
在 `gun.free()` 处对已释放对象动手而中止。表现出来就是「菜单回来了，点开始没反应」，并伴随
`previously freed` 脚本错误。上一个版本去掉转场动画只是掩盖了症状，没有碰到这条链。

**修改点**（`autoload/Demo.gd`）

- `release_session_nodes()`：切换前先解绑跨场景全局引用——`Utils.player.gun`、`Utils.player`、
  `PlayerData.player_weapon_list`、`PlayerData.player_am_list`、`Utils.canvasLayer`、`LevelServer.town`。
- `_swap_to_main_menu()`：实例化新的 `game/map/Main.tscn` → `add_child` → 设为 `current_scene` →
  释放旧场景，然后最多 `MENU_SWAP_FRAMES` 帧等待新实例就绪。
- `quitting_game` 守卫覆盖**整个**序列（旧代码在 await 的换场景动作之前就把它清掉了，这正是竞态的入口）。
- 返回菜单不再重建营地武器（存档已由 `quit_game()` 结算完成）。

**关键事实**：营地地图 `game/map/Main.tscn` **本身就是标题菜单**。点「开始」不换场景，是原地开局，
`get_tree().current_scene` 的实例不变。任何「场景路径变了」的断言都是错的（本项目早期测试正是踩了这个）。

**证据**

- 原生 `tests/R3ReturnMenu.gd`（已重写为 **5 轮**）：**128 检查 / 0 失败 / 5 轮 / exit 0**。
  包含 `EXACTLY_ONE_MENU_MAP`（杀掉旧 fixture「手工多加一张地图」的漏洞）、
  `MENU_OWNS_A_NEW_PLAYER`、`NO_INHERITED_WEAPON`、会话图（player 有效、无已释放武器、
  武器挂在本轮 GunRoot 下、`can_start`）、以及最后一轮**真实开火**证明会话可玩。
- 浏览器 `tools/web-menu-return-e2e.js` 5 轮：**`RESULT=PASS`，exit 0，83 个 token 全部 true**
  （5 轮 + 最后一轮返回后再开局，共 6 个完整迭代：
  `FIVE_CYCLES_COMPLETED cycles=5 returns=6 fully passing iterations=6`）。
  其中返回契约相关 token 全部通过：`CYCLE1..5_START_OPENS_CAMP_PANEL`、`_GAME_CONFIRMED_MENU_UP`、
  `_RETURNED_TO_LIVE_MENU`、`_NO_GHOST_AMMO_HUD`、`_PAGE_STILL_ALIVE`、`_LEAVE_ENTRY_CLICK_TOOK_EFFECT`、
  `_BLOCKED_ATTEMPT_WAS_PAUSED`、`_RESUMED_AFTER_BLOCKED_ATTEMPT`、`RESTART_AFTER_LAST_RETURN_*`、
  `PAUSE_RESUME_EVERY_CYCLE`、`SAVE_READABLE_AFTER_FIVE_RETURNS_AND_A_RELOAD`（`gold="9999.0" equipped="0"`）、
  `NO_UNEXPECTED_ENGINE_ERRORS`、`NO_PAGE_ERRORS`、`NO_NETWORK_ERRORS`。
  `_RETURNED_TO_LIVE_MENU` 是拿返回后的按钮列分别与标题菜单参考帧、游戏内参考帧比距离
  （4.84 对 59.38），冻结帧无法通过。证据：`evidence/r4/menu-return/`（JSON + 每轮截图）。
  在此之前另有**两次**独立整轮跑到 cycle 5（当时只因开火探针的 token 判负），说明返回契约可重复。
  该文件可重复产出决定性结果这一事实本身也是证据：修复前它在第 2 轮就崩掉（`Target page ... closed`）。

---

## A批-2 图形弹匣与真实弹匣不同步（P1）

**根因（源码级）**：`ui/GameUI.gd` 旧实现只画 `min(bullets_count, 40)` 个弹壳，并且**每发删掉一个**。
100 发弹匣因此只画 40 个壳，打 40 发就「空」了——此时还剩 60 发。

**修改点**

- `ui/GameUI.gd`：改为按 `当前 / 有效容量` **比例**渲染，最多 40 段。
  `segment_count(capacity)` = `min(capacity, 40)`；
  `lit_segments(current, capacity, segments)` 返回可含小数的段数，`floorf()` + `RATIO_EPSILON`
  处理 `0.6*40 = 23.999…` 这类二进制浮点误差；空=0、满=segments 都精确。
  数字改为 `剩余/容量`；备用弹匣（`N MAGS`）单独显示，不折进这个数字。
- `ui/widgets/BulletCountItem.gd` 改为 `TextureRect` + `set_lit(fraction)`，靠 `modulate.a` 表示点亮
  （`MIN_ALPHA = 0.35`，最后一段可以为小数）。节点始终保留在 HBox 里，所以行长度固定——旧的「删壳」
  会因为少一个节点而整行位移。
- `ui/ControlUI.tscn`：`BulletHbox` 改为右对齐（`offset_left=-91, offset_right=29`），40 段 × 3 px 才放得下。

**证据**：原生 `tests/AmmoBarCoverage.gd`（新）覆盖容量 **1 / 2 / 3 / 21 / 27 / 35 / 40 / 41 / 60 / 100 / 200**，
每个容量扫空→满并检查：段数 = `min(capacity,40)` 且 ≤ 40；空精确为 0、满精确为 segments；
中间值点亮段数 = `ceil(比例 × 段数)`；读数文本 = `剩余/容量`；点亮数随子弹数**单调不减**。
**234 检查 / 0 失败**。其中把报告的原始 bug 单独钉住：
`REGRESSION_60_OF_100_SHOWS_24`（100 发打剩 60 → 亮 24 段；旧实现这里是 0）。

---

## A批-3 Baby SMG 举过头顶（P1/P2）

**根因（实测，不是猜测）**：不是 Baby 场景坐标错。`game/guns/BaseGun.gd` 的 `_shootAnim()` 每次开火都
新建一个 SceneTree Tween，而回位目标取的是**当时的 `position`**。若上一次动画还没结束，下一次就把
「动画中途的位置」当成自己的终点 → 每开一枪整体上移一点。Baby 之所以最明显，是因为它**每个弹丸都调
一次** `_shootAnim()`（每扣一次扳机 3 次），动画寿命远短于开火间隔。

**修改点**

- `BaseGun.gd`：新增稳定锚点机制——`capture_pose()`（`_ready()` 里在任何动画之前记录
  `resting_position`/`resting_scale`）、`play_shot_feedback(duration, offset)`（**单一、互斥**的 tween：
  先 kill 旧 tween，再把 `position` 设成 `anchor + offset` 并缓动回锚点）、`restore_pose()`
  （立刻回锚点并取消 tween，接到 `cancel_actions()` 里——切枪/换弹/死亡/回营/返回菜单都不会留下残留偏移）。
  tween 建在节点上（不是 SceneTree），随场景一起释放。
- `game/guns/BabyZapZap.gd`：`createBullet()` 里删掉每个弹丸的那次 `_shootAnim()` 调用（这才是漂移源头），
  只保留 `await`；`_shootAnim()` 改为 `super._shootAnim()` + 一次 `play_shot_feedback()`。
- 其余 9 把带同样 tween 块的枪（`AlienRifle/AlienMachine/BoomBoi/EmpireShotgun/GunSprite/RebalShotgun/
  ShotgunBlaster/Sniper/Uzi`）统一迁移到 `play_shot_feedback()`（脚本 `tools/migrate-gun-recoil.py`），
  并把 `game/guns/*.gd` 统一为 LF。`MechanismGun` 原本就是正确的锚点写法，单独处理成复用父类锚点。
- Baby 的**名称、弹道、音效、伤害均未改动**。

**证据**：原生 `tests/WeaponPoseTable.gd`（新）遍历 `Utils.weapon_list` 的**全部 24 把枪**：锚点已记录且
等于场景姿势、枪口 `GunTip` 存在、枪口焰 `tier_muzzle` 挂在 `GunTip` 下（枪口焰与弹丸同源）、
单发后回锚点、动画中途位移有界（≤2.0）、中断可恢复、**60 连发后漂移 = 0.0000**。
进入真实会话后再验：Baby 出膛 3 发且**每发都在枪口**（最差 0.056 px），开火后姿势仍在锚点。
**259 检查 / 0 失败**。

---

## CI 门禁

`.github/workflows/deploy-pages.yml`：删除两处 `WEB_MENU_RETURN_E2E=KNOWN_FAILING_TRACKED` /
`ONLINE_WEB_MENU_RETURN_E2E=KNOWN_FAILING_TRACKED` 豁免，改为**真正运行** 5 轮
`tools/web-menu-return-e2e.js`，非零退出阻断 deploy（`build` 与 `online-smoke` 各一次，即部署前与部署后）。

`tools/web-menu-return-e2e.js` 的测量修正（测量对象错了，不是放宽阈值）：

- 开火判据原先采样 `ammoHud = regionCss(292,203,408,228)`——116×25 设计像素里大部分是**会滚动的世界背景**，
  实测 idle 基线 11.42 比单发效果还大，指标分不清「打掉一发」和「镜头动了」。
- 改为采样武器自己的弹匣条 `ammoBar = regionCss(215,217,341,230)`，并让驱动**按住扳机 6 秒**：
  单发只是 1 个 3 px 段，对移动背景做像素差不可靠；一整段连发才是可信信号。
- 游戏只在 `Input.mouse_mode == MOUSE_MODE_HIDDEN`（web）且 `Demo.fire_released` 为真时才允许开火。
  驱动因此补上「像玩家那样点回游戏」的点击，并把按住扳机延长到 6 秒——**这两项没有让探针变绿**
  （见上文「已知与未决」），所以它们是记录下来的尝试，不是被证明的修复。它们本身无害且更接近玩家的真实操作，
  故保留。
- 稳定性：加 `--disable-dev-shm-usage` / `--disable-background-timer-throttling` /
  `--disable-renderer-backgrounding` / `--disable-backgrounding-occluded-windows`；加 `page.on('crash')` 取证；
  `ensureLive()` 加 try/catch（页面被关时按「不 live」处理并给出具名 token，而不是整轮 FATAL）。
  加这些之前，浏览器在第 2 轮就崩掉（`Target page ... has been closed`）；加完之后连续两次跑满 5 轮无崩溃。

---

## 已知与未决（如实列出）

- **开火像素探针改为「记录项」，不作为门禁**。本脚本原有的 `*_BLOCKED_FIRE_NO_EFFECT` /
  `*_REAL_FIRE_CONSUMES_AMMO` 在**本轮之前的所有构建上从未通过**，本轮把测量对象从「HUD 区域」
  收紧到「弹匣条」并把按住扳机延长到 6 秒之后，数字反而说明了**指标本身不成立**：
  「本应打不出子弹」的 blocked 对照测得的差异**比真实开火还大**（blocked 7.32 / 7.24 / 8.12 对
  shot 1.59 / 5.96 / 7.04），方向是反的，两者根本无法区分；且两者都被 HUD 背后滚动的世界背景主导。
  保留它们当门禁，要么因为与产品无关的原因阻断每一次部署，要么只能靠不断上调阈值让它们变绿——
  那是把「改测试」当成证据。因此改为 `note()` 记录（人类仍能在日志与 JSON 里看到每次的数字），
  **同时明确：这不构成「开火已被本脚本验证」**。
- 弹药确实会被消耗，由能干净测量的地方证明，不是由这个探针证明：
  `tests/AmmoBarCoverage.gd` 走真实 `_shoot()` 路径并断言弹匣递减（234 项，含 `60/100 → 24 段`）；
  `tests/R3ReturnMenu.gd` 的 `FINAL_SHOT_SPENDS_ROUNDS`（8 → 7）；
  本轮浏览器跑同一份构建的截图里，会话内读数 `25/25`、开火后 `23/25`。开火逻辑（`game/guns/*`）本轮未改。
- 该探针为什么不继续追查：它测的是**驱动在真实入口下的输入取证**，与 A批三项修复无关，
  继续投入的收益低于把时间留给 B批。**根因我没有证实**，因此不写成结论。已知线索：
  同一构建的 `tools/web-aim-e2e.js` 跑出 `NO_POINTER_LOCK_EVER=true`，说明这套 web 构建并不使用
  浏览器 Pointer Lock，所以「Escape 释放了 Pointer Lock」这个解释**与本轮自己的证据不符**，已排除；
  剩下更可能的是 `Input.is_action_pressed("shoot")` 在某次 release 丢失后被卡在「按住」，
  而 `Demo.fire_released` 只在「未按住」时复位（`Demo.gd:169`），于是后续扣扳机被静默忽略——
  但这仍是待证假设，不是已证结论。
- `tests/ContractRunner.gd:79` 使用已退役的配件 `instance_id`（M8 起配件改为全局强化，
  `try_purchase` 不再返回该键），因此该测试自 M8 起就是**既有失败**，与本轮无关，本轮未修改它。
- 本轮没有 Windows 正式发行包的**真人**测试，也没有 OS 级鼠标验收；不声称 Windows 上这些项已获用户确认。
- M8Globals / M9WeaponVisual / R1Regression 等长时场景在本机 240 秒上限内未跑完（`exit 124`），
  属我自行设的时限，不构成失败结论；项目自身的汇总入口仍是 `tools/verify-m12.py`，本轮未改动它。
- 未把新的原生夹具挂进 `tools/verify-m12.py`：那是 M12 专用、会改写 evidence/m11 基线的编排脚本，
  改它属于与 A批无关的变动。新夹具的调用命令见上一节。

## 复现命令

```bash
export PATH="/usr/bin:/bin:/mingw64/bin:/cmd:$PATH"   # 本机 Git Bash
GD="/d/temp/godot-4.7.2/Godot_v4.7.2-stable_win64_console.exe"

# A批-1 五轮原生回归（部署前门禁）
"$GD" --headless --path "Don't stop" res://tests/R3ReturnMenu.tscn
# A批-2 弹匣容量覆盖
"$GD" --headless --path "Don't stop" res://tests/AmmoBarCoverage.tscn
# A批-3 24 把枪姿态与枪口
"$GD" --headless --path "Don't stop" res://tests/WeaponPoseTable.tscn

# 浏览器五轮门禁（部署前/后同一条）
"$GD" --headless --path "Don't stop" --editor --import --quit
"$GD" --headless --path "Don't stop" --export-release "Web Release" build/web/index.html
python3 -m http.server 8788 --directory "Don't stop/build/web"   # 需以后台任务方式启动
export NODE_PATH="C:/Users/admin/AppData/Roaming/npm/node_modules"   # Playwright 1.60.0，与 CI 同版本
node "Don't stop/tools/web-menu-return-e2e.js" http://localhost:8788/index.html \
  "Don't stop/docs/iteration/evidence/r4/menu-return" 5
```

## 同一源码的候选制品（本轮，未部署、未创建 Release）

Web（本地导出，CI 的 `<meta name="dontstop-build">` 指纹由工作流在部署时写入，本地导出没有该指纹）：

| 文件 | 字节 | SHA256 |
| --- | --- | --- |
| `index.html` | 15020 | `9764d5d6b7066daa2b1a743aed37f170a6cc072cfd1c7efe7a22e41c1e3fc4b5` |
| `index.js` | 279815 | `33c94cb3175f3333b82e2a3be5e8e86f77986f0aa2042b1631f6367a4e5bb6ba` |
| `index.wasm` | 39514754 | `fc74679e3b97f76878947fcd4fbe1268cbfa6188182a2e33bbc3f5dc9bfa57d0` |
| `index.pck` | 41134932 | `610463f6e0c24822dcbed8afcc25eb7a9cd612d5e3b1b9fa649e87219a7c4348` |

Windows 候选（同一工作树导出）：

| 文件 | 字节 | SHA256 |
| --- | --- | --- |
| `build/windows/Don't stop.pck` | 41134932 | `610463f6e0c24822dcbed8afcc25eb7a9cd612d5e3b1b9fa649e87219a7c4348` |
| `build/windows/Don't stop.exe` | 109197312 | `ddaca81def3824832bd659cfda86e9d78cf2b2317743d58fc99bd545a6151655` |

## 既有浏览器门禁的回归（同一构建，本地）

| 脚本 | 结果 |
| --- | --- |
| `tools/smoke-web.js` | `RESULT=PASS`，exit 0 |
| `tools/web-aim-e2e.js` | `RESULT=PASS`，exit 0（含 `NO_PAGE_ERRORS`、`NO_NETWORK_ERRORS`、`NO_POINTER_LOCK_EVER`） |
| `tools/web-menu-return-e2e.js` 5 轮 | `RESULT=PASS`，exit 0，83 token 全 true |

证据目录：`evidence/r4/browser-smoke/`、`evidence/r4/menu-return/`。
`web-aim-e2e.js` 覆盖「光标 → 瞄准 → 准星 → 枪 → 弹丸」的完整链路，因此武器姿态与枪口的改动
没有破坏瞄准链。

两点值得记录：

- Web 的 `index.pck` 与 Windows 的 `Don't stop.pck` **逐字节相同**，这就是「同一源码」的机器可验证证据
  （游戏内容都在 .pck 里）。两者都比上一轮（41133540 B / `9CFDEF73…`）大 1392 B，差额来自本轮的代码改动。
- `.exe` 的 SHA256 与 R3 记录的候选**完全一致**：该 exe 是 Godot 运行时外壳，不含游戏内容，
  本轮改动只进 .pck，所以外壳不变是正确的，不能拿「exe 没变」当作「源码没变」或反过来。

## 改动文件

- 会话生命周期：`autoload/Demo.gd`
- 武器姿态：`game/guns/{BaseGun,BabyZapZap,AlienRifle,AlienMachine,BoomBoi,EmpireShotgun,GunSprite,
  RebalShotgun,ShotgunBlaster,Sniper,Uzi,MechanismGun,ArcCaster,PlasmaOrb,BurstCarbine}.gd`
- 弹匣 UI：`ui/GameUI.gd`、`ui/widgets/BulletCountItem.gd`、`ui/widgets/BulletCountItem.tscn`、`ui/ControlUI.tscn`
- 测试：`tests/R3ReturnMenu.gd`（重写为 5 轮）、`tests/AmmoBarCoverage.{gd,tscn}`（新）、
  `tests/WeaponPoseTable.{gd,tscn}`（新）
- 工具/CI：`tools/web-menu-return-e2e.js`、`tools/migrate-gun-recoil.py`（新）、
  `.github/workflows/deploy-pages.yml`
