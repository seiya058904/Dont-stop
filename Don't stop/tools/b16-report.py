"""Generate the bounded B16 catalog review from current and pinned B15 source."""
import json
import re
import subprocess
from pathlib import Path

root = Path(__file__).resolve().parents[1]
out = root / 'docs/iteration'

def source(name, old=False):
    if old:
        return subprocess.check_output(['git', 'show', "69669f2:Don't stop/"+name], cwd=root, text=True, encoding='utf-8')
    return (root/name).read_text(encoding='utf-8')

def constant(text, name):
    raw = re.search(r'const '+name+r' = (\{[^\n]*\}|\{\n.*?\n\})', text, re.S)[1]
    raw = re.sub(r'(?<=[{,])\s*(\d+)\s*:', r'"\1":', raw)
    raw = re.sub(r',\s*}', '}', raw)
    return json.loads(raw)

upgrade_reasons = {
 '0':'20%装填缩减，低价且跨枪有效；0.15秒下限继续保留。',
 '1':'20%容量入门收益；取整可见，购买不补子弹。',
 '2':'45%容量比入门更大，稀有价格换更长开火周期。',
 '3':'伤害与装填复合，完整周期两端均有收益。',
 '5':'15%容量加20%快装，偏快装而非最大容量。',
 '6':'25%容量加10%快装，中间档持续性。',
 '7':'30%纯容量，低于稀有45%容量及60%超容。',
 '8':'60%容量保留装填需求；不在购买时补满弹。',
 '9':'右键门槛改真实命中自动爆破，公共1.75秒冷却；冻结周期参考，半径44。',
 '110':'暴击百分点与2%伤害叠加；100%封顶仍受真实预览约束。',
 '111':'射程与伤害；引力的实际收益是场半径，保留B15语义。',
 '112':'缩实体散布，提高定向密度；不缩热流/扇面主要角度。',
 '113':'束宽/扇角提升面积，原型激光仍不假扩宽；通用伤害8%。',
 '114':'显式15%伤害换10%较慢装填；即使全周期由装填主导仍有正比例收益。',
 '115':'真实装填和蓄力/暖机缩短；没有暖机的枪仍获装填收益。',
 '116':'普通10%快装；回正只标动画，不冒充实际射速。',
 '117':'普通怪击退加40%与6%伤害；Boss仍免推移。',
 '118':'直射多一目标、总数封顶；其余枪有6%伤害，非传说定价。',
 '119':'反弹保留100%而非负收益；锯盘返回仍不算反弹。',
 '120':'实体沿用有限裂片；其他家族增加向前2敌能量外溢，0.4秒共享冷却。',
 '121':'半径25%对应无遮挡面积56.25%提升；墙裁剪不变。',
 '122':'在10目标电弧基础上多1目标；通用8%伤害，保留稀有定位。',
 '123':'六枚导弹的转向/寻找角收益，已有目标分配不变。',
 '124':'每0.5秒原生击杀回填容量8%，上取整1至6发，受当前容量限制。',
}
talent_reasons = {
 'T01':'基础15%每级线性增伤，结算顺序不改。','T02':'射速收益由现有热流/封顶转管转伤害规则兑现。',
 'T03':'每级8%装填缩减，保留最低装填时间。','T04':'18%每级容量，保持取整及购买不补弹。',
 'T05':'每级10%有效射程，实体寿命和引力半径已有实路径。','T06':'每级6个百分点，暴击上限100%。',
 'T07':'每级最大生命+1，购买只补该增量；历史头盔不重复。','T08':'每级基础移动+3%，冲刺保持，旧蓝靴来源分离。',
 'T09':'20→32的小范围即时收取改120/180/240真实飞行；金币与医疗独立。',
 'T10':'击杀叠层最多5层、4秒；热流/转管已有真实收益，不重做。',
 'T11':'原生电弧/原生裂片也计有效击杀；每5杀补等级个备用弹匣，不填当前枪。',
 'T12':'25/40/55%首发增伤，真实补弹激活，共享齐射快照。',
 'T13':'真实额外2目标，最多8；不兼容项明示，已有贯穿事件证据。',
 'T14':'25%概率、50%实伤、0.5秒、80距离，一个不同目标；与暴击回响触发不同。',
 'T15':'灼烧下限0.3×等级；随单发2%×等级成长，上限0.6×等级，单来源刷新。',
 'T16':'原生武器击杀爆破；max(2.6,min(12,攻击伤害×0.25))，半径40、0.4秒、不递归。',
 'T17':'8/16/24%减速、1.5秒，Boss四分之一；控制价值而非纯DPS。',
 'T18':'每级15%普通怪击退，Boss免推移，保持基础定位。',
 'T19':'单盾基础6秒恢复；每原生击杀减0.35秒，破盾后至少2秒，不能叠层。',
 'T20':'胜利恢复最大生命10/20/30%；回营/选关不冒充胜利。',
 'T21':'15/25/35%仅精英，Boss不适用；低精英密度是明确适用限制。',
 'T22':'100距离至少3活敌，每0.2秒观察；冻结到发射快照，电弧收益不回退。',
 'T23':'暴击驱动40%扩散；85距离、0.15秒、不同目标；菱形回响区别于链电线。',
 'T24':'原生分支击杀可回血；0.2×等级、0.5秒，满血不播虚假治疗。',
}
u = source('game/config/AttachmentCatalog.gd')
t = source('game/config/DemoConfig.gd')
ud, uq, up = (constant(u, n) for n in ['DEFINITIONS','QUALITY','PRICES'])
td,tq,tg,tp = (constant(t,n) for n in ['TALENTS','TALENT_QUALITY','TALENT_GOLD_PRICES','TALENT_POINT_PRICES'])
qualities=['普通','稀有','传说']
lines=['# B16 成长目录审阅（24强化 + 24天赋）','',
 '稳定ID、已有所有权、等级和历史付款保留；新规则自动应用于旧拥有项，不补扣，不按新价重算退款。',
 '表中 KEEP 是本轮保留决定，不代表每个项目已做独立真人实战验收。目录/属性由 B13Catalog、B13UpgradeEffects、B13TalentEffects 检查；真实组合由 B16CombatMix、B14Growth、M4Talents 检查。',
 'T09另有12项拾取测试及80项历史支付/等级恢复检查。所有性能及人工验收边界见主报告。','',
 '|ID|处理|名称 / 品质|等级 / 金币 / 点数|实际参数|收益、兼容、边界与理由|',
 '|---|---|---|---|---|---|']
