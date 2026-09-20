# B18 有限交付协议与证据

日期：2026-09-20。范围冻结在 B18；不进入 B19，不重跑全量审计，不新增功能。

## 候选身份

- 分支：`codex/presentation-upgrade-20260919`。
- 当前 HEAD：`46d215f40092dab6661ded92afc4eff0742a9e50`（B17 基线）。当前 HEAD 没有被标记为 B18 生产提交；B18 候选是本工作区未提交的有限变更。
- B17 可玩生产基线：`80aae7255ac16256df944af6e68f04adbdd68696`。旧 B17 Web/Windows 构建和 B17 失败证据保留。
- 构建时运行时源码指纹：`eba9517341953cc9fac25f1ddfbaa5d3e4367712ad9c5aa9056fed61236137b3`，共 2202 个文件。规则是从 `Don't stop` 递归取文件，排除 `build/`、`evidence/`、`.godot/`、`docs/`、`tools/` 和 `.import`，按相对路径排序，逐行拼接 `relative-path<TAB>raw-file-sha256` 后做 UTF-8 SHA-256。导出后只更新了文档和工具，运行时源码集合未变。

当前候选导出物如下；Windows EXE/PCK 是同一导出对，ZIP 只封装这两个文件，Web 三个核心文件与 `index.pck` 由同一 Web 身份生成。

| 产物 | 字节数 | SHA-256 / Web identity |
|---|---:|---|
| `build/b18-windows/Don't stop.exe` | 109,197,312 | `ddaca81def3824832bd659cfda86e9d78cf2b2317743d58fc99bd545a6151655` |
| `build/b18-windows/Don't stop.pck` | 41,354,260 | `95617260051b951082dae7a3a1af6e504c6c681aca6f4716d36b086fec66acf4` |
| `build/b18-windows.zip` | 76,646,296 | `870e9fc775efc1fac098c7eac207375f4edc0217380a8f1cd02e0a3111c6238a` |
| `build/b18-web/index.html` | 19,729 | `a9ad944c0f3531aaa4eb0a30bc0ef7e51e2084eedd692ae6d9dc37fd95665a80` |
| `build/b18-web/index.js` | 279,815 | `33c94cb3175f3333b82e2a3be5e8e86f77986f0aa2042b1631f6367a4e5bb6ba` |
| `build/b18-web/index.pck` | 41,354,260 | `95617260051b951082dae7a3a1af6e504c6c681aca6f4716d36b086fec66acf4` |
| `build/b18-web/index.wasm` | 39,514,754 | `fc74679e3b97f76878947fcd4fbe1268cbfa6188182a33bbc3f5dc9bfa57d0` |
| Web identity | — | `a7731530fd25f4c7cc9b079ca765d17ec46288d1b3137fc880d94074210313f2` |

`windows-export-final-2.log` 和 `web-export-final-2.log` 均为 Godot 4.7.2 导出成功、无 `ERROR:`。ZIP 和构建目录被 `.gitignore` 忽略，提交只包含源码、测试、诊断脚本和本协议。

## Web A/B/C/D 对照

环境固定为 Godot 4.7.2 单线程、headed Chromium、D3D11、1280x760、RX 7900 XT；未与录屏、截图或压缩并跑。帧时间是原始每帧样本，`slow_run_ms` 是原有连续慢帧口径；阈值仍为 p95≤18.5 ms、p99≤25 ms、>33.3 ms<0.5%，不得把 max 长帧改写为平均 FPS 或“稳定锁 60”。A/B/C 的 B11/B18 技术路径会补满 HP；它们不是正常生存可玩性证明。

