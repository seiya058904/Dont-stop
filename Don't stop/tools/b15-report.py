"""Curate compact B15 evidence; raw frames/logs stay in the ignored evidence directory."""
import json
from pathlib import Path

root = Path(__file__).resolve().parents[1]
raw = root / 'evidence/visual-upgrade-20260919'
out = root / 'docs/iteration/evidence/b15'
out.mkdir(parents=True, exist_ok=True)

def read(name):
    return json.loads((raw / name).read_text(encoding='utf-8-sig'))

def stats(values):
    v = sorted(values)
    return {'n': len(v), 'mean': sum(v)/len(v), 'p95': v[int((len(v)-1)*.95)],
            'p99': v[int((len(v)-1)*.99)], 'max': v[-1]}

horde = read('b14-horde-b15-all.json')
thermal = read('b14-horde-b15-thermal-local.json')
horde = [r for r in horde if r['id'] != 116] + thermal
compact_horde = [{k:r[k] for k in ['id','build','seconds','kills','kills_per_s','reloads','reload_s','hp_damage','role_stats']} for r in horde]
stages = read('b15-stage-table.json')
milestones = read('b14-encounter-b15-milestones.json')
compact_milestones = [{k:r[k] for k in ['stage','weapon','seconds','completed','dead','live_peak','special_peak','ordinary_alive_time_fraction']} for r in milestones]
perf = {}
for tag in ['after','b15']:
    d = read(f'b14-fixed-perf-{tag}.json')
    rows = [r for r in d['rows'] if 15 <= r[0] <= 105]
    perf[tag] = {'renderer':d['renderer'],'window':[15,105],'emitted':d['zones_emitted'],
                 'frame':stats([r[1] for r in rows]), 'process_proxy':stats([r[2] for r in rows]),
                 'physics_proxy':stats([r[3] for r in rows])}
product = []
for tag in ['b15-product39','b15-product40','b15-product39-repeat']:
    r = read(f'b14-encounter-{tag}.json')[0]
    frames = [s for s in r['frame_samples'] if s[0] >= 5]
    product.append({'tag':tag,**{k:r[k] for k in ['stage','weapon','seconds','completed','dead','live_peak','special_peak']},
                    'window':'5 seconds to end; new product load, not fixed-load A/B',
                    'frame':stats([s[1] for s in frames]),'largest_samples':sorted(frames,key=lambda s:s[1],reverse=True)[:3]})
heavy = read('b15-heavy-targets.json')
summary = {'horde':compact_horde,'heavy_targets':heavy,'milestones':compact_milestones,'fixed_performance':perf,'product_performance':product,
           'limitations':['Historical three CPU proxy failures remain open','True per-frame CPU/GPU unavailable',
                          '39 product run has a 96ms long frame; attribution remains open',
                          'Initial thermal renderer failed triangulation; corrected local-coordinate rerun supersedes only its two rows',
                          'Moving horde uses durable observer; milestone runs use normal HP; neither is human acceptance'],
           'HUMAN_ACCEPTED':False}