for key,d in sorted(ud.items(),key=lambda x:int(x[0])):
    state='REDESIGN' if key in ['9','120'] else ('TUNE' if key=='124' else 'KEEP')
    params={k:v for k,v in d.items() if k not in ['name','info']}
    lines.append(f'|A{key}|{state}|{d["name"]} / {qualities[uq[key]-1]}|一次性 / {up[key]} / —|`{json.dumps(params,ensure_ascii=False)}`|{upgrade_reasons[key]}|')
for key,d in sorted(td.items()):
    q=tq[key]; count=d['max']
    def ladder(kind,fallback):
        a=d.get(kind,fallback[str(q)])
        return '/'.join(str(a[min(i,len(a)-1)]) for i in range(count))
    state='REDESIGN' if key=='T09' else ('TUNE' if key in ['T11','T15','T16','T19','T23','T24'] else 'KEEP')
    params={k:v for k,v in d.items() if k not in ['name','info','unit','max','gold_prices','point_prices']}
    lines.append(f'|{key}|{state}|{d["name"]} / {qualities[q-1]}|{count}级 / {ladder("gold_prices",tg)} / {ladder("point_prices",tp)}|`{json.dumps(params,ensure_ascii=False)}`|{talent_reasons[key]}|')
lines+=['','伤害/装填/容量等被动参数在 `EffectiveStats.calculate` 结算；条件事件在 `Combat.hit` / `Demo.on_kill` 结算。资源资格与递归深度分开：原生电弧/原生3裂片可获资源，强化追加裂片、成长爆破、灼烧和回响不可递归获益。',
 'A9：冻结单枪周期参考 `damage × projectile_count × magazine / (magazine/rate + reload) × 0.65`，夹在单发1–12倍；这是设计参考，不是宣称精确实测DPS。A120非直射实体路径取 `max(hit_damage×0.35,link_reference×0.16)`，向前100距离最多2敌。',
 '旧T09金币150/250/350、点数1/1/2的付款原样退款；新金币700/1000/1400、点数3/4/5。旧rank 0/1/2/3不降级。']
(out/'b16-growth-matrix.md').write_text('\n'.join(lines)+'\n',encoding='utf-8')

prices=constant(source('game/config/WeaponCatalog.gd'),'PRICES')
old_prices=constant(source('game/config/WeaponCatalog.gd',True),'PRICES')
names=['冲击波步枪','冲击波霰弹枪','轻型狙击枪','Baby冲锋枪','异形者步枪','帝国霰弹枪','BoomBoi','异形者机枪','RebalShotgun','Uzi']
defs=constant(source('game/config/WeaponCatalog.gd'),'DEFINITIONS')
names_by_id={str(i):name for i,name in enumerate(names)}
names_by_id.update({key:d['name'] for key,d in defs.items()})
names_by_id.update({'112':'跃迁电弧枪','114':'等离子榴炮','123':'三连发卡宾'})
reasons={ '0':'均衡低价直射','1':'最低价近距散射','2':'精良高单发','3':'普通快射入门','4':'稀有持续步枪','5':'精良散射升级','6':'独立持续激光；传说入门','7':'精良大弹匣','8':'普通多弹爆发','9':'普通高射速',
 '111':'三轻束覆盖','112':'用户指定清怪首选、最高价；3根10目标不削弱','113':'三重束蓄力贯穿','114':'48半径爆破','115':'短程宽扇面','116':'持续热流和灼烧','117':'高单发反弹','118':'原生有限裂片','119':'三枚扇形火箭','120':'六枚分配制导','121':'碰撞成场控制价值','122':'出返各一次切割','123':'精良三连发','124':'高射速大弹匣、暖机成本'}
lines=['# B16 全24枪定价复核','', '仅电弧3000→4200，确保最高标价；其余23枪 KEEP，保留B15认可的机制、品质与伤害。价格是产品决策，非将出生限速下的击杀率精确倒算。高价候选额外单靶完整周期和固定怪群参考见本轮日志；控制/覆盖价值不等于单靶DPS。','', '|ID|武器|旧→新金币|决定与理由|','|---|---|---|---|']
for key in sorted(prices,key=int):
    lines.append(f'|{key}|{names_by_id[key]}|{old_prices[key]} → {prices[key]}|{"TUNE" if old_prices[key]!=prices[key] else "KEEP"}：{reasons[key]}|')
(out/'b16-prices.md').write_text('\n'.join(lines)+'\n',encoding='utf-8')
print('Wrote 48 growth rows and 24 weapon price rows.')