| 运行 | 构筑与身份 | 种子/窗口/采样 | HP 补充 | 实际活跃数量（峰值） | p95 / p99 / max | 慢帧与 >50 ms |
|---|---|---|---|---|---|---|
| A | B17 原始玩法与原始性能；临时 `b18-a3-web`，identity `c678641a…` | seed 808，stage 39，weapon 112，申请 44 s；实际 combat 46.3 s，约 0.25 s 人口采样、逐帧性能 | 是，B11Stress inflated HP | ordinary 38，giant 0，enchanted 0，enemy shots 1，screen ordinary 19 | 14.58 / 29.31 / 145.25 ms | 40/5694（0.703%），>50 ms 4，slow 317 ms |
| B | B17 玩法与 B18 性能修复；临时 `b18-b3-web`，identity `05850d69…` | 同 A | 是 | ordinary 45，giant 0，enchanted 0，enemy shots 1，screen ordinary 17 | 11.11 / 12.55 / 145.18 ms | 5/6332（0.079%），>50 ms 4，slow 276 ms |
| C | B18 正式玩法/性能；`b18-web`，identity `a7731530…` | seed 808，stage 39，weapon 112，申请 15 s；B18Run 完整 round 实际 46.4 s | 是，技术路径 | ordinary 117，giant 3，enchanted 8，enemy shots 6，screen ordinary 34；damage 3719，kills 3424 | 18.06 / 21.85 / 148.66 ms | 5/3746（0.133%），>50 ms 2，slow 188 ms |
| D-Web | C 的正式代码加 `capacity` 夹具，cap 256 | seed 808，stage 39，申请 4 s；B18 simulation 4.0058 s（round bookkeeping combat 9.2 s） | 是，高 HP top-up | ordinary 139，giant 2，enchanted 8，enemy shots 256；damage/kills 0 | 141.27 / 146.49 / 146.49 ms | 33/53（62.3%），>50 ms 33，slow 3752 ms |
| D-native | 同一 capacity 夹具的 Windows/native 运行 | seed 808，stage 39，4.0067 s | 是，高 HP top-up | ordinary 176，giant 2，enchanted 8，enemy shots 256；damage/kills 0 | 11.11 / 16.67 / 135.84 ms | 2/522，>50 ms 1；CPU physics p95/max 57.338 ms |

正式 B18 上限是 180，D 的 256 是独立技术压力夹具。D-Web 达到 256 弹的实际维持约 4.0 s，D-native 也达到 256 弹约 4.0067 s；这证明夹具容量，不证明正式 180 配置下的长时生存或 Web 性能目标。

A→B 的确定性热点变化是 T10 capped-kill 路径：`B18_REFRESH` 的 200 次微基准从 `refreshes=200,usec=485125` 降到 `refreshes=0,usec=175`。B 的 p95、p99、>33 ms 占比也下降；max 和 >50 ms 仍保留，且 B 的实际 ordinary 峰值更高、帧数更多，不能把它解释成纯密度相同的 A/B 实验。C 满足原定 p95、p99、>33 ms 候选阈值，但保留 max 148.66 ms、2 个 >50 ms 记录；`18.06/21.85/0.133%` 是帧分位与比例，不能称为平均 FPS或稳定锁 60。

有效运行还包括 stage 40 的 A3/B3 控制（seed 808、weapon 112、申请 44 s）：A `8.33/18.07/147.24 ms`，15/6522 帧 >33 ms、4 帧 >50 ms，约 94 shots；B `8.85/17.77/141.03 ms`，10/6479 帧 >33 ms、4 帧 >50 ms，约 91 shots。它们是 Boss/阶段控制样本，不替换 stage 39 的 A/B/C 表。

`stress-b18-c39-cap180-run-C.json`（run1）没有作为结果使用：headed Chromium 页面被后台节流到约 1 FPS，约 256 s 墙钟后无完整 summary；保留原始 JSON。`stress-b18-c39-cap180-run2-C.json` 是最终 C：在脚本中加入 `page.bringToFront()` 与三个 Chromium background-throttling 禁用参数后重新取得上述 C 结果。更早的 `stress-b18-c39-final-C.json`/`stress-b18-c39-cap180-C.json` URL 没有 `b18=1`，使用旧 B11Stress 驱动，只作为诊断保留，不能冒充 C。

## 两次正常 HP 死亡

两次均来自 `B18Play`，不是 B11Stress：seed 808、weapon 112、`driver=avoid`，每 0.12 s 以 8 个方向试探 `test_move`，综合普通怪距离和弹体线段距离后用真实输入移动；没有补 HP、强制击杀、无敌或移除敌人。`_grant_everything()` 走合法商店路径给满 attachments、weapons、talents 和 legacy reward，日志为 `rewards_owned=22 talents=24 reward_group=22`；T10 capped-kill 微基准刷新为 0。日志可确认 start HP=8、HP max=11、weapon=112、最终 HP=0，但没有记录 player level、每个三源成长项的等级、护盾值、每次攻击的 source/attacker、raw damage 和实际扣血，因此这些数值不补造。

