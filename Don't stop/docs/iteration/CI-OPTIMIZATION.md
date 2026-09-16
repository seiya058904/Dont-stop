# Web CI / GitHub Pages 流水线优化（本轮）

**状态不变**：`H1_STATUS = WEB_DEPLOYED_FOR_HUMAN_REVIEW`、`HUMAN_ACCEPTED = false`。
本轮**只优化 CI**，不改游戏内容，不进入 B批，不动 1–40 关难度。

---

## 0. 一句话结论

一次 main 部署从 **约 3.5 小时**降到**真机实测 10 分 43 秒**（候选分支 dispatch，同口径）：
4 个浏览器门禁改成**并行 job**、每个都改成**读游戏自己的只读状态**（不再靠截图）、
在线烟测从"重跑整套"改成**≤5 分钟的指纹 + 一次状态走查**，并且部署的字节被 digest 锁死为
"测过的那一份"。

真实数据与两次 run 见第 5 节；同口径降幅 **1 h 25 m 52 s → 10 m 43 s（−87.5%）**。

---

## 1. 真实性能审计（优化前，来自真实 CI run）

| 阶段 | 实测 | 来源 |
| --- | --- | --- |
| build（Godot 下载 + 导入 + 导出） | **45 s** | run `34954529853` / `34962338505` |
| Browser smoke（一个 job 串行跑 4 个脚本） | **1 h 44 m 30 s** | 同上 |
| deploy（Pages） | **13 s** | 同上 |
| Online smoke（对线上重跑整套） | **1 h 41 m 6 s** | 同上 |
| 合计 | **≈ 3 h 26 m**（含排队约 3.5 h） | 同上 |

### 根因（本轮实测定性 + 定量）

* Web 导出用的是 **`web_nothreads` 模板**：游戏循环占用浏览器主线程，因此每一次
  `page.screenshot()` / `page.evaluate()` 都必须等游戏让出主线程。
  实测同一个 build：**本机 32 ms / CI 约 30 s**，相差约 1000 倍。
* 旧 `web-menu-return-e2e.js` 用「像素差」测量一切（会话是否在跑 = HUD 两处裁剪变化；
  面板是否打开 = 按钮矩形变化；是否真开火 = 弹匣区域变化），5 轮下来在 CI 上≈80 分钟。
* 旧 Online smoke 只是把**整套套件对着线上再跑一遍**，所以又付一次同样的代价。

### 旧判据本身也不成立（不只是慢）

* **开火探针从没通过过任何 build**：blocked 测得比 shot 还大（`blocked 7.32` vs `shot 1.59`），
  因为比较的区域是 HUD 背后的世界滚动；而且**新档营地根本没有装备武器**
  （`Demo.load_camp()` 把 `Utils.player.gun` 置空、`PlayerData.player_weapon_list` 清空，
  只有 `depart()` 进 COMBAT 才装备），所以"开火"没有东西可以消耗。
* 结论：该判据必须从像素降级为**只读状态**观测——这与 `AI-TASK.zh-CN.md` 第 2 节的判断一致。

---

## 2. 优化后的架构

```
changes(秒级)  ─►  build(一次，产出唯一致测字节 + 指纹)
                        │
                        ├─► gate smoke      (并行)  ┐
                        ├─► gate save-audit (并行)  ├─► deploy(仅 main)
                        ├─► gate aim-e2e    (并行)  │        │
                        └─► gate menu-return(并行)  ┘        └─► online-smoke(≤5 min)
                                                                    （验指纹 + 走一次）
```

### Build once / Test once / Deploy exact artifact

* `build` job 是**唯一**产生 build 的地方，导出后立刻用
  `tools/stamp-build-identity.py` 往 `index.html` 写两个身份：
  * `dontstop-build` = 提交 SHA；
  * `dontstop-artifact` = **`sha256(index.wasm || index.pck || index.js)`**。
* digest 只由**载荷字节**决定：同一个提交重新导出、只要有任何一个字节不同，digest 就变。
  这就是"测 A 部署 B"的机器判据。
* 所有门禁 `download-artifact` 拿**同一个** `web-build`；deploy 用同一目录上传 Pages artifact；
  `online-smoke` 把线上页面里的 build/digest 与本次 run 的 `build-identity.json` 逐字节核对。

### 读只读状态，而不是截图

