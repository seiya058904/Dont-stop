"""Build the review tables from final raw engine evidence; fail on incomplete gates."""
import json, pathlib, re, statistics

root = pathlib.Path(__file__).resolve().parents[1]
out = root/'docs/iteration/evidence/m8'
def read(name): return json.loads((out/name).read_text(encoding='utf-8'))
def rows_from(name, marker):
    return [json.loads(line[len(marker):]) for line in (out/name).read_text(encoding='utf-8').splitlines() if line.startswith(marker)]
def mean(rows,key): return statistics.mean(r[key] for r in rows)
def pct(number): return f'{100*number:.1f}%'

encounters = read('encounters.json')
baseline = read('baseline-encounters.json')
assert len(encounters)==len(baseline)==30
assert all(r['clear'] or r['death'] for r in encounters)
assert all(r['cleanup']==0 for r in encounters)
bosses=[]
for tier in ['middle','high','full']:
    original=rows_from(f'bosses-{tier}-verified.txt','M8 BOSS ')
    final=rows_from(f'boss-{tier}-final-budget.txt','M8 BOSS ')
    assert len(original)==3 and len(final)==1
    bosses += [r for r in original if r['stage']!=30]+final
for r in bosses:
    assert r['clear'] and not r['death'] and r['boss']['phase_two']
    assert r['player_movement']>100 and r['boss']['travel']>100
    for action in {10:['charge','cleave','slam'],20:['brood','lockdown','pulse'],30:['dash','sweep','burst']}[r['stage']]:
        assert r['boss']['actions'].get(action,0)>0
    if r['tier']=='full':
        low,high={10:(30,50),20:(40,60),30:(45,75)}[r['stage']]
        assert low<=r['seconds']<=high
(out/'boss-final.json').write_text(json.dumps(bosses,indent=2,ensure_ascii=False),encoding='utf-8')
regression=read('regression/index.json')
assert len(regression)==21 and all(r['passed'] for r in regression)
assert len(read('global-combinations.json'))==576
assert 'checks=1409 failures=0' in (out/'globals-r4.txt').read_text(encoding='utf-8')
assert 'checks=49 failures=0' in (out/'global-refill-verified.txt').read_text(encoding='utf-8')
for name in ['contracts-final','boss-stops-final','ui-final','contracts-fx-final','visuals-final']:
    assert read(name+'-execution.json')['code']==0
    assert not read(name+'-execution.json')['errors']
    assert read(name+'-execution.json')['product_unchanged']
perf=read('performance.json')
assert len(perf)==24 and all(r['code']==0 and r['metrics']['draw_calls']>0 for r in perf)
fx=read('performance-final-fx.json')
assert len(fx)==8 and all(r['code']==0 and r['metrics']['draw_calls']>0 for r in fx)
perf=[r for r in perf if r['scenario'] not in ['telegraph','particle']]+fx
performance=[]
for scenario in ['normal','late','boss','projectile','telegraph','particle']:
    pair={version:{key:statistics.median(r['metrics'][key] for r in perf if r['scenario']==scenario and r['version']==version) for key in ['p50','p95','p99','max']} for version in ['M7','M8']}
    pair.update(scenario=scenario)
    pair['review_needed']=any(pair['M8'][key]>max(pair['M7'][key]*1.35,pair['M7'][key]+8) for key in ['p95','p99'])
    performance.append(pair)
assert not any(r['review_needed'] for r in performance), 'Paired performance regression requires diagnosis/retest'

groups=[]
for name,all_rows in [('M7',baseline),('M8',encounters)]:
    for first in [1,11,21]:
        a=[r for r in all_rows if first<=r['stage']<first+9]
        groups.append(dict(version=name,range=f'{first}–{first+8}',pursuit=mean(a,'pursuit_uptime'),pressure=mean(a,'pressure_uptime'),threats=mean(a,'simultaneous_threats_mean'),peak=max(r['simultaneous_threats_peak'] for r in a),damage=sum(r['incoming_damage'] for r in a),deaths=sum(r['death'] for r in a)))
