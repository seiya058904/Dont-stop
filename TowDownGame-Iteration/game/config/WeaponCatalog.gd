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