`autoload/Smoke.gd` 增加 `--probe` 只读通道（仅由 `index.html?probe=1` 触发）：每秒 4 次把
会话代号、**可暂停的**帧计数、暂停栈、面板数、是否在局内、武器/弹匣、鼠标模式、
角色坐标、准星与瞄准点、以及驱动需要点击的每个控件矩形，通过 `print("[probe] …")` 打到
浏览器控制台。脚本用 CDP 控制台通道读取——**没有页面往返**，所以不再等主线程。

### 等待改成"状态到即到"，不再是固定延时

* 面板就绪 = `Demo.pause_stack.size()` + **暂停栈稳定 1 秒**（`settlePaused()`）。
  实测：面板 `_enter_tree` 里先 `push_pause` 再布局，**开面板后约 60 ms 发出的 Esc 会被吞掉**
  （8001 ms 超时），而栈稳定后再发 Esc，300 ms 内关闭。
* 不再用"新 instance id"当就绪信号：Godot 会**复用 instance id**，重建后的面板可能拿到驱动
  已经见过的 id，于是等待超时——而面板其实在屏幕上、可以点。这类假失败本轮全部删除。

### 在线烟测瘦身（`tools/online-smoke.js`，新）

28 个 token，顺序：
1. 页面被服务，且带 `dontstop-build` / `dontstop-artifact`；
2. 载荷文件可达，且（给 identity 文件时）**SHA-256 逐字节相等**；
3. 真入口（`?probe=1`，无驱动、无状态注入）：菜单 → 开始 → 营地面板 → 真点击关闭 →
   按住 `d` 真的移动角色 → 真实光标被准星跟随 → Esc 暂停/恢复 →
   走 设置 → 返回主菜单 → **第二次开局**（关掉面板后要求引擎继续推进帧）。
* 刻意**不**再进 COMBAT 开火：那一步是旧 job 的主要成本（一次启动 + 首次战斗着色器编译），
  且不提供任何"身份"信息；开火与弹道已由 `web-aim-e2e.js` 在**同一份字节**上验证过。

---

## 3. 逐条对应本轮 14 项要求

| # | 要求 | 落点 |
| --- | --- | --- |
| 1 | 先做真实性能审计 | 本文第 1 节，数据来自真实 run `34954529853` / `34962338505` |
| 2 | Build Once / Test Once / Deploy Exact Artifact | `build` 唯一次构建 + `stamp-build-identity.py` 写 digest；门禁/部署/在线全部锁同一 artifact |
| 3 | 浏览器测试并行化 | `browser-gates` matrix：smoke / save-audit / aim-e2e / menu-return 四个并行 job，`deploy` needs 全部 |
| 4 | 优化 E2E 本身，不靠减轮数 | 固定延时 → 状态等待（`settlePaused()` / `waitRect()` / `waitState()`）；**仍是 5 轮 + 第 6 次再进入** |
| 5 | 开火验证不依赖 HUD 像素差 | 像素探针删除；`web-aim-e2e.js` 用武器自身弹匣 + 引擎弹丸流；menu-return 改为"输入被吞 + 角色没动"的状态判据 |
| 6 | Online smoke ≤5 min | `online-smoke.js`，`ONLINE_BUDGET_MS` 默认 5 min，job `timeout-minutes: 10` |
| 7 | 缓存环境 | `actions/cache` 缓存 Godot 二进制 + 600 MB 导出模板、`~/.npm` + `~/.cache/ms-playwright` |
| 8 | PR 自动跑 CI，main 才部署 | `pull_request: [main]` 跑门禁；`deploy` 有 `github.ref == refs/heads/main` 守卫，PR 永不部署 |
| 9 | docs-only 不触发几小时构建 | `changes` job 判定（全部改动都在 `docs/`、`Don't stop/docs/` 或 `*.md` 时 `game=false`，重活全部跳过） |
| 10 | 分层 FAST / RELEASE / SOAK | FAST = smoke + save-audit；RELEASE = aim-e2e + menu-return(5)，随每次 push/PR；SOAK = 每晚 `cron` 跑同一组但 **20 轮**，且不部署 |
| 11 | 明确时间预算 | 每个 job 都有 `timeout-minutes`（见下表），脚本另有自身 watchdog |
| 12 | 不改游戏 | 只碰测试基础设施：`autoload/Smoke.gd` 的 `--probe` 分支、`web/loader.html` 的 `?probe=1` 接线；**没有任何**玩法脚本/场景/数值改动 |
| 13 | 验证标准 | 本节 + 第 4 节：本地实测 + 与旧 run 同口径对比；token 数从 83 增到 133（不是删断言） |
| 14 | 交付汇报前后耗时 | 本文；状态保持 `WEB_DEPLOYED_FOR_HUMAN_REVIEW`、`HUMAN_ACCEPTED=false`，不进入 B批 |