assert groups[-1]['pursuit']>groups[-3]['pursuit'] and groups[-1]['threats']>groups[-3]['threats']
assert sum(r['pursuit_uptime']>0.5 for r in encounters if 21<=r['stage']<=29)>=7
summary=dict(status='M8 IMPLEMENTED / READY FOR THIRD HUMAN REVIEW',H1_STATUS='SECOND_FEEDBACK_ADDRESSED',HUMAN_ACCEPTED=False,regression_processes=len(regression),regression_checks=sum(r['checks'] for r in regression),global_checks=1409,real_pairs=576,refill_checks=49,encounters=len(encounters),clears=sum(r['clear'] for r in encounters),deaths=sum(r['death'] for r in encounters),groups=groups,performance=performance,bosses=[{k:r[k] for k in ['tier','stage','seconds','damage_received','boss_successful_hits']} for r in bosses])
(out/'summary.json').write_text(json.dumps(summary,ensure_ascii=False,indent=2),encoding='utf-8')

text='''# M8 — Combat Content Quality Revision

**M8 IMPLEMENTED / READY FOR THIRD HUMAN REVIEW**

`H1_STATUS = SECOND_FEEDBACK_ADDRESSED` · `HUMAN_ACCEPTED = false`

基线为 feature branch 的 `55a22ae`。本轮只修订迭代目录，内容保持 24 枪 / 24 全局强化 / 24 天赋 / 12 普通敌人 / 3 Boss / 6 区 / 30 遭遇；不合并 main、不 Release、不进入 M9。全部证据来自实际 Godot 4.7.2 进程，后台自动输入与离屏截图不等于真人验收。

## 先复现，再改动

修改游戏前保存了独立的 M7 源码副本（工作区 archive/workspace-support/m8-baseline），比对见 baseline-source.json。基线行为测试先跑原型和 M5 的 12 类敌人、3 个 Boss，定点与接近响应各有记录；高生命、静止角色仅用于这个诊断，不用于 Boss TTK。

基线中 E07/E08/E10 本体追击时间为 0，16 秒窗口分别仅移动约 1.2/1.2/2.0 秒；原型 E01 逼近后持续接触，累计造成 14 点伤害。原型的直接压迫来自逼近和短空窗，后续支援与炮击过长的停止时间让玩家获得固定安全输出位。原型近身停止不等于没有威胁，因此同时记录位移、攻击和接触，不能单凭位移率评价所有敌人。

修订后：恢复期持续移动；冲锋按距离选路线并继续追近；盾兵主动推进；炮击交替束线与标记区域并重新定位；支援跟随推进单位；召唤本体移动且有总量/同时存活上限；自爆明显追击；侧翼单位切侧近身。后半段使用混合队列、不同侧生成和有上限的双单位节奏。修复了旧 rhythm 分支把混合阵容连续替换成单一兵种 7–15 秒的问题。

实战还复现了玩家默认碰撞掩码漏掉新区域墙层：玩家能出界、敌人被墙拦住。Hero 的掩码现包含该层，并用真实移动撞墙验证。这是移动/追击异常的实际原因之一。

## Boss 三枪死亡的原因

旧 Boss HP 为 180/150/165，只有 Boss 1 有 24 护甲。使用合法旧槽位组合和满天赋，蓄能轨道炮分别 3/2/2 发击杀，散射火箭 5/3/4 发、微型追踪导弹 5/4/5 发；电驱转管机枪虽需 33/27/32 次开火，却也仅约 2 秒。

baseline-damage.json 逐次保留 input/resolved/applied、HP 前后、护甲前后、暴击、派生深度、DOT 和 volley。轨道炮首发输入 109.392，护甲后实际 49.2255；后续无甲普通满蓄力约 109.39，暴击约 164.09。倍率由原有 Tier V ×4.8、合法强化/天赋、满蓄力 ×2.5、一次暴击 ×1.5 构成，没有额外弱点倍率。DOT 为每 0.25 秒 0.6，刷新单条计时，非无限叠层。

没有发现重复 callback 或一次弹丸无限命中的证据：射线访问表、弹丸 finished/visited、派生深度上限和死亡幂等均有实际交叉检查。多火箭、裂片、回程锯盘及 DOT 的合法多段不能当作重复回调。结论是旧 Boss 生命预算与已存在的高阶合法火力严重不匹配；先记录上述证据，再调整生命与行为。诊断并未给每个物理弹丸新增唯一追踪 ID，不能据此声称穷尽了所有可能伤害链。

现在 Boss 1 为 4400 HP/120 护甲，Boss 2 为 6000 HP，Boss 3 为 6200 HP；后两者无护甲。每个 Boss 仍使用真实伤害链，无按武器限伤或强制延长计时。24 枪完整强化实射 DPS 表见 full-build-dps.json；其中 Tier V 单目标持续测量最高为 124，约 151.4 DPS，据此选作最强完整配置的 TTK 样本。

## 敌人行为合同

真实获得玩家位置、靠近、玩家换位/贴近、恢复期移动、召唤上限、死亡及回营清理均有实跑。下表位移单位为世界像素；追击为采样窗口内实际朝玩家移动的时间，不把函数调用当作追击。

| ID | 总位移 | 追击秒 | 最小距离 | 恢复期位移 |
|---|---:|---:|---:|---:|
'''
for r in read('enemy-contracts.json'):
    text+=f"| {r['id']} | {r['travel']:.1f} | {r['pursuit_seconds']:.1f} | {r['minimum_distance']:.1f} | {r['cooldown_motion']:.1f} |\n"