- Stage 31：`normal31-final.log`，10.7479 s 死亡，ordinary 峰值 51、screen 42、enchanted 2、giant 0、enemy shots 2；`hits=12`、`zone_hits=6`、无同帧重复（`same_frame=0`）。5.416 s 以后多次 meteor 选择均为 `no_legal_visible_point`，没有确认 meteor 命中。日志没有逐击扣血或护盾消耗轨迹，不能把死亡归因到某一个来源。
- Stage 39：`normal39-final.log`，5.7137 s 死亡，ordinary 峰值 176、screen 121、enchanted 8、giant 3、enemy shots 1；`hits=11`、`zone_hits=7`、无同帧重复（`same_frame=0`）。2.85/3.85 s meteor 均无合法可见点，4.85 s 生成过一个 shock；没有 root window 或同一弹重复命中的证据，但日志仍没有逐击实际扣血。

`Hero.onHit` 的 variant damage 只在非百分比来源乘一次；B18Contracts 的 87 项测试通过了 variant 一次性伤害、巨型碰撞体、墙体反射和高 delta 先命中玩家等回归。现有正常日志未显示卡墙、倍率重复、同弹重复命中、预警与伤害不一致或联合危险没有可达通路的确定缺陷。因此这两次死亡记录为“正常 HP 压力下未归因死亡”，既不是不可玩结论，也不是难度达标证明；本轮不削弱尸潮、HP、附魔或弹幕。

## B18 原计划边界

- 31–39：最终普通 HP 曲线为 E01 基准 `[2.0,2.3,2.6,3.0,3.6,4.3,5.2,6.4,8.0]`；E02 使用同一 final scale 乘其 1.2 基础 HP。普通 cap（含 180 上限）为 `[60,68,75,84,96,108,122,136,152]`。C stage39 实际 ordinary 峰值 117；D-Web/D-native 为独立 top-up，实际分别 139/176。
- Boss：`b17-bosses-final.log` 的四个 Boss、三阶段、每阶段 22 s 受控观测 28/28 通过；请求=实际发射的弹量为 stage10 `[153,252,258]`、stage20 `[279,400,254]`、stage30 `[324,316,315]`、stage40 `[385,361,146]`。该观测未报告延迟或取消；EnemyBarrage 仍保留 `barrage_deferred`、owner/capacity cancellation accounting。交替波次的反弹由 `EnemyShot` 和 B18Contracts 墙体反射通过证明。Boss 受控观测每轮补满 HP，未测真实承伤，因此“真实承伤”仍未完成，不能写成已验证。
- 巨型与附魔：E01 巨型从 stage33 起按到达计数触发，HP×12、速度×0.55、sprite/collider/area×2.2；stage<37 同时上限 1，stage≥37 上限 3。附魔 tier1 HP×2、速度×1.08、damage×2；tier2 HP×4、速度×1.15、damage×4；stage<37 同时上限 4，stage≥37 同时上限 8；`variant_applied` 防止重复应用，且不启用 elite AI。B18Contracts 通过。
- T10：封顶击杀只续时不重复 `refresh()`；第一次加层才重算，过期清层，51/51 performance contracts 通过，A/B 微基准保留了 refresh 热点差异。
- 枪体光环：`WeaponIdle` 已加入逐武器中心偏移以减小遮挡；B17 aura contract 12/12 通过，但该次运行有 4 个 ObjectDB 泄漏和 2 个资源仍在使用，尚未完成人工视觉验收。
- 产物身份：Windows 成对 EXE/PCK、可试玩 ZIP、Web `a7731530…` 身份及文件指纹均已固定在本协议“候选身份”表。

## 仍保留的门槛

HUMAN_ACCEPTED=false。历史轨道枪 `81<85`、ObjectDB 警告和长帧未归因均保留；本轮没有关闭它们。`b18-performance-final-5.log` 51/51、`b18-contracts-final-4.log` 87/87、`b11-shot-layer-final-3.log` 54/54、`b17-bosses-final.log` 28/28，以及导入/导出日志均无 `ERROR:`，但正常 HP 两次死亡、Boss 真实承伤、光环人工视觉验收和稳定 60 FPS 仍未通过。分支推送不触发正式部署：Pages 只对 `main`，Windows Release 需要 tag 或 dispatch；不 merge、不 deploy、不发布 Release，等待真人试玩反馈。
