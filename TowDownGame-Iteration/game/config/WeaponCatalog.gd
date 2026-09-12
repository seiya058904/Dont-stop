extends RefCounted
class_name WeaponCatalog

# Plan IDs are stable metadata; runtime/save IDs append in the 100 namespace.
const DEFINITIONS = {
	117:{"plan":"W17","name":"反弹重弹枪","mode":"ricochet","tags":["projectile","ricochet","straight"],"damage":4.0,"rate":2.0,"magazine":10,"reload":1.4,"speed":150,"bounces":2,"info":"重弹最多反弹2次；墙角接触结束，寿命2秒；直接命中冲击。"},
	118:{"plan":"W18","name":"裂片发射器","mode":"shard","tags":["projectile","split","straight"],"damage":3.5,"rate":2.5,"magazine":12,"reload":1.4,"speed":160,"shards":3,"info":"母弹首次命中产生3枚前向裂片，各为母弹35%伤害；裂片不再分裂。"},
	119:{"plan":"W19","name":"散射火箭炮","mode":"rocket","tags":["projectile","explosive","spread"],"damage":3.0,"rate":1.4,"magazine":9,"reload":1.8,"speed":110,"count":3,"fan":0.28,"radius":24.0,"info":"每次耗1发，扇形射出3枚火箭；每枚半径24独立爆炸，各目标每枚至多一次。"},
	120:{"plan":"W20","name":"微型追踪导弹","mode":"missile","tags":["projectile","explosive","homing"],"damage":2.8,"rate":1.8,"magazine":12,"reload":1.5,"speed":130,"count":2,"fan":0.12,"radius":22.0,"turn":2.2,"lock_angle":0.65,"info":"每次耗1发射2枚；前方视角内锁定，有限转向；目标消失保持前向，不穿墙。"}
}

static func definition(id: int) -> Dictionary:
	return DEFINITIONS.get(id,{})