text+='''
E06 在攻击后按设计自毁，恢复期位移不适用。最终 contracts-final 有 52 项检查；四种危险几何均实际验证预警期不伤人、到时才命中。

## 30 遭遇压力曲线

同一 Tier III 117、满天赋、各版合法完整强化，逐关重置等级 1 / 8 HP，按真实武器计时器开火，使用正常碰撞移动。普通关每场 45 秒；Boss 击杀/死亡结束。两版全局强化模型和玩家撞墙修复不同，因此这不是只改变 AI 的单变量伤害实验；主要门槛是修订版自身后段相对前段的压力曲线。

PURSUIT UPTIME：每约 0.1 秒采样，至少一个存活敌人的实际位移在朝向玩家方向上的投影超过 0.6 像素。PRESSURE 额外含 42 像素内接触；同时威胁含追击、接触或攻击前摇。远程/近战构成按 actor_samples_by_role 保存，这是存活角色采样数，不是生成数量。完整逐关 clear/death/时间/入伤/追击/峰值/构成见 encounters.json 和 baseline-encounters.json。

分段统计排除第 10/20/30 Boss，以免不同时长混淆普通遭遇：

| 版本 | 普通关段 | 追击覆盖 | 压力覆盖 | 同时威胁均值 | 峰值 | 总入伤 | 死亡 |
|---|---|---:|---:|---:|---:|---:|---:|
'''
for r in groups:
    text+=f"| {r['version']} | {r['range']} | {pct(r['pursuit'])} | {pct(r['pressure'])} | {r['threats']:.2f} | {r['peak']} | {r['damage']:.3f} | {r['deaths']} |\n"
text+=f"\n修订版整套 30 关：{summary['clears']} 次完成、{summary['deaths']} 次死亡、30 次退出后的残留实体均为 0。遇到死亡也记录为完成一次测试，不冒充通关。最后仅 Boss 3 生命预算继续校准到 6200；最终三档第 30 关由下一节独立实战覆盖，27 个普通关配置未再变化。\n"
text+='''
## 三 Boss × 三档真实战斗

角色正常生命、护盾、拾取治疗和碰撞，不传送、不无敌、不强制伤害。机器人用真实移动/Shift 输入、武器计时器、射弹/射线；中档 117 会预判目标移动，躲避器从实际危险区选择退出方向。初次机器人绕柱丢失射界和死亡保留在旧日志，改进自动操作后重新完成战斗，没有为此全局削弱敌人伤害。

表中入伤来自 Hero.incoming_hit 信号，包含召唤物；Boss 命中单独按来源标记。零命中表示这一场机器人躲开了，不表示技能不伤人；危险区命中与多次实战记录另有覆盖。中、高、完整三档都购买 24 强化和满天赋，区别为所用枪；其中 113 和 124 同为 Tier V。

| 档位/枪 | Boss关 | TTK秒 | 入伤 | Boss命中 | 玩家位移 | Boss位移 | 两阶段 |
|---|---:|---:|---:|---:|---:|---:|---|
'''
for r in bosses:
    text+=f"| {r['tier']}/{r['gun']} | {r['stage']} | {r['seconds']:.2f} | {r['damage_received']:.2f} | {r['boss_successful_hits']} | {r['player_movement']:.0f} | {r['boss']['travel']:.0f} | 是 |\n"