### 时间预算（文件里写死）

| job | `timeout-minutes` |
| --- | --- |
| `changes` | 5 |
| `build` | 12（目标 <5 min，冷缓存留余量） |
| gate `smoke` / `save-audit` | 10 |
| gate `aim-e2e` | 12 |
| gate `menu-return` | 15 |
| `deploy` | 10 |
| `online-smoke` | 10（脚本自身预算 5 min） |

---

## 4. 实测数据（本机，真实跑出来的）

| 项目 | 结果 | 说明 |
| --- | --- | --- |
| `web-menu-return-e2e.js` 6 个循环（含 fixture 播种 + 末尾整页重载） | **WALL_CLOCK 149–153 s，`RESULT=PASS`，exit 0** | **133 / 133 token 全 true**（两次独立整轮跑，最后一次 152.9 s） |
| 单轮循环 | **21.5–23.1 s** | 旧像素版 CI 上约 15.8 min/轮（≈79 min / 5 轮） |
| `online-smoke.js` | **43 s，`RESULT=PASS`，exit 0** | **28 / 28 token 全 true** |
| 每轮 7 个阶段的耗时 | start ~0.8 s、close-panel ~0.8 s、liveness ~2.1 s、aim ~0.3–0.8 s、pause-resume ~5.8 s、blocked-input ~3.7 s、leave ~2–4 s（**优化前 leave 一度 25 s，全是等待超时**） | — |

> 修正一个此前会误导读者的量：旧脚本打印的 `TOTAL` 会把每轮子阶段和每轮合计**重复相加**，
> 所以 711 s 不是真实墙钟。现在打印的是真实 `WALL_CLOCK`。

### 其余三个门禁（本轮未重写，按截图数估算 CI 成本）

| gate | 截图引用数 | CI 预估（按 ~30 s/截图 + 启动着色器编译） |
| --- | --- | --- |
| `save-audit-web.js` | **0** | 1–2 min |
| `smoke-web.js` | 5 | 3–5 min |
| `web-aim-e2e.js` | 10 | 5–8 min |
| `web-menu-return-e2e.js` | 2（第 1 轮 + 最后 1 张） | 3–5 min |

并行后 Browser 门禁阶段 ≈ **max(各 gate) ≈ 5–8 min**（原来是 **104 min**）。

---

## 5. CI 实测（候选分支 workflow_dispatch，真实 runner）

两次真实 dispatch，分支 `feat/dont-stop-revision`，参数 `deploy=false`。两次的 `deploy` 与
`online-smoke` 都被 `github.ref == 'refs/heads/main'` 守卫**跳过**，**线上 Pages 完全未受影响**。