(out/'summary.json').write_text(json.dumps(summary,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')

lines=['# B15：40关最终难度表','',
       '由最终运行时表和初始化后真实E01/E02实例导出。速率是基础生成间隔倒数；分批到达参数另列，不能当作实际接敌数。Boss节点单列。', '',
       '|关|E01 HP/速度|E02 HP/速度|基础生成/s|总上限|特殊/精英上限|批次/窗口秒|环境|',
       '|---|---|---|---|---|---|---|---|']
for r in stages:
    a,b=r['actual_instances']; h=r['horde']; boss=r.get('boss')
    special_cap=r.get('pressure',{}).get('special_cap','Boss召唤自身限额' if boss else '无特殊')
    lines.append(f"|{r['stage']}{' '+boss if boss else ''}|{a['hp']:.2f}/{a['speed']:.1f}|{b['hp']:.2f}/{b['speed']:.1f}|{1/r['interval']:.2f}|{r['cap']}|{special_cap}/{r.get('elite',{}).get('cap',0)}|{str(h.get('batch','—'))+'/'+str(h.get('window','—'))}|{','.join(r['hazards'].get('kinds',[])) or '无环境导演事件'}|")
lines += ['', '## 登场限制', '', 'E01/E02=1；E05=3；E04=4；轻精英=5；E03=6；E06=7；E11=11；E09=12；E10=13；E07=16；E08=17；E12=18；E13=31；E14=32；E15=33。共享生成入口也检查召唤/增援。', '',
          '## 实际18秒抽查', '', '|关|峰值存活|特殊峰值|普通存活时间占比|死亡|', '|---|---|---|---|---|']
for r in milestones:
    lines.append(f"|{r['stage']}|{r['live_peak']}|{r['special_peak']}|{r['ordinary_alive_time_fraction']:.1%}|{r['dead']}|")
lines += ['', '参考构筑：115，等级20，固定天赋/强化，正常HP自动移动。Boss占比不与普通关比较；18秒未死亡不等于通关。39关另以116完成全程，40关112观察47秒未清Boss。']
(root/'docs/iteration/b15-stage-table.md').write_text('\n'.join(lines)+'\n',encoding='utf-8')
print('wrote compact summary and 40-stage table')

catalog = read('b14-catalog-b15.json')['weapons']
art = {
    3:'保留轻便短枪和清楚枪口；普通起步枪',1:'保留短粗霰弹轮廓；近距离散射',
    0:'保留步枪比例与握把；均衡精良主力',9:'保留紧凑Uzi外形；短弹匣高射速',
    2:'保留长枪管与狙击轮廓；点射定位',5:'保留厚重霰弹结构；多弹丸近战',
    8:'保留五弹丸霰弹轮廓；换弹代价明确',123:'保留卡宾机身；三连发身份清楚',
    7:'保留大弹匣与长机身；持续火力',4:'保留已有异形结构；统一修正步枪译名',
    117:'保留反弹重弹身份；无需套传奇光环',118:'重画分节母弹枪口；尖锐母/子裂片分层',
    115:'保留已获认可宽口脉冲结构与冲击表现',6:'补机身能量轨、散热鳍及局部待机能量；保留强束流',
    111:'保留棱镜分叉结构与三脉冲身份',112:'重画成对电极/电容，局部待机电弧；多分支真实命中图',
    114:'重画等离子腔体；核心破裂、冲击层和命中热斑',116:'重画高温喷口/储热结构；持续热舌、前缘火花和热斑',
    122:'重画盘仓；齿盘旋转、出返双色盘芯、实际双程切割',113:'重画重型双侧导轨；三道独立加宽重束与热斑',
    119:'保留已修复的三火箭扇射与实战能力',120:'重画多发射口；六枚实体弹/目标分配/真实爆炸',
    121:'重画引力核心；飞行弹/聚拢场/爆开保持不同阶段',124:'重画多管与供弹，局部待机旋转；保留满转成长'
}
mechanics = {112:'单链3后跳/75% → 3根、10目标预算、140连接距、4.5次/s、90%逐跳且60%下限；修T12/T22',
             116:'射程85→108，半角0.40→0.45；保留10 tick/s、伤害和成长',
             113:'1次beam宽14→3次独立beam宽20；连续内部判定，无采样缝隙',
             120:'每次2→6枚，爆炸22→34；有限制导、分配多目标',
             121:'取消0.45秒成场和2秒飞行回收；碰撞一次成场；范围成长扩大场',
             122:'基础2→4次/s；弹匣12→24；伤害3、换弹1.3秒不减',
             114:'真实爆炸半径32→48；复用同一裁剪footprint判定与绘制',
             118:'保留真实3枚35%子裂片与派生上限；重做母弹/尖锐子弹视觉全过程'}
rarities=['普通','精良','稀有','史诗','传说']
lines=['# B15：24枪品质、能力与枪体复核','',
       '三束轨道炮与六枚导弹依据本轮实际输出升为传说，价格分别1800→3400、1750→3100；其余22把保留品质与价格，没有为了标签排序改隐藏伤害倍率。清怪场景有约6.6击杀/s的到达上限，不能仅凭饱和分数证明传说全面领先。原四把传说处于裸装清怪第一组；新两把的高HP靶输出突出，真实四Boss分阶段另查。最终手感仍待真人验收。','',
       '移动怪群：相同种子、固定E01/E02 HP和速度、10秒裸装/后期各一次；观察者高HP不代表生存通过。精英/Boss列为3.5秒实际发射的高HP静止BaseMonster标记靶DPS，不含真实Boss行为/装甲，也不是完整长程换弹测试。','',
       '|ID/武器|旧→新品质|旧→新价格|裸/后期击杀每秒|精英/Boss靶DPS|本轮机制与美术决定|',
       '|---|---|---|---|---|---|']
for w in catalog:
    wid=int(w['id']); tier=rarities[w['tier']-1]
    new_tier='传说' if wid in [113,120] else tier
    new_price={113:3400,120:3100}.get(wid,w['price'])
    h={r['build']:r['kills_per_s'] for r in horde if r['id']==wid}
    t={r['kind']:r['damage']/r['seconds'] for r in heavy if r['id']==wid}
    decision=mechanics.get(wid,'机制与数值保留')+'；'+art[wid]
    lines.append(f"|{wid} {w['name']}|{tier}→{new_tier}|{w['price']}→{new_price}|{h['bare']:.2f}/{h['late']:.2f}|{t['elite']:.2f}/{t['boss']:.2f}|{decision}|")
lines += ['', '重束/导弹的裸装移动清怪分别约4.6/4.1，低于原传说组约6.1–6.3，但高HP靶输出约164/108 DPS，明显高于原传说21–49，结合三束贯穿/六枚制导的覆盖和完整枪体身份升档。回旋锯盘70.7 DPS来自近距离出返双击，移动清怪约5.4且受回程路径影响，本轮保持史诗。各机制保留短程、蓄力、转向、回返代价，不把所有武器强行做成同射速。', '',
          '全部24枪使用真实资源记录静态图及8方向持枪；复核枪口、握把、翻转和轮廓。10把重点枪改SVG，其余14把保留已有清楚身份，不为了制造差距故意画丑普通枪。详见原始证据 b15-bodies-final/poses.json 与逐张图；小图合集只用于检索，不能替代动态片段。']
(root/'docs/iteration/b15-weapons.md').write_text('\n'.join(lines)+'\n',encoding='utf-8')
print('wrote 24-weapon review')