text+='''
9 场均完成，三个核心攻击各自实际执行、两阶段均到达。Boss 1 为 charge/cleave/slam；Boss 2 为 brood/lockdown/pulse；Boss 3 为 dash/sweep/burst。详细执行次数和每 5 秒战斗快照保留在 bosses-*-verified.txt 与 boss-*-final-budget.txt，汇总 boss-final.json；第 30 关使用最终生命预算的补测。`remaining_hp` 是死亡前最后一次 50ms 采样，可能仍为正；是否完成由实际 LevelServer 结算状态判断。

## 全局强化、购买和回归

- globals-r4：1409 项通过，含 576 个真实开火组合、24 项首购/重复连点/保存读档、当前和未来枪属性、schema 1–5 合法重复实例迁移、幂等和非法数据拒绝。
- M8Mechanics：11 项真实机制对照，覆盖反弹保留、制导转速、预热、换弹、回正、伤害、冲量、暴击、散布和爆炸边缘。M3/M6 保留的链电、贯穿、裂片、DOT、回程、Boss 阶段与停止路径继续运行。
- global-refill-verified：49 项通过，24 枪真实直接击杀各仅返还一发，派生击杀不递归回填。测试保留原型散弹/连发每次消耗多发的合同，并隔离自动换弹；未修改原枪弹药语义。
- regression/index.json：21 个进程、921 项检查全部通过。包含钱包 9999、退出五路径和主菜单退出、武器/弹匣/天赋、保存恢复、伤害交叉、冻结内容、死亡/回营。M8Supply 有 24 枪各三次完整/部分换弹及取消/空库存检查。
- 最后冻结后又跑 contracts-final、boss-stops-final、ui-final；重复检查不重复累加。历史 M7 装配/实例 UI 与库存测试被 M8Globals/M8UI/M8Supply/M8Refill 替代，其旧断言不再代表当前产品合同；历史文件保留。

新保存结构为 schema 6 / owned_global_upgrades。只保留旧定义 ID、存档验证用槽信息及不可达历史 UI 资源；当前玩家没有实例创建、安装、卸下或槽位管理入口。24 状态只可购买一次，购买后 refresh 所有枪并保存，新枪计算读取同一全局状态。旧实例合法拥有即折叠，重复不叠层、不退款。

## 统一预警与原生离屏证据

CombatTelegraph 为共享世界空间绘制：危险填充、统一橙红边缘和末段脉冲；冲锋有移动箭头/双边界，AoE 有中心标记/收缩/圆周进度，扇形显示覆盖并填充，Beam 细预警后才变明亮攻击，扫射带旋转范围和方向箭头。HostileVFX 覆盖蓄力/释放/冲刺/爆炸命中，敌弹附 7 点短尾迹，VFX 全局上限 32、寿命 0.28 秒，无全屏白闪；八条火花线使用一次批量绘制。

visuals-final 在原生 OpenGL 兼容渲染器保存 38 张 1366×768 图片：24 张预警/攻击状态、12 张阶段/持续行为状态、营地和强化页。画面取自游戏原生 410×230 视口，按像素最近邻放大；已检查代表画面。为了明确展示两个阶段，视觉场景可把 Boss 血量设到 49%，该场景不用于 TTK。Vulkan 最小化离屏首跑报 surface capabilities -13，停止后改用 GL，未把失败当成成功或声称 Vulkan 性能已验证。

![全局武器强化](upgrades.png)
![冲锋预警](E03-charge-warning.png)
![炮击收缩圈](E10-circle-warning.png)
![方向扫射及分段生命条](B03-line-sweep-warning.png)

## 六类成对性能

先停止其他 Godot 测试，再按每场景 M7 → M8 → M8 → M7 顺序运行，每进程 20 秒、前 3 秒预热；原生 410×230 内容视口、1366×768 后台窗口、同一 GL 渲染器和驱动，均有实际 draw calls。最小化后台状态的普通帧约 32ms，这不是前台最高帧率基准。下表为两次测量的中位数，单位 ms；max 是各次最大帧时间的中位数，原始最坏帧仍在 performance.json。

预先使用 p95/p99 超过基线 max(×1.35, +8ms) 作为需要定位和重测的信号，不把双样本视为统计学性能保证。普通/后期/Boss、400 实体弹极端压力、60 并发危险区、连续爆炸/枪口颗粒分别覆盖；两版测试的危险区、实体弹和敌人生成输入一致，装饰优化作为真实改动接受测量。

初轮六场景共 24 进程中，预警极压 p99 从约 38.36 增至 50.87ms，虽未超过上述粗门槛，但两轮都复现，因此仍进行了局部优化：只把装饰释放 VFX 从 48 降至 32，并合并八条火花线的绘制。全部 60 个危险区、伤害判定和预警几何保留。重新验证清理/完整截图后，对预警和粒子追加 8 个成对进程，保存 performance-final-fx.json；下表这两行取优化后重测，其余四行保留原批次（装饰峰值低于新上限）。这 32 个测量进程均保留原始记录，不混称全场景在同一次源码冻结中重跑。

| 场景 | M7 p95 | M8 p95 | M7 p99 | M8 p99 | M7 max | M8 max |
|---|---:|---:|---:|---:|---:|---:|
'''
for r in performance:
    text+=f"| {r['scenario']} | {r['M7']['p95']:.2f} | {r['M8']['p95']:.2f} | {r['M7']['p99']:.2f} | {r['M8']['p99']:.2f} | {r['M7']['max']:.2f} | {r['M8']['max']:.2f} |\n"
