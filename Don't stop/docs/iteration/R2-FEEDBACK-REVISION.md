# 本轮修订：用户试玩反馈（2026-09-14）

来源：用户在本轮实际试玩后给出的反馈。基线是 `main@25192ee`（v1.0.2 之后的文档提交），
本轮分支 `feat/dont-stop-revision`。**旧的 HUMAN ACCEPTED 记录保留，但不外推给本版本。**

用户在反馈里把两端分开定了性：

- **Web：未通过。** 需要修复开始流程、鼠标与文字显示。
- **Windows：现有游玩体验基本认可。** 只补真正的启动加载动画，不重做鼠标手感、渲染、战斗画面、音色与玩法。

## 1. 命名迁移

| 项目 | 旧 | 新 |
| --- | --- | --- |
| 面向玩家的显示名 | TowDownGame | `Don't stop` |
| GitHub 技术仓库名 | `game-prototype-lab` | `Dont-stop` |
| 本地游戏工程文件夹 | `TowDownGame-Iteration` | `Don't stop` |
| Windows 制品 | `TowDownGame-Windows-x64.exe/.pck` | `Don't stop.exe` / `Don't stop.pck` |
| Web 入口 | `index.html` | 不变（导出器生成的依赖关系不改） |

`.git` 在仓库根（工作区目录），`project.godot` 在下一层，因此**只原地改名游戏工程目录**，
不改上一层的整片游戏工作区，也不复制/克隆第二份工程。

**存档命名空间故意保持不变**：`config/custom_user_dir_name="TowDownGame-Iteration"`（开发）
与 `config/custom_user_dir_name.public_release="TowDownGame"`（正式）都原样保留。改名是为了
品牌统一，不是为了整齐而让玩家丢进度。Web 导出实测 `user_dir=/userfs/TowDownGame`，与旧版
一致。

历史材料（`docs/iteration/evidence/**`、旧哈希、归档快照路径）里的旧名保持原样，因为它们
记录的是当时真实发生过的事情。

GitHub 仓库改名后，**旧 Pages 项目地址不会自动重定向**。本轮实测：

| 地址 | 实测结果 | 内容 |
| --- | --- | --- |
| `https://seiya058904.github.io/game-prototype-lab/` | **HTTP 404** | 已不可用（未自动重定向） |
| `https://seiya058904.github.io/Dont-stop/` | HTTP 200 | **仍然是旧基线**（`main@25192ee` 部署的 Web 构建，也就是用户判定未通过的那一版） |

也就是说：改名后站点在新地址上仍然可用，但它对应的**不是**本轮候选。本轮 Web 修复只存在于分支
`feat/dont-stop-revision`，没有推 `main`，也没有更新稳定 Release 或 Pages，避免在真人验收之前
把未验收版本放到稳定站点上。想试本轮 Web 候选请用 `PLAY_WEB.bat`（本地静态服务 + 打开浏览器），
Windows 候选是 `build/windows/Don't stop.exe`。

## 2. Web 开始流程

目标流程：`打开网页 → 加载反馈 → 自动显示原有主菜单 → 点原菜单“开始游戏” → 进入营地`。

修改前是两层入口：外壳（`web/loader.html`）先显示自己的“点击开始”，点完才露出引擎里的
真菜单，再点一次“开始游戏”。外壳那一次点击还提供给了浏览器一个引擎根本收不到的手势。

修好之后：

- 删掉了外壳的 `#start` 按钮，以及它派发的 `towdown-start` 死事件（之前没有任何监听者）。
- 画布从第一帧起就挂载并在外壳**后面**绘制；外壳只在游戏报告“主菜单已画出”之后才移除
  自己，所以玩家看到的是已经就绪、已经在跑的真菜单，不是“掀开盖布”。
- 就绪是游戏推上来的两段信号（主菜单已绘制 **且** 预热已完成），不是引擎 `startGame()`
  promise 的返回值。
- 下载阶段显示引擎自己报的真实百分比；场景加载显示 `ResourceLoader` 的真实进度；预热这类
  测不出百分比的工作用不定进度扫动动画，不伪造 100%。
- 错误（引擎脚本没加载、`new Engine()` 抛异常、wasm/pck 失败、5 分钟没启动完）都有明确
  文案和“重试”；重试就是整页重载，因此不可能留下半初始化、重复注册输入的状态。
- 音频解锁用的是原菜单那一次真实点击，没有伪造 DOM 事件。

重复点原菜单只初始化一局：`MainUI._on_start_pressed()` 在 `Utils.is_game_start` 时直接返回。

## 3. Web 鼠标

**产品决定：Web 不再使用 Pointer Lock。** 实测证据（同一构建、真实 Chromium）：

- 进入可操作状态后**不按 ESC**、不额外点击，直接移动鼠标即可瞄准；
- 游戏内 `mousemode=1`（HIDDEN，隐藏系统箭头、显示产品准星），全程
  `document.pointerLockElement === null`；
- 绝对坐标映射正确：把真实鼠标移到画布中心右侧 180 CSS px，引擎的瞄准视图坐标随之移动，
  与画布矩形换算出的设计坐标误差 < 12 px；
- 反向移动能精确回到原点（`dvp=(0.00, 0.00)`）；
- 左右/上下的垂直轴串扰 < 3 px；
- 准星与瞄准提供者一致（`crh ≈ aimvp`）；
- 连续转圈累计 2220°；
- 四个方向真实左键开火，弹丸速度方向与瞄准提供者夹角误差 ≤ 0.5°；
- ESC 仍然暂停（`paused=true`、指针可见）并能恢复（`paused=false`、`mousemode=1`），恢复后
  瞄准依然可用；暂停期间按住的移动和射击都被释放。

