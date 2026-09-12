"""Generate review tables from recorded engine results; no simulated combat values."""
from pathlib import Path
import csv, json, statistics

root = Path(__file__).resolve().parents[1]
out = root / 'docs/iteration/evidence/m7'
def read(path): return json.loads(path.read_text(encoding='utf-8'))
def write(name, value): (out/name).write_text(json.dumps(value,ensure_ascii=False,indent=2),encoding='utf-8')
weapons = sorted(read(out/'tier-measured.json'),key=lambda r:(r['tier'],r['price']))
columns = ['id','name','tier','price','damage','rate','magazine','reload','burst_1s','single_window_dps','three_target_window_dps','seconds','range_or_path_limit','mechanic']
table = []
for r in weapons:
    e = r['effective']
    table.append(dict(id=r['id'],name=r['name'],tier=r['tier'],price=r['price'],damage=e['damage'],rate=e['rate'],magazine=e['magazine'],reload=e['reload'],burst_1s=round(r['burst_damage'][0],3),single_window_dps=round(r['target_damage'][0]/r['seconds'],3),three_target_window_dps=round(sum(r['target_damage'])/r['seconds'],3),seconds=r['seconds'],range_or_path_limit=e.get('projectile_path_limit',e['range']),mechanic='/'.join(e['tags'])))
with (out/'weapons.csv').open('w',encoding='utf-8-sig',newline='') as f:
    writer=csv.DictWriter(f,fieldnames=columns); writer.writeheader(); writer.writerows(table)
lines=['# M7 武器实测与固定 Tier','',
'24 把实枪，等级 1、无天赋/配件，固定三个静止高血量目标，真实物理命中。射击窗口约 6 秒，按实际耗时计算，自动换弹；停止后等待 1.5 秒收集在途伤害。首秒爆发独立在运行中采样。0 爆发可由蓄力、弹道、延迟爆炸导致，并非零收益。',
'', '窗口 DPS 是有限窗口持续开火指标，包含窗口内实际换弹，不是无限时间稳态 DPS。弹匣较大的枪可能未在六秒内换弹，因此同时列容量/换弹；另用 90 场长于窗口的遭遇审核检查实际续航。伤害列是单弹/单 tick 基础量，各机制弹丸数、束数、蓄力倍率不同，不能直接以 damage×rate 比较全部武器。',
'', '|枪|Tier|金币|伤害|首秒伤害|窗口单体 DPS|三目标总 DPS|容量/换弹秒|机制|', '|---|---:|---:|---:|---:|---:|---:|---|---|']
for r in table:
    lines.append(f"|{r['name']}|{r['tier']}|{r['price']}|{r['damage']:.2f}|{r['burst_1s']:.2f}|{r['single_window_dps']:.2f}|{r['three_target_window_dps']:.2f}|{r['magazine']}/{r['reload']}|{r['mechanic']}|")
lines += ['', '## 分档判断', '', '|Tier|价格区间|实测单体窗口 DPS 范围|中位值|', '|---|---|---|---|']
for tier in range(1,6):
    group=[r for r in table if r['tier']==tier]; values=[r['single_window_dps'] for r in group]
    lines.append(f"|{tier}|{min(r['price'] for r in group)}–{max(r['price'] for r in group)}|{min(values):.2f}–{max(values):.2f}|{statistics.median(values):.2f}|")