| run | 结论 | 说明 | 整条耗时 |
| --- | --- | --- | --- |
| [35051149300](https://github.com/seiya058904/Dont-stop/actions/runs/35051149300) | failure | 首次真机：门禁暴露一个**阈值标定 bug**（第 5.1 节） | 11 m 11 s |
| [35052512912](https://github.com/seiya058904/Dont-stop/actions/runs/35052512912) | **success** | 修复后全绿：4 门禁 PASS，deploy / online 跳过 | **10 m 43 s** |

> 耗时口径：表里的数字是**关键路径**（第一个 job 开始 → 最后一个 job 结束）。
> GitHub 页面显示的 run 时长略大（含排队与收尾）：run `35052512912` = 10 m 47 s，
> run `35051149300` = 11 m 11 s。两者都远低于 30 min 预算。

### 5.0 与优化前同口径对比（都是"候选分支 dispatch"）

| 阶段 | 优化前 run `34954529853` | 优化后 run `35052512912` |
| --- | --- | --- |
| Scope（docs-only 判定） | —（旧文件没有该 job） | 8 s |
| build | 44 s | **43 s** |
| Browser 门禁（旧：一个 job 串行跑 4 脚本） | **1 h 25 m 05 s** | — |
| └ smoke（FAST） | （含在上面） | 5 m 05 s |
| └ save-audit（FAST） | （含在上面） | 6 m 32 s |
| └ aim-e2e（RELEASE） | （含在上面） | **9 m 48 s** |
| └ menu-return（RELEASE，5 轮） | （含在上面） | 7 m 16 s |
| deploy | skipped | skipped |
| online smoke | skipped | skipped |
| **候选分支整条（关键路径）** | **1 h 25 m 52 s** | **10 m 43 s** |

**降幅 87.5%。**（main 推送的口径还要加 deploy 13 s + online smoke，按本地实测 43 s +
CI 启动开销估计 ≈ 11–12 min；**本轮没在 main 上跑过，不写成实测**。）

### 5.1 首次真机暴露并修掉的一个门禁 bug（阈值标定，不是产品问题）

run `35051149300` 里 menu-return **7 个 token 全红**，且失败信息完全一样：

```
[menu-e2e] FAIL CYCLE1_SESSION_IS_RUNNING the game's own idle frames advanced 8 in 10013ms while unpaused
```

根因：探针的帧计数是 `PROCESS_MODE_PAUSABLE`，所以"未暂停时它前进了"本身就是完整结论；
但有意义的对照是"暂停时它纹丝不动"。脚本却断言了**速率**（`+10 帧 / 10 s`），而这个阈值来自
本机（vsync 60 fps）；CI 的软件渲染把**同一个循环**跑到 **≈0.8 fps**（8 帧 / 10 s）。
**固定阈值测的是机器，不是产品。**

修法（见 commit `311df1d`）：
* 所有存活等待改成"推进了两帧"，不再断言速率（`+10/+5` → `+2`），窗口给足；
* `online-smoke.js` 的"按住移动键"改成**按住直到角色真的动了**再松手，不再固定按 900 ms
  （CI 上 900 ms 可能跨不到一帧——这正是本任务第 4 条"用状态等待替代固定等待"的同一条纪律）；
* 附带：`net::ERR_ABORTED` 归类为**导航产物**而不是网络故障——门禁最后会重载整页，
  此时仍在流式下载的 `index.wasm` 被浏览器取消；它没有 HTTP 状态码，重载后的页面另有断言
  证明活着，且是测试自己的导航造成的。原始条目仍写进证据文件，其他任何失败（含所有
  `http>=400`）照旧让 `NO_NETWORK_ERRORS` 失败。

### 5.2 预算核对（run `35052512912`，全部达标）

| 预算 | 目标 | 实测 | 结论 |
| --- | --- | --- | --- |
| build | < 5 min | **43 s** | ✅ |
| 单个普通 browser gate | < 10 min | 最大 aim-e2e **9 m 48 s** | ✅（贴线，见第 7 节） |
| menu-return 5 轮 | < 10 min（最多 15） | **7 m 16 s** | ✅ |
| 候选 pre-deploy 整条 | < 20 min（最多 30） | **10 m 43 s** | ✅ |
| deploy + online smoke | < 10 min | 未在候选分支上执行（守卫跳过） | 待 main 验证 |

### 5.3 缓存命中（run `35052512912`）

| 缓存键 | 结果 | 效果 |
| --- | --- | --- |
| `godot-4.7.2-stable-web-nothreads-v1`（Godot 二进制 + 600 MB 模板） | **命中** | "安装 Godot/模板"步骤 9 s → **0 s** |
| `pw-1.60.0-chromium-v1`（`~/.npm` + `~/.cache/ms-playwright`） | **4 个门禁全部命中** | Chromium 安装 21–32 s → 14–18 s |

run `35051149300` 是**冷缓存**：两项都 miss 并各自写出缓存键——这正是第二次能命中的原因。
（冷缓存下 4 个门禁都 miss 同一个 Playwright 键，只有第一个写成功，其余报 "already exists"；
这是正常的竞争，不影响正确性。）

### 5.4 门禁结果（run `35052512912`）

| gate | 证据 | 结果 |
| --- | --- | --- |
| smoke（FAST） | `[smoke] done pass=t` | **PASS** |
| save-audit（FAST） | `RESULT=PASS` | **PASS** |
| aim-e2e（RELEASE） | `RESULT=PASS` | **PASS** |
| menu-return（RELEASE） | **133 / 133 token 全 true，`RESULT=PASS`**，`WALL_CLOCK 392 856 ms` | **PASS** |
| deploy / online-smoke | — | **skipped（有意）** |

---

## 6. 改动文件

| 文件 | 改动 |
| --- | --- |
| `autoload/Smoke.gd` | 新增 `--probe` 只读通道（`_start_probe` / `_probe_stream` / `_probe_report` / `_probe_report_rects`）；状态行增 `ingame`，矩形行增 `id`。**只读，不改任何游戏状态** |
| `web/loader.html` | `?probe=1` → `GODOT_CONFIG.args = ['--probe']`（与 `?smoke` / `?e2e` 互斥分支） |
| `tools/web-menu-return-e2e.js` | 重写为状态驱动：删除像素差与 instance-id 就绪判定，改用 `settlePaused()` / `waitRect()` / `waitState()`；blocked-input 改为"按住真实移动键 + 角色坐标未变"；token 83 → 133 |
| `tools/online-smoke.js` | 新增：≤5 min 在线烟测（指纹 + 载荷 digest + 一次状态走查），28 token |
| `tools/stamp-build-identity.py` | 新增：写 `dontstop-build` / `dontstop-artifact` 与 `build-identity.json`（本地与 CI 共用同一实现） |
| `.github/workflows/deploy-pages.yml` | 重设计：单次构建 + 4 并行门禁 + PR 触发 + docs-only 跳过 + digest 身份 + 缓存 + 显式超时 + SOAK 排程 |

真机验证后又补了一个提交 `311df1d`（`fix(web): stop the gates measuring the renderer instead of
the product`），只改 `tools/web-menu-return-e2e.js` 与 `tools/online-smoke.js`：把存活判据从
"断言速率"改成"断言在推进"，并把 `net::ERR_ABORTED` 归类为导航产物。**没有**扩大任何 Godot
错误忽略范围（`self_list` 仍是原来的窄口径，原文照记）。

---

## 7. 未决项与风险（如实记录）

1. **`self_list` 引擎内部消息**：偶发出现
   `ERROR: Condition "p_elem->_root" is true.` + `at: add (./core/templates/self_list.h:46)`，
   是 Godot 自身内联链表在"同帧释放场景 + 添加场景"时的断言。
   * 已用 A/B 实测排除探针嫌疑：同一 build 分别以**普通加载**与 `?probe=1` 各走一次相同离开流程，
     两边的 console error 都是 **0**——它间歇，且不由只读通道产生。
   * 它伴随的换场是**独立可验证成功**的：新会话代号、返回后菜单无武器、
     游戏自己打印 `main menu is up … swapped=true ready=true`、页面继续推进帧。
   * 处理方式：**窄口径**归类为引擎噪声（只匹配该断言原文，或指向引擎自身
     `./core/templates/self_list.h:NN` 的定位行——产品代码不可能产生该路径），
     并且**仍然以 `note` 打印原文**，不会静默消失；其他任何 error 仍会让
     `NO_UNEXPECTED_ENGINE_ERRORS` 失败。
   * 建议：这是 Godot Web 导出 + 换场时序的既有特性，若要根因需改引擎侧换场顺序，
     属于"改游戏"范围，本轮不做。
2. **`aim-e2e` 是当前唯一贴近预算的 gate**：真机 **9 m 48 s**（预算 <10 min），
   两次 run 里都是最长的（run1 9 m 59 s / run2 9 m 48 s），并决定整条关键路径。
   它仍是截图型（10 张截图），所以它的耗时基本就是"截图数 × CI 单张成本"。
   它**没有**超过 10 min，按本轮约定**没有**动它；但已经贴线，遇到更慢的 runner
   有可能越线——建议把它列为下一个迁移到 `?probe=1` 状态判据的候选。
   `smoke`（5 m 05 s）与 `save-audit`（6 m 32 s）都还有余量，暂不迁移。
3. **`deploy` / `online-smoke` 尚未在 main 上实跑**：候选分支上它们被守卫跳过（有意为之），
   因此"online smoke ≤5 min"目前只有**本机实测 43 s** 支撑。要把它变成真机数字，
   需要在 main 上做一次真实部署（本轮未做：不合并、不部署 Pages）。
4. **本机 vs CI 环境差异被量化了**：本机 60 fps / CI ≈0.8 fps，差约 75×；
   这也正是第 5.1 节那个阈值 bug 的来源。**任何"本机成立"的时序假设都必须重审。**
5. **工作区卫生已处理**：`Don't stop/.git/` 那个非法残留目录（无 `HEAD`/`config`/`objects`/`refs`，
   只含我自己的 scratch）已按明确授权**精确删除**；内容先备份到
   `.git/scratch/from-nested-dotgit/`（13 个文件，与源逐一致）。工作区仓库不受影响。

---

## 8. 本轮状态

* **已推送候选分支** `feat/dont-stop-revision`（head `311df1d`），并做了两次
  `workflow_dispatch` 真机验证；**未合并 main、未部署 Pages、未改线上**。
* 远端 `main` 仍是 `b6f6fa92`（未动），线上 Pages 不受影响；状态
  `H1_STATUS = WEB_DEPLOYED_FOR_HUMAN_REVIEW`，`HUMAN_ACCEPTED = false`。
* CI 优化完成即停，**不进入 B批**。
