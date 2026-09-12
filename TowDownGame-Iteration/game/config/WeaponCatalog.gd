extends RefCounted
class_name WeaponCatalog

# Plan IDs are stable metadata; runtime/save IDs append in the 100 namespace.
const DEFINITIONS = {
	121:{"plan":"W21","name":"引力榴弹器","mode":"gravity","tags":["projectile","explosive","gravity"],"damage":5.0,"rate":1.2,"magazine":8,"reload":1.7,"speed":90,"radius":64.0,"info":"榴弹命中或飞行0.45秒后形成0.9秒聚拢场，再爆开；拉拽经碰撞检测且不隔墙，Boss免拉拽。"},
	122:{"plan":"W22","name":"回旋锯盘","mode":"disc","tags":["projectile","returning"],"damage":3.0,"rate":2.0,"magazine":12,"reload":1.3,"speed":180,"info":"锯盘0.55秒后返回角色；出/回各对同一目标最多一次。触墙提前回返，回程触墙结束，最长2秒。"},
	124:{"plan":"W24","name":"加速转管机枪","mode":"rotary","tags":["projectile","rotary","straight"],"damage":1.2,"rate":24.0,"magazine":100,"reload":2.0,"speed":220,"warmup":1.2,"max_rate":24.0,"info":"按住由每秒6发逐渐加速，1.2秒到每秒24发上限；松手转速回落，不降低角色移速。"},
	111:{"plan":"W11","name":"棱镜脉冲枪","mode":"prism","tags":["beam","energy","pulse"],"damage":2.2,"rate":2.4,"magazine":16,"reload":1.4,"speed":100,"range":280.0,"width":3.0,"info":"一次耗1发，3条轻微分叉束独立阻墙；同一目标可承受实际相交的多束。"},
	113:{"plan":"W13","name":"蓄能轨道炮","mode":"rail","tags":["beam","energy","charged","straight"],"damage":5.0,"rate":1.2,"magazine":6,"reload":1.8,"speed":100,"range":420.0,"width":2.0,"pierce":5,"charge":1.2,"info":"按住最多蓄力1.2秒，松开发射；轻点基础伤害，满蓄×2.5；最多6目标且实墙阻断。切枪取消。"},
	115:{"plan":"W15","name":"扇面脉冲炮","mode":"cone","tags":["pulse_cone","energy"],"damage":4.2,"rate":2.0,"magazine":12,"reload":1.5,"speed":100,"range":105.0,"angle":0.65,"info":"一次短程宽扇面冲击；半角37度、距离105，角度/距离/遮墙分别判定，每目标一次。"},
	116:{"plan":"W16","name":"热流喷射器","mode":"thermal","tags":["pulse_cone","energy","continuous"],"damage":0.7,"rate":10.0,"magazine":70,"reload":1.8,"speed":100,"range":85.0,"angle":0.4,"burn":0.35,"info":"按住近程喷流，每0.1秒tick消耗1发；目标灼烧1秒，每0.25秒0.35伤害，同来源刷新不叠无限层。"},
	117:{"plan":"W17","name":"反弹重弹枪","mode":"ricochet","tags":["projectile","ricochet","straight"],"damage":4.0,"rate":2.0,"magazine":10,"reload":1.4,"speed":150,"bounces":2,"info":"重弹最多反弹2次；墙角接触结束，寿命2秒；直接命中冲击。"},
	118:{"plan":"W18","name":"裂片发射器","mode":"shard","tags":["projectile","split","straight"],"damage":3.5,"rate":2.5,"magazine":12,"reload":1.4,"speed":160,"shards":3,"info":"母弹首次命中产生3枚前向裂片，各为母弹35%伤害；裂片不再分裂。"},
	119:{"plan":"W19","name":"散射火箭炮","mode":"rocket","tags":["projectile","explosive","spread"],"damage":3.0,"rate":1.4,"magazine":9,"reload":1.8,"speed":110,"count":3,"fan":0.28,"radius":24.0,"info":"每次耗1发，扇形射出3枚火箭；每枚半径24独立爆炸，各目标每枚至多一次。"},
	120:{"plan":"W20","name":"微型追踪导弹","mode":"missile","tags":["projectile","explosive","homing"],"damage":2.8,"rate":1.8,"magazine":12,"reload":1.5,"speed":130,"count":2,"fan":0.12,"radius":22.0,"turn":2.2,"lock_angle":0.65,"info":"每次耗1发射2枚；前方视角内锁定，有限转向；目标消失保持前向，不穿墙。"}
}

static func definition(id: int) -> Dictionary:
	return DEFINITIONS.get(id,{})

# Fixed progression, no random rarity. Multipliers are applied once in EffectiveStats.
const TIERS = {3:1,1:1,0:1,9:1,2:2,5:2,8:2,123:2,7:2,4:3,117:3,118:3,115:3,6:3,111:4,112:4,114:4,116:4,122:4,113:5,119:5,120:5,121:5,124:5}
const PRICES = {"3":60,"1":80,"0":100,"9":120,"2":260,"5":290,"8":320,"123":350,"7":380,"4":650,"117":700,"118":760,"115":800,"6":850,"111":1400,"112":1500,"114":1600,"116":1700,"122":1800,"113":2800,"119":3000,"120":3200,"121":3400,"124":3600}
const POWER = {3:1.4,1:1.0,0:1.0,9:1.0,2:1.4,5:1.2,8:1.6,123:1.7,7:1.1,4:1.35,117:2.5,118:2.0,115:2.3,6:1.7,111:1.9,112:3.6,114:4.2,116:3.0,122:3.0,113:4.8,119:4.0,120:3.4,121:4.5,124:1.9}
static func tier(id: int) -> int:
	return TIERS.get(id,1)
static func power(id: int) -> float:
	return POWER.get(id,1.0)
static func short_info(id: int) -> String:
	var basics = {0:"均衡的单发弹道，适合稳定压制。",1:"扇形弹丸覆盖近距离敌人。",2:"高单发伤害，适合中远距离点射。",3:"轻便连射，适合低成本起步。",4:"较高射速与伤害兼顾的主力步枪。",5:"近距离散射压制，多弹丸分别命中。",6:"远距离持续束流，实墙阻断。",7:"大弹匣机枪，适合持续火力。",8:"近距离五弹丸爆发，换弹频繁。",9:"高射速冲锋枪，快速倾泻小弹匣。"}
	if basics.has(id): return basics[id]
	var info = DemoConfig.weapon_info(id)
	return info.split("。")[0].split("；")[0].split("\n")[0]+"。"
static func type_name(id: int) -> String:
	var tags = DemoConfig.weapon_tags(id)
	if "explosive" in tags: return "爆破"
	if "energy" in tags: return "能量"
	if "spread" in tags: return "散射"
	return "直射"

static func labels(id: int) -> Array:
	var names = {"projectile":"实体弹","straight":"直射","spread":"散射","energy":"能量","explosive":"爆炸","chain":"连锁电弧","beam":"束流","pulse":"多束脉冲","charged":"蓄力贯穿","pulse_cone":"扇面覆盖","continuous":"持续热流","ricochet":"墙面反弹","split":"命中裂片","homing":"有限追踪","returning":"出返双击","gravity":"聚拢控制","rotary":"加速连射","burst":"三发连射"}
	var result = []
	for tag in DemoConfig.weapon_tags(id): result.append(names.get(tag,tag))
	return result.slice(0,4)
