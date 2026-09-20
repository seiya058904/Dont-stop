# B19.1 — 性能优化续作与可试玩候选

状态：`B19_1_CANDIDATE_FOR_HUMAN_REVIEW / PARTIAL / NOT_ATTAINED`。`HUMAN_ACCEPTED=false`。

主任务仍是实际游玩流畅。此前将任务停在附魔视觉候选是执行偏差；用户要求继续后，已修复真实弹幕负载、实施性能改动，并完成 headed Web 与 Windows Release 战斗。**Web 仍不达标，Windows 单轮持续帧耗时较好但仍有尖峰；不能宣称完成流畅度验收。**

## 实际实现

1. `Monster 2/Monster2.tscn` 近战 Area2D 只检测玩家专用层 8，消除对其他怪物与墙的无效感应。实体 collision_mask、尺寸、攻击范围、伤害和频率不变。真实玩家进入仍触发原近战状态。
2. `CombatFootprint.gd` 每个完整轮廓只构造一次射线参数、复制一次排除列表，保留全部原射线与顶点。80 个真实世界位置、5120 条射线的新旧顶点完全一致；首次原生局部比较 8255→4523 μs。这个局部收益不等于整帧提速。
3. `Combat.gd` LOS 消费者按 exclusion revision 更新，避免每条射线重复复制整组 RID，也避免旧的“另一消费者清除 dirty 后留下失效 RID”回归。组缓存保持 physics tick 边界、只读快照、奖励增删失效，并补 tree_exited 二次失效，覆盖退出回调中重入读取。
4. `BaseMonster.gd` 使用有界、不可变的附魔/相位/受击材质集合，解决共享后串闪风险；去掉每怪从未播放的 AudioStreamPlayer2D，仍由原声音池播放。`HitLabel.gd` 生命周期计数替代每次生成前扫描 group。可证明减少实例/扫描，但第一轮没有证明整场帧耗时改善，因此不计为已兑现的 FPS 收益，也不声称合批已解决。
5. 保留用户指定的 Minecraft 式本体像素流光：原精灵 alpha 内的蓝紫/紫红斜向阶梯光泽，巨型随本体缩放；共享时钟暂停感知，死亡取消附魔，受击独立。未重画身体、未降低怪数/弹量/分辨率/伤害或碰撞更新频率。

已有空状态 guard、共享音频池、敌弹墙层、雾缓存、B19 group cache 不是本次新增优化。

## 负载修复与证据口径

旧驱动先占满 special budget，随后生成 E14/E10 请求被正式工厂替换成普通怪，旧结果 sources=0。现在优先选择场内真实 E14/E10，再走正式 elite promotion，验证成功后才标记。D 的两名精英使用明确的 1,000,000 HP 保载夹具；普通怪保持正式 HP，玩家耐久夹具用于性能观察，不证明正常 HP 可躲。

固定 seed=20260920，热流116/电弧112，39关完整45模拟秒。保留之前失败数据，不跑到偶然绿灯为止。按用户减少重复测试的要求，没有做三 seed 矩阵。第一轮材质/节点/计数；第二轮查询/碰撞及必要正确性收尾。中间查询版本与最终感应层版本都留存，绝不只摘最终最好的一条。

以下是诊断轮次，不是严格等负载正式 A/B：虽然输入按模拟 tick、配置/种子固定，但实际存活分布和击杀数不同；后两轮增加了局部成本探针，观测开销也不完全一致。所有正式门槛均保持原值。

## 热窗结果（每轮墙钟≥5秒，毫秒）

| 平台/版本/场景 | p50 | p95 | p99 | max | >33.3ms | >50ms |
|---|---:|---:|---:|---:|---:|---:|
| Web perf-before/D | 16.52 | 29.60 | 37.28 | 54.10 | 55 (2.43%) | 1 |
| Web perf-after/D | 16.70 | 32.06 | 40.51 | 61.12 | 89 (4.02%) | 4 |
| Web perf-final/D | 17.47 | 31.43 | 38.04 | 54.79 | 76 (3.53%) | 2 |
| Web perf-contact/D | 16.06 | 26.75 | 33.12 | 52.19 | 24 (0.99%) | 1 |
| Web perf-boss/A | 6.91 | 23.08 | 38.74 | 175.86 | 185 (1.89%) | 32 |
| Windows Release / B尸潮 | 6.25 | 10.06 | 11.43 | 93.88 | 2 | 1 |