实现要点：把“允许瞄准/开火”和“浏览器锁住鼠标”解耦。`Utils.is_gameplay_mouse_mode()` 在
Web 上判断 `MOUSE_MODE_HIDDEN`，所有枪械、榴弹与准星的判断都跟着它走，而不是偷偷继续要求
CAPTURED。Windows 仍然是 `MOUSE_MODE_CONFINED_HIDDEN`，`tests/AimProvider` 实测通过。

**旧 Pointer Lock E2E 已退役**（`tools/pointer-lock-e2e.js` 删除），替换为
`tools/web-aim-e2e.js`：Phase A 走**真实入口**（不带 `?smoke/?e2e/?tour`），Phase B 才加状态
流做数值断言。CI 里不再有“拿到 Pointer Lock 才算过”的必过项，也删掉了“环境无法测相对位移”
这个 exit 3 逃生口。

## 4. Web 文字与符号

先定位，不猜字体。工具是 `tests/FontAudit.gd`：遍历真实实例化的 UI，解析每个控件**实际**用
的字体（theme override → LabelSettings → theme 链 → 项目默认），沿字体的 fallback 链逐字符
检查，同时报告泄漏未翻译的 key。

在修复前的源码上实测：**33 个界面、3233 条字符串、219 行缺字，全部是 U+2713 `✓`**，字体是
`res://fonts/fusion-pixel.otf`（“已激活/已拥有”这类标记）。修复后：**0 行**。

| 界面/控件 | 原始字符串与码点 | 期望显示 | 实际字体与 fallback | 修复 |
| --- | --- | --- | --- | --- |
| 营地·武器/强化列表条目、强化详情按钮 | `✓ 已激活` / `✓ <武器名>`（U+2713） | 一个勾形标记 | `fusion-pixel.otf`，`fallbacks=[]`；`px.ttf` 同样没有该码点 | 换成两款字体都覆盖的 `√`（U+221A） |
| `ui/theme.tres` 全局 UI 字体 | 使用 `px.ttf`（4504 个 CJK，无 `×` `–` `›` `↑` `↓` `→` `▲` `▼` `▶` `◀`） | 需要时能回退 | 该字体没有 fallback 链，Web 又没有系统字体回退，缺字即十六进制码框 | 改用 `fonts/ui-font.tres`：`px.ttf` + `fusion-pixel.otf` 回退链 |
| `HitLabel.tscn` / `ModeSelect.tscn` / `SnowWorld.tscn` | 各自的 `px.ttf` 覆盖 | 同上 | 同上 | 改为同一条回退链 |

诚实说明：目前**实测到**的 Web 缺字只有 `✓`。回退链那一项是结构性修复——`px.ttf` 确实缺
`×`、箭头等码点，但按现在的布局它们恰好都落在用 `fusion-pixel.otf` 的界面上，所以审计没
有把它们报成缺陷。这一点在提交信息里也写明了，没有把结构性修的说成“已观测到的 bug”。

没有使用日语假名/私用区图标字体（扫描确认），也没有通过禁用缺字框、删字符、把文本变空白
或把图标换成内部数字来“解决”。

## 5. Windows 启动

新增 `boot/Boot.tscn` 作为主场景：先画出与 Web 同视觉语言的一屏（同一背景色 `#0d0c17`、
应用图标、`Dont'Stop` 字标、状态行、进度条），**之后**才做真正耗时的两段工作：

1. `ResourceLoader.load_threaded_request` 线程加载 `res://game/map/Main.tscn`（连同城镇、
   地图、主题），显示引擎给的真实进度；
2. 预热（VFX/粒子/音频 voice），显示 `Warmup.progress`；测不出时显示不定进度扫动。

预热结束、淡出 0.22 秒后切到主菜单。实测时间（隔离 APPDATA、`--boot-capture` 自截图）：

| 阶段 | 冷启动 | 热启动 |
| --- | --- | --- |
| 加载界面出现 | t=1524 ms | t=1612 ms |
| 线程加载场景 | 107 ms | 119 ms |
| 预热 | 177 ms | 157 ms |
| 交出主菜单（相对加载界面） | 654 ms | 646 ms |

**诚实边界**：引擎自身起来之前什么都画不出来，那段由 `boot_splash` 覆盖（同一背景色），
本轮没有假装 Godot 场景能在引擎启动前显示。没有用固定 sleep 凑动画时长，也没有在耗时工作
结束之后再补一段假加载。

Windows 的画面效果、音色、鼠标手感、窗口习惯与战斗规则没有改动；没有把 Windows 改成 Web
Compatibility，也没有加浏览器式的“立即开始”。

## 6. 仍未解决 / 不在本轮范围

- 上一轮审计里与本轮无关的独立问题继续留在待办，不因 Windows 体验正常而关闭，也没有借
  这次机会扩成全系统重构。
- 本轮的真人验收只有用户自己试玩才算数。机器测试通过后最高只标
  `READY_FOR_HUMAN_REVIEW`；在拿到用户新的明确反馈前，不填 `WEB_HUMAN_ACCEPTED=true`，也不
  宣称新的 Windows 加载效果已获真人认可。
- 1366×768 / 1920×1080 之外的浏览器与高 DPI 未逐一实测的部分，明确记为验收缺口。
