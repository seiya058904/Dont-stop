# Web CI / GitHub Pages 流水线优化（本轮）

**状态不变**：`H1_STATUS = WEB_DEPLOYED_FOR_HUMAN_REVIEW`、`HUMAN_ACCEPTED = false`。
本轮**只优化 CI**，不改游戏内容，不进入 B批，不动 1–40 关难度。

---

## 0. 一句话结论

一次 main 部署从 **约 3.5 小时**降到**真机实测 10 分 43 秒**（候选分支 dispatch，同口径）：
4 个浏览器门禁改成**并行 job**、每个都改成**读游戏自己的只读状态**（不再靠截图）、
在线烟测从"重跑整套"改成**≤5 分钟的指纹 + 一次状态走查**，并且部署的字节被 digest 锁死为
"测过的那一份"。

第三轮把最后一个截图型门禁 `aim-e2e` 也迁到只读 probe 通道，同一口径再降到
**真机实测 8 分 25 秒**（`aim-e2e` 9 m 48 s → 7 m 11 s）。**但 `aim-e2e` 的 1–3 min 目标没有达成**：
瓶颈已经从"页面往返"变成"runner 上 ≈1 fps 的帧率 × 契约要求的状态迁移数"，脚本侧没有剩余空间。
如实记录见第 5.5 节。

第五轮在**不删任何覆盖面**的前提下把 `aim-e2e` 按相位拆成两个并行 job
（`aim-core` = A+B、`aim-fault` = F；契约 61 + 10，并集仍是 **65**，丢失 0、新增 0）：
aim 的串行成本从 588 s → **254–361 s**，故障注入另用 111–118 s 并行跑完，
**aim 从此不再出现在关键路径上**。整条候选的 `exec` 由 8 m 21 s 变成
**7 m 36 s / 8 m 14 s / 8 m 18 s**（三次同提交 dispatch）——关键路径转移到了
**本轮没有改动**的 `save-audit`（384–443 s）与 `menu-return`（276–429 s）。
因此 "≤8 min" 这条线**没有稳定达标**（三次里一次达标，另两次各超 14–18 s），
超出部分不来自本轮任何改动。如实记录见第 5.6 节。

真实数据与五次 run 见第 5 节；同口径降幅 **1 h 25 m 52 s → 约 8 m（−90% 以上）**。

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
                        ├─► gate aim-core   (并行)  │        │
                        ├─► gate aim-fault  (并行)  │        │
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
| 3 | 浏览器测试并行化 | `browser-gates` matrix：smoke / save-audit / **aim-core / aim-fault** / menu-return 五个并行 job，`deploy` needs 全部。aim 的两半是同一个脚本 `tools/web-aim-e2e.js` 的 `core` / `fault` 两种相位选择（第五轮，见第 5.6 节） |
| 4 | 优化 E2E 本身，不靠减轮数 | 固定延时 → 状态等待（`settlePaused()` / `waitRect()` / `waitState()`）；**仍是 5 轮 + 第 6 次再进入** |
| 5 | 开火验证不依赖 HUD 像素差 | 像素探针删除；`web-aim-e2e.js` 用武器自身弹匣 + 引擎弹丸流；menu-return 改为"输入被吞 + 角色没动"的状态判据 |
| 6 | Online smoke ≤5 min | `online-smoke.js`，`ONLINE_BUDGET_MS` 默认 5 min，job `timeout-minutes: 10` |
| 7 | 缓存环境 | `actions/cache` 缓存 Godot 二进制 + 600 MB 导出模板、`~/.npm` + `~/.cache/ms-playwright` |
| 8 | PR 自动跑 CI，main 才部署 | `pull_request: [main]` 跑门禁；`deploy` 有 `github.ref == refs/heads/main` 守卫，PR 永不部署 |
| 9 | docs-only 不触发几小时构建 | `changes` job 判定（全部改动都在 `docs/`、`Don't stop/docs/` 或 `*.md` 时 `game=false`，重活全部跳过） |
| 10 | 分层 FAST / RELEASE / SOAK | FAST = smoke + save-audit；RELEASE = aim-core + aim-fault + menu-return(5)，随每次 push/PR；SOAK = 每晚 `cron` 跑同一组但 **20 轮**，且不部署 |
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
| gate `aim-core` | 12（脚本 watchdog 10 min） |
| gate `aim-fault` | 8（脚本 watchdog 6 min） |
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