门槛：p95≤18.5、p99≤25、>33.3ms<0.5%，无新增可重复>50ms。Web混合场景最终热窗26.75/33.13ms，仍失败。Windows单轮p95/p99较低，但热窗15.417秒出现93.88ms尖峰，不能据单轮证明稳定。

完整/开场/热窗逐帧值与模拟速率见 `raw/performance-summary.json`、`raw/windows-perf-horde.json`。Web 混合开场最高256.59ms，Boss开场最高1216.46ms；均未隐藏、未断言是 shader 编译。Windows完整窗口最高172.27ms。

- Web D实际两只持续源，原参考累计活着源发射116，峰值21弹；最终22弹、160非精英+2精英峰值。旧参考178+2，不能把全部帧差归为同负载收益。
- Windows B保持正常怪物HP，一整轮真实热流/电弧，峰值166非精英/1精英，4304伤害事件、3357击杀；最高7弹。这是尸潮场景，不冒充弹幕容量。
- Web 40关实际Boss、持续源、主动技能和安全窗运行90模拟秒，持续源发射203，实际敌弹峰值147。只到第二阶段，第三阶段完整循环 **NOT_ATTAINED**；147峰值也不代表180弹持续容量通过。
- 连续计数目前是存活所有者动作累计，不是全局永久累计；D的HP夹具保持所有者存活。出生属性比例、独立灼烧/减速/派生/掉落拾取全链路计数未完全齐备，不填零或宣称全覆盖。

局部探针：查询优化后、感应层修改前，移动碰撞4.561秒/304882调用，约14.96μs/次；最终总3.253秒，实际群体分布不同。BaseMonster process约1.259秒、最外层命中含派生约0.697秒、轮廓约0.042秒。后两项可能嵌套在其它计时中，不能相加当总CPU。它们说明生成/轮廓并非当前整场主要瓶颈；完整物理服务器、渲染提交/驱动等待尚未得到独立归因，剩余瓶颈没有伪装成已解决。

环境：Godot 4.7.2 ed1daf0bf；RX7900XT；Web Chromium151/ANGLE D3D11、1280×760、DPR1；Windows Forward+ Vulkan、项目窗口1536×864。项目逻辑viewport410×230、canvas_items stretch，未降低尺寸。时间是单调 process-frame 间隔，不是GPU呈现时间；process/physics monitors是重叠代理。Release static-memory/orphan为N/A；遗留日志的零不代表零内存。没有OS进程内存高水位数据。

## 检查、缺口与旧失败

最终原生 B191Runtime 55/55，无脚本错误或退出诊断；两次回营敌人/敌弹归零、303节点、Debug orphan=0。包括材质独立受击、真实感应、相同墙轮廓、退出回调重入、奖励缓存与持续源生命周期。B12LineOfSightRegression 12/12，无诊断。旧B19配置24/24记录保留，但其原退出警告未抹掉。没有把两次回营写成十次。

Windows正式EXE实际完成战斗并走正常退出，exit0，仍有20 ObjectDB实例退出警告。Web脚本保留原始页面错误，不再过滤 currentTime；退出按现有 Demo.quit_game 路径。历史railgun81<85未改；广泛旧门禁/三seed/十轮/正常HP可躲性/持续180弹容量未重新跑。PR CI以远端实际状态为准。

## 可试玩与交接

- Windows：`build/b191-perf-windows/Dont-stop.exe` + 匹配的 `Dont-stop.pck`；压缩包 `build/b191-perf-windows.zip`。
- Web：`build/b191-delivery-web/index.html`。在项目根执行 `node tools/b10-static-server.js "<项目绝对路径>/build/b191-delivery-web" 8226`，访问 `http://127.0.0.1:8226/index.html`。
- 原生：现有 `PLAY_GAME.bat`。
- `manifest.json` 保存生产源码及最终EXE/PCK/Web核心/ZIP哈希。`source.patch`、`new-source/`、`prechange/`、被引用原始JSON/日志和像素附魔预览均在交接包 `build/b191-performance-handoff.zip` 中。旧参考构建保留。
- Web性能测量对应contact构建；最终delivery另补tree_exited缓存正确性修复并通过55项运行时检查，未把它冒称同一字节产物。Windows战斗使用最终delivery源码。

feature push只触发PR门禁，正式Pages部署限main；不merge、不deploy、不Release。`HUMAN_ACCEPTED=false`。总体仍PARTIAL：Web帧门槛、开场/热窗尖峰归因、Boss第三阶段、持续容量与最终人类试玩尚未完成。
