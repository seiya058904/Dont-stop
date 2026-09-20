# B17 三源登记与证据边界

72 项来自当前运行注册表。被动属性、真实发射和资源事件是不同证据；下表不把尚未覆盖的生命周期组合标成 PASS。

|来源|ID|名称|购买上限|规则 / 条件|实现|
|---|---|---|---|---|---|
|reward|12|火核 Ember Core|4|直接命中10/13/16/19%附加1秒灼烧，总伤害为本次50%；同源刷新，不递归。|res://game/reward/Reward12.tscn|
|reward|13|霜镜 Frost Lens|4|直接命中10/14/18/22%减速20%持续1秒；Boss效果四分之一，与低温天赋相加上限40%。|res://game/reward/Reward13.tscn|
|reward|14|猎手徽记 Hunter Seal|4|对精英及Boss，每层独立伤害+5%。|res://game/reward/Reward14.tscn|
|reward|15|脉冲电容 Pulse Capacitor|3|每第7/6/5次直接命中，该次伤害+35%。|res://game/reward/Reward15.tscn|
|reward|16|裂光棱镜 Split Prism|3|直接暴击15/20/25%放出两枚各12.5%伤害实体裂片；墙阻挡，短距飞行，仅一代。|res://game/reward/Reward16.tscn|
|reward|17|反应装甲 Reactive Plating|3|受伤后，下一次普通攻击伤害-20%；激活冷却6/5/4秒，不减百分比大招。|res://game/reward/Reward17.tscn|
|reward|18|再生凝胶 Recovery Gel|3|每12/10/8次直接击杀恢复0.5HP；派生和假人不计。|res://game/reward/Reward18.tscn|
|reward|19|应急电池 Emergency Cell|3|受伤后生命低于30%且存活，恢复1/1.5/2HP；冷却20秒。|res://game/reward/Reward19.tscn|
|reward|20|冲量弹簧 Impact Spring|4|对普通敌人击退每层+15%，与天赋及强化普通百分比相加；Boss免推。|res://game/reward/Reward20.tscn|
|reward|21|余弹卡扣 Magazine Latch|3|每15/12/10次直接击杀获得1个备用弹匣；不填当前弹匣。|res://game/reward/Reward21.tscn|
|reward|22|动量环 Momentum Ring|3|连续移动2秒后移速及射速每层+3%；停止即消失。|res://game/reward/Reward22.tscn|
|reward|23|拾荒磁环 Scavenger Magnet|3|金币和回血拾取范围每层+40%；与天赋相加，隔墙无效，金币价值不变。|res://game/reward/Reward23.tscn|
|reward|0|小型钱袋|99|获得10枚金币|res://game/reward/GoldReward.tscn|
|reward|1|医疗箱|99|回复满你的血量|res://game/reward/HpReward.tscn|
|reward|2|异形头盔|4|获得及叠层时最大生命+3；最多前4层提供效果，旧存档计数和历史生命保留。|res://game/reward/AlienHelmentReward.tscn|
|reward|3|警示盾牌|4|15%/层概率抵消少量伤害；概率最高60%，减伤量按最多4层计算。|res://game/reward/WarningShield.tscn|
|reward|4|蓝色巨斧|10|直接命中每层10%概率伤害翻倍，概率最高100%；保留蓝斧特色。|res://game/reward/BlueAxe.tscn|
|reward|5|蓝色跑靴|6|基础移动速度每层+5，效果最多6层；与天赋及动量环相加。|res://game/reward/BlueBoots.tscn|
|reward|6|琥珀之星|6|同目标每3次直接命中造成5×层数附加伤害，效果最多6层；附伤不递归。|res://game/reward/AmberStar.tscn|
|reward|7|医疗包|3|直接击杀20%掉落回血包，回复量最多3HP；不触发派生击杀。|res://game/reward/HeathPack.tscn|
|reward|8|琥珀镰刀|5|1秒内直接击杀3敌，射速+20个百分点，持续层数+1秒（最多6秒），不重复叠加；保存剩余时间。|res://game/reward/AmberSickle.tscn|
|reward|9|电池|3|每3秒充能，下一次直接命中伤害+50%×层数，效果最多3层；保存充能状态。|res://game/reward/Battery.tscn|
|reward|10|蓝色细菌|1|前100次直接击杀每次最大生命+0.1；旧存档击杀计数及历史生命保留。|res://game/reward/BlueBacteria.tscn|
|reward|11|蓝色电路|4|直接命中20%概率额外造成25%×层数伤害，效果最多4层；派生不再触发。|res://game/reward/BlueCircuit.tscn|
|upgrade|0|快速装填组件|1|所有武器装填时间-20%。|res://game/config/AttachmentCatalog.gd|
|upgrade|1|扩容供弹组件|1|所有武器弹匣容量+20%。|res://game/config/AttachmentCatalog.gd|
|upgrade|2|高容量供弹系统|1|所有武器弹匣容量+45%。|res://game/config/AttachmentCatalog.gd|
|upgrade|3|火力循环组件|1|所有武器伤害+6%，装填时间-15%。|res://game/config/AttachmentCatalog.gd|
|upgrade|9|联动爆破核心|1|所有武器伤害+8%；真实命中自动爆破，公共冷却1.75秒、半径44。伤害为完整装填周期每秒输出的65%，限单发1至12倍；派生不递归。|res://game/config/AttachmentCatalog.gd|
|upgrade|5|轻量快装弹鼓|1|所有武器弹匣+15%，装填时间-20%。|res://game/config/AttachmentCatalog.gd|
|upgrade|6|效率弹链|1|所有武器弹匣+25%，装填时间-10%。|res://game/config/AttachmentCatalog.gd|
|upgrade|7|双排供弹模块|1|所有武器弹匣容量+30%。|res://game/config/AttachmentCatalog.gd|
|upgrade|8|超容供弹鼓|1|所有武器弹匣容量+60%。|res://game/config/AttachmentCatalog.gd|
|upgrade|110|精密瞄具|1|所有武器暴击+8个百分点、伤害+2%。|res://game/config/AttachmentCatalog.gd|
|upgrade|111|焦距校准器|1|所有武器伤害+6%、有效射程+25%。|res://game/config/AttachmentCatalog.gd|
|upgrade|112|稳定瞄准模块|1|所有武器伤害+6%；散布角-25%。|res://game/config/AttachmentCatalog.gd|
|upgrade|113|宽域扩束模块|1|所有武器伤害+8%；棱镜/轨道束宽及扇面角+35%；原型激光不扩宽，不扩大爆炸半径。|res://game/config/AttachmentCatalog.gd|
|upgrade|114|强化枪管|1|所有武器伤害+15%；装填时间+10%。|res://game/config/AttachmentCatalog.gd|
|upgrade|115|冷却导管|1|所有武器装填时间-15%；有预热/蓄力时等待-10%。|res://game/config/AttachmentCatalog.gd|
|upgrade|116|稳定枪身组件|1|所有武器装填时间-10%；射击后回正动画时间-25%，不缩短实际射击间隔。|res://game/config/AttachmentCatalog.gd|
|upgrade|117|冲击载荷模块|1|所有武器伤害+6%；对普通敌人击退+40%。|res://game/config/AttachmentCatalog.gd|
|upgrade|118|贯穿弹药包|1|所有武器伤害+6%；直射攻击额外贯穿1个目标。|res://game/config/AttachmentCatalog.gd|
|upgrade|119|墙面反弹核心|1|所有武器伤害+8%；反弹重弹枪多1次墙面反弹（最多4次），每次保留100%伤害；不增加锯盘返回次数。|res://game/config/AttachmentCatalog.gd|
|upgrade|120|裂变火力核心|1|所有武器伤害+8%；直射实体弹首次命中追加2枚25%裂片，原生裂片保留35%，总数最多5枚、仅一代；能量/爆破/锯盘命中向前方至多2敌外溢，冷却0.4秒，范围100，伤害取命中35%与周期联动参考16%的较大值；墙阻挡、派生不递归。|res://game/config/AttachmentCatalog.gd|
|upgrade|121|扩爆引信|1|所有武器伤害+8%；爆炸半径+25%。|res://game/config/AttachmentCatalog.gd|
|upgrade|122|电弧传导核心|1|所有武器伤害+8%；链电武器多跳1个目标。|res://game/config/AttachmentCatalog.gd|
|upgrade|123|制导校准核心|1|所有武器伤害+8%；追踪转向+30%、寻找角+20%。|res://game/config/AttachmentCatalog.gd|
|upgrade|124|击杀回填核心|1|所有武器伤害+6%；武器原生击杀最多每0.5秒返还弹匣容量8%（向上取整，1至6发），不超容量；派生与假人不触发。|res://game/config/AttachmentCatalog.gd|
|talent|T02|快速循环|3|每级射速+10%；热流转为每tick伤害，转管超过24发/秒的部分转单发伤害；原激光提升脉冲频率，轨道炮只缩短发射后冷却。|res://game/config/DemoConfig.gd|
|talent|T05|弹道延展|3|每级有效射程/实体弹寿命+10%；墙仍阻断。|res://game/config/DemoConfig.gd|
|talent|T06|弱点识别|3|每级暴击率+6个百分点；每次命中只采样一次，暴击×1.5。|res://game/config/DemoConfig.gd|
|talent|T07|生存余量|3|每级最大生命+1（初始基础5的20%），购买补该增量；旧头盔生命增量作为历史来源保留。|res://game/config/DemoConfig.gd|
|talent|T08|轻装移动|3|每级基础移速+3%；不改变冲刺。旧蓝靴来源保留，详情另列。|res://game/config/DemoConfig.gd|
|talent|T09|强磁回收|3|金币在120/180/240范围内加速飞来，到达才入账；墙阻挡，暂停停止。医疗包独立判定，满血不消耗。|res://game/config/DemoConfig.gd|
|talent|T11|弹药回流|3|每5次有效武器击杀补1×等级备用弹匣；假人、派生击杀不计，不填弹匣。|res://game/config/DemoConfig.gd|
|talent|T12|首发重击|3|完成实际补弹后的第一发伤害+25/40/55%；同次同时发射的弹丸共享，不含后续连发。取消装填不触发。|res://game/config/DemoConfig.gd|
|talent|T13|贯穿专精|1|明确兼容的直射攻击+2贯穿；总目标最多8，实墙阻断，不影响爆炸/跟踪/锯盘。轨道炮按蓄力比例兑现；已达上限时不继续增加。|res://game/config/DemoConfig.gd|
|talent|T14|静电跃迁|1|直接命中25%概率电弧到附近一个不同目标，50%命中伤害；冷却0.5秒，墙阻挡；派生不触发。|res://game/config/DemoConfig.gd|
|talent|T15|灼热弹道|3|直接命中施加1.5秒灼烧，每0.25秒至少伤害0.3×等级，随发射时单发伤害的2%×等级成长，上限0.6×等级；同来源刷新，一条计时记录。|res://game/config/DemoConfig.gd|
|talent|T17|低温冲击|3|直接命中减速8%×等级，1.5秒；最高24%，Boss仅四分之一，不叠无限层。|res://game/config/DemoConfig.gd|
|talent|T18|冲击放大|3|普通敌人冲量每级+15%；Boss免推移。|res://game/config/DemoConfig.gd|
|talent|T19|应急护盾|1|战斗抵消一次正伤害，基础恢复6秒；有效原生击杀缩短0.35秒，破盾后至少2秒才可恢复；只有一层。|res://game/config/DemoConfig.gd|
|talent|T20|战后修复|3|有效遭遇胜利回复最大生命10%×等级；手动回营、选关和重复结算不触发。|res://game/config/DemoConfig.gd|
|talent|T21|精英猎手|3|对精英目标伤害+15/25/35%；Boss不适用。精英按关卡计划与存活预算出现，并非所有特殊怪都是精英。|res://game/config/DemoConfig.gd|
|talent|T22|密集火网|3|100范围内至少3名存活敌人时伤害+8%×等级；每0.2秒更新，发射快照保留该次状态。|res://game/config/DemoConfig.gd|
|talent|T23|暴击回响|1|直接暴击向附近一个不同目标回响40%该次伤害，冷却0.15秒；墙阻挡，回响不暴击、不递归。|res://game/config/DemoConfig.gd|
|talent|T01|火力强化|3|{'max': 3, 'name': '火力强化', 'step': 0.15}|res://game/config/DemoConfig.gd|
|talent|T03|熟练装填|3|{'max': 3, 'name': '熟练装填', 'step': 0.08}|res://game/config/DemoConfig.gd|
|talent|T04|扩充弹匣|3|{'max': 3, 'name': '扩充弹匣', 'step': 0.18}|res://game/config/DemoConfig.gd|
|talent|T10|连杀加速|3|{'max': 3, 'name': '连杀加速', 'seconds': 4.0, 'stacks': 5, 'step': 0.04}|res://game/config/DemoConfig.gd|
|talent|T16|连锁爆破|1|{'cooldown': 0.4, 'damage': 2.6, 'max': 1, 'name': '连锁爆破', 'radius': 40.0}|res://game/config/DemoConfig.gd|
|talent|T24|吸能修复|3|{'cooldown': 0.5, 'max': 3, 'name': '吸能修复', 'step': 0.2}|res://game/config/DemoConfig.gd|

真实数据：独立 HP 与交易见 sources.json；原型直接事件见 reward-matrix.json；24 枪三源实发、资源与生命周期检查见 test-log-index.json。

原生 depth=1 分支保留原型“直接命中/直接击杀”文案限制；强化和天赋的 native_attack 资格独立，不把 depth 归零。

saved 计算已隔离 live 基础字段、击杀层数和原型状态；B17Saved 使用真实校验/加载路径检验独立性和历史超限持有。旧 schema 未保存的 base_* 字段按历史默认零，不从当前角色推断。

旧档超限计数保留；新购买以效果上限拒绝。概率/条件效果不作为常驻伤害相加；同组百分比相加，独立倍率相乘，暴击是百分点，射频、装填秒数和每 tick 伤害分别记录。