> 上表是**第一轮**的估算，当时四个门禁都还是截图型，所以按"截图数 × 单张成本"算。
> 第三轮之后 `web-aim-e2e.js` 只剩 4 张**存档**截图（不作判据），
> `web-menu-return-e2e.js` 改成纯状态判据；**真实数字一律以第 5 节的真机数据为准**，
> 第 5.6 节还有拆成 5 个 job 之后的最新一版。

---

## 5. CI 实测（候选分支 workflow_dispatch，真实 runner）

两次真实 dispatch，分支 `feat/dont-stop-revision`，参数 `deploy=false`。两次的 `deploy` 与
`online-smoke` 都被 `github.ref == 'refs/heads/main'` 守卫**跳过**，**线上 Pages 完全未受影响**。

| run | 结论 | 说明 | 整条耗时 |
| --- | --- | --- | --- |
| [35051149300](https://github.com/seiya058904/Dont-stop/actions/runs/35051149300) | failure | 首次真机：门禁暴露一个**阈值标定 bug**（第 5.1 节） | 11 m 11 s |
| [35052512912](https://github.com/seiya058904/Dont-stop/actions/runs/35052512912) | **success** | 修复后全绿：4 门禁 PASS，deploy / online 跳过 | **10 m 43 s** |
| [35056975522](https://github.com/seiya058904/Dont-stop/actions/runs/35056975522) | **success** | aim-e2e 迁到只读 probe 通道后全绿（第 5.5 节） | **8 m 25 s** |
| [35059568590](https://github.com/seiya058904/Dont-stop/actions/runs/35059568590) | **success** | Phase F 拆成并行 job（第 5.6 节）：5 门禁 PASS | **8 m 18 s** |
| [35060318021](https://github.com/seiya058904/Dont-stop/actions/runs/35060318021) | **success** | 同提交复测（第 5.6 节） | **7 m 36 s** |
| [35060328946](https://github.com/seiya058904/Dont-stop/actions/runs/35060328946) | **success** | 同提交复测（第 5.6 节）；span 含 452 s 排队 | **8 m 14 s** |

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

### 5.5 第三轮：`aim-e2e` 迁到只读 probe 通道（run `35056975522`）

**这一轮只动 `tools/web-aim-e2e.js`**（外加 `Smoke.gd` 的只读字段与 `loader.html` 的参数组合），
不碰游戏业务逻辑、Web 输入方案、枪械逻辑、`smoke-web.js`、`save-audit-web.js`、menu-return 语义、
`main`、Pages，不开始 B批。分支 `feat/dont-stop-revision`，dispatch 参数 `deploy=false`。

#### 真实数字（GitHub runner，非估算）

| 阶段 | run `35052512912`（前） | run `35056975522`（后） | 变化 |
| --- | --- | --- | --- |
| Scope | 8 s | 10 s | — |
| build | 43 s | 53 s | — |
| └ smoke（FAST） | 5 m 05 s | 4 m 51 s | — |
| └ save-audit（FAST） | 6 m 32 s | 6 m 35 s | — |
| └ **aim-e2e（RELEASE）** | **9 m 48 s** | **7 m 11 s** | **−2 m 37 s（−27%）** |
| └ menu-return（RELEASE，5 轮） | 7 m 16 s | 7 m 04 s | — |
| deploy / online smoke | skipped | **skipped** | — |
| **候选分支整条（关键路径）** | **10 m 43 s** | **8 m 25 s** | **−2 m 18 s（−21%）** |

门禁结果：4 门禁全 PASS；aim-e2e **65 required / 0 false / 65 total，`RESULT=PASS`**。

#### 目标未达成，如实记录

本轮的既定目标是 **aim-e2e ≤3 min（≤5 min 可接受）**，实测 **7 m 11 s**，**没有达标**。
原因是瓶颈已经**不是**页面往返，而是 **runner 的帧率本身**。run 里的实测：

```
note the machine under test reports fps=1 (a rate is reported, never asserted: the product is not a frame-rate test)
```

CI 上游戏跑 ≈1 fps，于是一次"状态等待"最少就是一帧 ≈1.1 s，而脚本本身**只按状态推进**：

| 阶段 | 实测 | 结构 |
| --- | --- | --- |
| A（真实入口：瞄准/十字线/360°/WASD/暂停恢复） | 147 s | 16 次真实指针移动 + 6 次按键，每次 ≥3 帧 |
| F（故障注入：loader 自己的 45 s 静默窗口） | 78 s | 45 s 是**产品的**窗口，测试不缩短（主线程被游戏占住，定时器还会晚触发） |
| B（`?smoke=1&e2e=1` 打靶链） | 169 s | 62 s 用于启动一场真实 COMBAT，其余 5 发真实开火 |
| 合计（脚本） | **≈394 s** | |

其中 `A-aim-360` 单段 53 s = 12 次指针移动 × ≈4.4 s；每次移动 ≈3 帧（1 帧事件投递 + 2 帧观察）。
**这些帧不是脚本制造的，是 24 条产品契约要求的状态迁移数 × runner 的 1 fps。**
上一轮 `aim-e2e` 里那 68 s 的标定页加载与本轮删掉的像素判据已经拿掉了；剩下的地板在 runner 上。

> 结论：**要再往 1–3 min 压，只能减少契约要求的状态迁移数（牺牲覆盖面），或者提高 runner 的帧率
> （更强 CPU / 硬件加速）**，脚本侧没有剩下的空间。本轮就此停手，未继续动其他门禁。

#### 这次实际删掉 / 保留的东西

* 删除：`meanAbsDiff` / `hudCrop` / `liveAgain` 三个像素工具、**整页标定加载**（68 s）、
  旧的 HUD 像素弹药判据、`?e2e` 文本流的 `parseState` 轮询，以及**全部 43 处 `waitForTimeout`**。
* 页面往返：`page.screenshot` 的调用点 8 处（其中一个在 4 次重试的循环里 → 实际最多约 14 次）→ **4 处**，
  且这 4 张都不作为判据；`page.evaluate` 10 处 → **5 处**（均为一次性 DOM 读，不再是轮询）。
  旧脚本用 `hudCrop()` 反复截 HUD 并写到磁盘的
  `aim-ammo-hud-before-shot.png` / `aim-ammo-hud-after-shot.png` 也一并删除。
* 保留的视觉证据（仅存档，不参与判定）：`aim-01-entry-title.png`、`aim-02-crosshair-visible.png`、
  `aim-03-fault-injection-cover.png`、`aim-04-fired-from-normal-entry.png`。
* 新增的 probe 只读字段：`aimworld`、`projv`、`projang`、`projshots`、`fr`（fire_released）、`fps`，
  以及一次性的 `[probe] proj-shot n=… vx=… vy=… speed=… aim=…` 事件行（`n` 是引擎自己的弹药序号，
  用于把事件和具体某一发配对）。全部只读：不调 `_shoot()`、不写 `bullets_count`、不设瞄准、
  不生成弹丸、不跳过 UI、不改暂停状态。

---

### 5.6 第五轮：把 Phase F 拆成并行 job（commit `101f9a6`，三次真机 dispatch）

**这一轮只动两个文件**：`tools/web-aim-e2e.js` 增加一个相位选择参数，
`.github/workflows/deploy-pages.yml` 把一行门禁拆成两行。**没有碰**：游戏业务逻辑 / Web 输入方案 /
枪械逻辑 / `smoke-web.js` / `save-audit-web.js` / `web-menu-return-e2e.js` 的语义 /
`main` / Pages / B批。

#### 为什么还剩空间可以拿

第四轮之后 `aim-e2e` 的 7 m 11 s 已经不是页面往返（截图与 `evaluate` 都拿掉了）。
真机 AI 日志里 runner 跑软件渲染的 Godot Web 只有 **约 1 fps**，于是每个契约要等的一次状态迁移
最少就是一个帧周期——**剩下的是"契约数 × 帧周期"**，脚本侧再压只能删覆盖面。
唯一还没被拿走的是**相位的串行化**：Phase F 用 78 s 去等 loader 自己的 45 s 静默窗口，
而它与 A / B **不共享一个字节的状态**（它是自己的一次 `?noready=1` 加载）。

#### 拆分方式（一个脚本、两种相位、两个 job）

| | `aim-core` | `aim-fault` |
| --- | --- | --- |
| 相位 | A + B | F |
| 内容 | 真实入口（启动握手 + 瞄准/准星/360/暂停/恢复）+ 从状态读的开火链 | 故障注入 |
| 调用 | `node tools/web-aim-e2e.js <url> <dir> core` | `node tools/web-aim-e2e.js <url> <dir> fault` |
| `timeout-minutes` | 12（脚本 watchdog 10 min） | 8（脚本 watchdog 6 min） |
| 断言 token | 61 | 10 |

`all` 仍是默认值，所以**裸跑 `node web-aim-e2e.js <url> <dir>` 的行为与拆分前完全一致**（本地就用它）。
`deploy` 的 `needs` 仍是整个 `browser-gates`，**两个 job 都必须成功**，不存在"另一个挂了也能过"。

#### 覆盖面：机器核对，不是人工比对

从两个 job 的**真实 CI 日志**里抽出 `token NAME=` 行，与拆分前 `d9ac940` 版本的 `const required` 对比：

| 量 | 值 |
| --- | --- |
| 拆分前的契约数 | **65** |
| `aim-core` 实际断言 | 61 |
| `aim-fault` 实际断言 | 10 |
| **两者并集** | **65** |
| 两者交集（共用错误门禁，各断言一次） | 6 |
| **丢失的契约** | **0** |
| **新增的契约** | **0** |

契约按相位分组（A 41 / F 4 / B 14 / 共用 6），每个 job 只要求"自己那组 + 共用组"，
所以**跳过的相位不可能悄悄拿走一条要求**。共用组被两个 job **各断言一次**：
故障注入 job 现在有自己的"无引擎/页面/网络错误、无 pointer lock、无渲染崩溃、在预算内"独立判据，
比拆分前**多一层**检查。360° 扫掠仍是 **2 圈**（没有降成 1 圈）。

#### 真机数据（5 次 dispatch，统一口径）

`exec` = 第一个 job 开始 → 最后一个 job 结束（**剔除排队**）；`span` = GitHub 记录的 created→updated。

| run | 门禁数 | exec | span | queue | 关键路径 |
| --- | --- | --- | --- | --- | --- |
| R1 `35052512912`（拆前） | 4 | **10 m 43 s** | 10 m 47 s | 3 s | `aim-e2e` 588 s |
| R2 `35056975522`（拆前） | 4 | **8 m 21 s** | 8 m 25 s | 4 s | `aim-e2e` 431 s |
| R3 `35059568590`（拆后） | 5 | **8 m 18 s** | 8 m 23 s | 4 s | `save-audit` 443 s |
| R4 `35060318021`（拆后） | 5 | **7 m 36 s** | 7 m 40 s | 3 s | `save-audit` 393 s |
| R5 `35060328946`（拆后） | 5 | **8 m 14 s** | 15 m 46 s | **452 s** | `menu-return` 429 s |

> R5 的 452 s 是**并发组排队**（R4 还在跑，`cancel-in-progress` 只对 PR 为真），
> 不是流水线成本，所以五个 run 的比较一律看 `exec`。

逐门禁秒数（aim 拆开后是两个 job，用 `核心 + 故障` 表示）：

| run | smoke | save-audit | aim | menu-return | build |
| --- | --- | --- | --- | --- | --- |
| R1 | 305 | 392 | **588**（单 job） | 436 | 43 |
| R2 | 291 | 395 | **431**（单 job） | 424 | 53 |
| R3 | 223 | **443** | 349 + **113** | 276 | 40 |
| R4 | 224 | **393** | 361 + **111** | 283 | 47 |
| R5 | 295 | **384** | 254 + **118** | **429** | 51 |

#### 结论：aim 已经让出关键路径，但 8 分钟线现在由别的门禁决定

* **拆分达到了设计目标**：aim 的串行成本 588 s → 431 s → **254–361 s**；
  故障注入只用 111–118 s 跑完并与主链**真正并行**；三次拆后运行里 aim **从未成为关键路径**。
  预测（A+B ≈316 s + 约 37 s 环境开销 ≈353 s）与实测 349 / 361 / 254 s 一致。
* **8 分钟线的归属变了**：现在决定整条的是 `save-audit`（384–443 s）或 `menu-return`（276–429 s）——
  两个**本轮没有改动**的门禁。`save-audit` 在 5 次运行里、同一份脚本下是
  392 / 395 / 443 / 393 / 384 s（**约 15% 波动**），这个波动**大于**我们距离 8 分钟线的差距。
* **达标判定（如实记录，不下"达标"结论）**：拆后三次是 **7 m 36 s / 8 m 14 s / 8 m 18 s**，
  中位数 **8 m 14 s**。按"≤8 min"这条线，**三次里只有一次达标**，另两次各超出 14–18 s；
  而超出的部分**不来自本轮改动的任何东西**。要关掉这 15 s 左右只能动
  `save-audit` / `menu-return`，而它们在本轮**明确被排除在优化范围之外**，
  所以这里把判定交回决策，而不是自行扩大范围。

#### 本轮验证（本地，真机 Web build，同机同构建）

| 模式 | 结果 | 本地墙钟 |
| --- | --- | --- |
| `fault` | **10/10 PASS** | 55 s |
| `core` | **61/61 PASS** | 57 s |
| `all`（默认，等价于拆分前） | **65/65 PASS** | 108 s |

---

## 6. 改动文件

| 文件 | 改动 |
| --- | --- |
| `autoload/Smoke.gd` | 新增 `--probe` 只读通道（`_start_probe` / `_probe_stream` / `_probe_report` / `_probe_report_rects`）；状态行增 `ingame`，矩形行增 `id`。**只读，不改任何游戏状态** |
| `web/loader.html` | `?probe=1` → `GODOT_CONFIG.args = ['--probe']`（与 `?smoke` / `?e2e` 互斥分支） |
| `tools/web-menu-return-e2e.js` | 重写为状态驱动：删除像素差与 instance-id 就绪判定，改用 `settlePaused()` / `waitRect()` / `waitState()`；blocked-input 改为"按住真实移动键 + 角色坐标未变"；token 83 → 133 |
| `tools/web-aim-e2e.js` | 第三轮重写为只读状态驱动（第 5.5 节）：删除像素工具与整页标定加载、删除 HUD 弹药像素判据、43 处固定改状态等待；新增 `probe_ord` 配对的 `[probe] proj-shot` 事件与 `aimworld`/`projv`/`projang`/`fr`/`fps` 只读字段。24 条产品契约与 65 个 token 不变。第五轮（第 5.6 节）新增相位选择参数 `[all\|core\|fault]`，并把契约按相位分组（A 41 / F 4 / B 14 / 共用 6）——**没有任何 token 被删除或弱化**，两个 job 的并集仍是全部 65 条 |
| `tools/online-smoke.js` | 新增：≤5 min 在线烟测（指纹 + 载荷 digest + 一次状态走查），28 token |
| `tools/stamp-build-identity.py` | 新增：写 `dontstop-build` / `dontstop-artifact` 与 `build-identity.json`（本地与 CI 共用同一实现） |
| `.github/workflows/deploy-pages.yml` | 重设计：单次构建 + 并行门禁 + PR 触发 + docs-only 跳过 + digest 身份 + 缓存 + 显式超时 + SOAK 排程。第五轮把门禁从 4 个扩到 5 个：`aim-e2e` 一行拆成 `aim-core`（12 min）与 `aim-fault`（8 min），两者共用 `tools/web-aim-e2e.js`，靠新增的第 4 个参数选相位 |

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
2. **关键路径已从 aim 转到 `menu-return`**（第五轮之后）：aim 拆成两半后，
   `aim-core` 的脚本耗时降到 A+B ≈316 s，`aim-fault` 只有 F ≈78 s，
   两者都不再是候选里最长的那条；现在最长的是 `menu-return`（真机约 **7 m 04 s**）。
   它的成本**不是**截图或页面往返，而是**游戏自身的帧率地板**：
   它要真走 6 次"菜单 → 进入 → 暂停 → 离开 → 再进入"，每次都必须等到
   引擎真的推进若干帧，而 runner 上 ≈1 fps，所以每轮的墙钟下限由产品决定，不由脚本决定。
   按本轮约定（见第 5.6 节）：候选关键路径若 ≤8 min 就**停止继续优化**，
   不再动 `menu-return` / `smoke` / `save-audit`。
   `aim-core` 与 `smoke` / `save-audit` 都还有明显余量。
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

* **已推送候选分支** `feat/dont-stop-revision`，并做了五次 `workflow_dispatch` 真机验证
  （第三轮 1 次、第五轮 3 次同提交复测）；**未合并 main、未部署 Pages、未改线上**。
  本轮被测提交 = `101f9a6`（"代码提交"，只含 `tools/web-aim-e2e.js` 与 workflow 两行门禁拆分的改动）。
  本文档的更新是**后续的 docs-only 提交**，不改变被测代码。
* 远端 `main` 仍是 `b6f6fa92`（未动），线上 Pages 不受影响；状态
  `H1_STATUS = WEB_DEPLOYED_FOR_HUMAN_REVIEW`，`HUMAN_ACCEPTED = false`。
* **本轮 5 个门禁全 PASS，deploy / online-smoke 均 skipped（已确认）**，
  两个 aim job 的 token 分别是 **61/61** 与 **10/10**，并集仍是 65 条契约。
* **待决策**：拆后三次 `exec` 为 7 m 36 s / 8 m 14 s / 8 m 18 s，"≤8 min"未稳定达标；
  超出部分来自 `save-audit` / `menu-return` 的正常波动，而这两个门禁本轮被明确排除在优化范围外，
  因此不自行扩大范围、不继续优化。**CI 性能优化到此停手，不进入 B批。**
