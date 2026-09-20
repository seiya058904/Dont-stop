extends RefCounted
class_name AttachmentCatalog
## B13 rework: the 24 one-shot global upgrades are now graded 普通/稀有/传说.
##
## Invariants this file must keep (B13 spec):
##   * IDs 0-9 / 110-124 are stable: they are the save's ownership keys, so no renumbering.
##   * Every upgrade stays one-shot, permanent, global, no slots, no exclusivity, and applies
##     to every current and future weapon through EffectiveStats.
##   * Every entry carries a universal primary effect, so no purchase can be dead weight on
##     most of the roster; weapon-specific mechanisms (bounce/chain/homing/radius) ride on top.
##   * Names describe the actual effect in all-weapon language - never a part name
##     (枪口/枪托/弹芯) or a weapon-type name (步枪/霰弹枪) for a global upgrade.
##   * Quality bands do not overlap: 普通 280-520 < 稀有 720-1250 < 传说 1450-2000.
const QUALITY_NAMES = ["普通","稀有","传说"]
const PRICES = {0:320,1:280,2:850,3:720,9:2000,5:520,6:500,7:470,8:1250,110:480,111:880,112:780,113:900,114:440,115:460,116:420,117:820,118:1080,119:900,120:1600,121:1050,122:1100,123:900,124:1900}
## Quality is the value grade of the upgrade itself, not a route: a player owns and benefits
## from 普通/稀有/传说 upgrades at the same time. 1=普通 2=稀有 3=传说.
const QUALITY = {0:1,1:1,5:1,6:1,7:1,110:1,114:1,115:1,116:1,2:2,3:2,8:2,111:2,112:2,113:2,117:2,118:2,121:2,9:3,119:2,120:3,122:2,123:2,124:3}
const DEFINITIONS = {
	0:{"name":"快速装填组件","reload_mul":0.8,"info":"所有武器装填时间-20%。"},
	1:{"name":"扩容供弹组件","magazine_mul":1.2,"info":"所有武器弹匣容量+20%。"},
	2:{"name":"高容量供弹系统","magazine_mul":1.45,"info":"所有武器弹匣容量+45%。"},
	3:{"name":"火力循环组件","damage":0.06,"reload_mul":0.85,"info":"所有武器伤害+6%，装填时间-15%。"},
	9:{"name":"联动爆破核心","damage":0.08,"info":"所有武器伤害+8%；真实命中自动爆破，公共冷却1.75秒、半径44。伤害为完整装填周期每秒输出的65%，限单发1至12倍；派生不递归。"},
	5:{"name":"轻量快装弹鼓","magazine_mul":1.15,"reload_mul":0.8,"info":"所有武器弹匣+15%，装填时间-20%。"},
	6:{"name":"效率弹链","magazine_mul":1.25,"reload_mul":0.9,"info":"所有武器弹匣+25%，装填时间-10%。"},
	7:{"name":"双排供弹模块","magazine_mul":1.3,"info":"所有武器弹匣容量+30%。"},
	8:{"name":"超容供弹鼓","magazine_mul":1.6,"info":"所有武器弹匣容量+60%。"},
	110:{"name":"精密瞄具","damage":0.02,"crit":0.08,"info":"所有武器暴击+8个百分点、伤害+2%。"},
	111:{"name":"焦距校准器","damage":0.06,"range_mul":1.25,"info":"所有武器伤害+6%、有效射程+25%。"},
	112:{"name":"稳定瞄准模块","damage":0.06,"spread_mul":0.75,"info":"所有武器伤害+6%；散布角-25%。"},
	113:{"name":"宽域扩束模块","damage_mul":1.08,"width_mul":1.35,"angle_mul":1.35,"info":"所有武器伤害+8%；棱镜/轨道束宽及扇面角+35%；原型激光不扩宽，不扩大爆炸半径。"},
	114:{"name":"强化枪管","damage":0.15,"reload_mul":1.1,"info":"所有武器伤害+15%；装填时间+10%。"},
	115:{"name":"冷却导管","reload_mul":0.85,"warmup_mul":0.9,"info":"所有武器装填时间-15%；有预热/蓄力时等待-10%。"},
	116:{"name":"稳定枪身组件","reload_mul":0.9,"recovery_mul":0.75,"info":"所有武器装填时间-10%；射击后回正动画时间-25%，不缩短实际射击间隔。"},
	117:{"name":"冲击载荷模块","damage":0.06,"impulse_mul":1.4,"info":"所有武器伤害+6%；对普通敌人击退+40%。"},
	118:{"name":"贯穿弹药包","damage":0.06,"pierce":1,"info":"所有武器伤害+6%；直射攻击额外贯穿1个目标。"},
	119:{"name":"墙面反弹核心","damage":0.08,"bounces":1,"bounce_retention":1.0,"info":"所有武器伤害+8%；反弹重弹枪多1次墙面反弹（最多4次），每次保留100%伤害；不增加锯盘返回次数。"},
	120:{"name":"裂变火力核心","damage":0.08,"shards":2,"shard_ratio":0.25,"info":"所有武器伤害+8%；直射实体弹首次命中追加2枚25%裂片，原生裂片保留35%，总数最多5枚、仅一代；能量/爆破/锯盘命中向前方至多2敌外溢，冷却0.4秒，范围100，伤害取命中35%与周期联动参考16%的较大值；墙阻挡、派生不递归。"},
	121:{"name":"扩爆引信","damage":0.08,"radius_mul":1.25,"info":"所有武器伤害+8%；爆炸半径+25%。"},
	122:{"name":"电弧传导核心","damage":0.08,"jumps":1,"info":"所有武器伤害+8%；链电武器多跳1个目标。"},
	123:{"name":"制导校准核心","damage":0.08,"turn_mul":1.3,"lock_mul":1.2,"info":"所有武器伤害+8%；追踪转向+30%、寻找角+20%。"},
	124:{"name":"击杀回填核心","damage":0.06,"refill":1,"cooldown":0.5,"info":"所有武器伤害+6%；武器原生击杀最多每0.5秒返还弹匣容量8%（向上取整，1至6发），不超容量；派生与假人不触发。"}
}

static func quality(id: int) -> int:
	return QUALITY.get(id,1)

static func quality_name(id: int) -> String:
	return QUALITY_NAMES[clampi(quality(id),1,3)-1]

## Single source of truth for player-visible upgrade names. The attachment scenes keep their
## legacy exports, but every shop/stat surface reads the catalog so a rename cannot drift.
static func display_name(id: int) -> String:
	return DEFINITIONS[id].get("name","")

static func compatible(_id: int, gun) -> bool:
	return is_instance_valid(gun) and gun.damage > 0 and gun.bullets_max_count > 0