lines += ['', 'Tier 的价格区间互不重叠，单体中位值逐档增加；本样本没有跨两档反转。T3 扇面炮的密集多目标伤害可超过部分 T4/T5，但射程只有 105，必须贴近；T4 热流只有 85。T4 锯盘在静止目标出返双击中单体可高于 T5 轨道炮，但轨道炮具 420 射程、蓄力爆发和最多六目标贯穿，安全输出空间不同。T5 引力炮在当前三目标排列最高，代价是延迟爆炸和较小弹匣；Boss 免拉拽，不把该控场计算成 Boss 收益。火箭/导弹在本排列没有全体覆盖，表中保留实测结果，不按理论爆炸圈乘目标数。', '', '固定分档综合射程、安全距离、精度/散射、墙体阻挡、弹药/换弹、AoE、控场及 Boss 机制，而不是保证每种排列严格单调。所有枪每次完整换弹统一消耗一备用弹匣。追踪不穿墙、反弹有次数上限、裂片不递归。真人移动目标命中率与武器手感仍待第二次试玩。', '', '证据：tier-measured.json、tier-measured-execution.json；早期 tier-first/second/third/final 为诊断或旧采样方法，不能替代此最终表。']
(out/'tier-audit.md').write_text('\n'.join(lines)+'\n',encoding='utf-8')
encounters=[]; summary=[]
for version in ['m6','m7']:
    for build in ['basic','middle','late']:
        data=read(out.parent/version/f'audit-{build}.json'); rows=data['rows']
        entry=dict(version=version,build=build,encounters=len(rows),completed=sum(r['completed'] for r in rows),deaths=sum(r['dead'] for r in rows),flow_failures=data['failures'],damage_taken=sum(r['damage_taken'] for r in rows),mean_completed_seconds=statistics.mean(r['seconds'] for r in rows if r['completed']))
        if version=='m7':
            entry.update(normal_raw=sum(r['incoming_raw']-r['boss_raw'] for r in rows),normal_applied=sum(r['incoming_applied']-r['boss_applied'] for r in rows),boss_raw=sum(r['boss_raw'] for r in rows),boss_applied=sum(r['boss_applied'] for r in rows))
            for r in rows: encounters.append(dict(build=build,stage=r['stage'],weapon=r['weapon'],completed=r['completed'],dead=r['dead'],seconds=r['seconds'],damage_taken=r['damage_taken'],incoming_raw=r['incoming_raw'],incoming_applied=r['incoming_applied'],boss_raw=r['boss_raw'],boss_applied=r['boss_applied'],watchdog=r['watchdog'],remaining_enemies=r['remaining_enemies']))
        summary.append(entry)
write('encounter-comparison.json',summary)
with (out/'encounters-90.csv').open('w',encoding='utf-8-sig',newline='') as f:
    writer=csv.DictWriter(f,fieldnames=list(encounters[0])); writer.writeheader(); writer.writerows(encounters)
lines=['# M7 默认压力审核','', '相同 30 遭遇、三档代表配置、固定控制策略和种子，对照 M6 已记录的同一审核。M7 的 Tier 和通用配件本身改变输出；因此完成率/总受伤只能表示整体产品效果，不能单独证明敌方削弱幅度。', '', '|版本/配置|完成|死亡|总受伤|成功场次平均秒|流程失败|','|---|---:|---:|---:|---:|---:|']
for r in summary: lines.append(f"|{r['version']}/{r['build']}|{r['completed']}/30|{r['deaths']}|{r['damage_taken']:.3f}|{r['mean_completed_seconds']:.3f}|{r['flow_failures']}|")
normal_raw=sum(r.get('normal_raw',0) for r in summary); normal_applied=sum(r.get('normal_applied',0) for r in summary)
boss_raw=sum(r.get('boss_raw',0) for r in summary); boss_applied=sum(r.get('boss_applied',0) for r in summary)
lines += ['', f'实际受击链观测：普通敌人防御后原始 {normal_raw:.3f} → 应用 {normal_applied:.3f}，比值 {normal_applied/normal_raw:.6f}；Boss {boss_raw:.3f} → {boss_applied:.3f}，比值 {boss_applied/boss_raw:.6f}。分别为明确的 12.5% 和 3% 下调；不增加 HP，不改敌人数量、遭遇时限或玩家血量。Boss 召唤的普通单位按普通伤害系数。', '', '完成 82/90 → 87/90，死亡 8 → 3；M7 仍有死亡，未把挑战消除。总受伤不是逐档必降：后期配置死亡更少、存活更久，也可能承受更多累计伤害。定时生存遭遇时间主要由固定时限决定，平均通关时间混合了生存场与 Boss 场，不等价于击杀速度。', '', '所有 90 行见 encounters-90.csv；原始 JSON 包含敌方构成、Boss 用时、清理数量、无伤害时段与 watchdog。三个 execution 文件均要求 code=0/source_unchanged=true。真人压力、走位与可反应性仍需第二次试玩。']
(out/'difficulty-audit.md').write_text('\n'.join(lines)+'\n',encoding='utf-8')
print('Wrote 24 weapon rows and 90 encounter rows.')