text+='''
这批测量没有触发新的严重回退信号。极端压力的长尾 spike 仍以原始数据为准，不能解释为稳定高帧率，也不能外推到其他硬件或 Vulkan。

## 失败、证据边界与复跑

所有初次失败/被中止日志保留：旧机器人无法合理躲避造成 Boss 死亡；早期预警截图 Vulkan surface 失败；矩阵 fixture 的 StringName ID/激光坐标问题；回填 fixture 的散弹扣费/自动换弹误判。修订后以本文指向的最终日志为准，未把旧失败混计为通过。

baseline-behavior.txt 与 final-import.txt 仅规范化终端行末空白和重复空白尾行；错误和事件文本完整保留。原始字节已归档在工作区 archive/workspace-support/m8-raw-terminal-logs，原始/发布 SHA256 见 text-normalization.json。

保留回归中的固定音频退出诊断只包含 AudioStreamMP3/AudioStreamPlaybackMP3 与 Cephalopod.mp3，按原 M6/M7 分类列在 regression/index.json；没有宣称修复这个历史诊断。若出现其他运行时错误或不同泄漏身份则不在该豁免内。

早期执行记录的 source_unchanged 可能为 false（同一会话中继续改测试或调整战斗）；原始哈希和失败日志保留。最终短测及性能 runner 同时记录脚本、场景、project.godot 与 changed_during_run；Boss 3 预算由最终单关实战覆盖。跨版本普通遭遇的测试角色逻辑一致，旧版和新版强化数量/碰撞差异已明确，不能把入伤差异全部归因于敌人行为。

复跑：`python tools/run-m8.py <标签> <测试场景> [参数]`；`python tools/verify-m8.py`；其他游戏进程结束后 `python tools/benchmark-m8.py` 与 `python tools/benchmark-m8.py --final-fx`；最后 `python tools/report-m8.py`。基线副本只由起点 55a22ae 创建一次，freeze-m8-baseline.py 拒绝覆盖已有基线。运行用隔离测试存档，不覆盖玩家正式存档。

真人短路线见 [README-PLAY](../../../../README-PLAY.md)。工程完成后停止，等待第三次真人试玩。
'''
(out/'README.md').write_text(text,encoding='utf-8')
print(json.dumps({k:v for k,v in summary.items() if k not in ['groups','performance','bosses']},ensure_ascii=False))
