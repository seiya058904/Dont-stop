extends RefCounted
class_name AttachmentCatalog
const DEFINITIONS = {
	0:{"reload_mul":0.8,"info":"所有武器换弹时间-20%。"},
	1:{"magazine_mul":1.2,"info":"所有武器弹匣容量+20%。"},
	2:{"magazine_mul":1.35,"info":"所有武器弹匣容量+35%。"},
	3:{"magazine_mul":1.2,"reload_mul":0.8,"info":"所有武器弹匣+20%，换弹时间-20%。"},
	9:{"damage":0.1,"info":"所有武器伤害+10%；右键发射榴弹，冷却2秒，伤害为当前武器35%。"},
	5:{"magazine_mul":1.15,"reload_mul":0.8,"info":"所有武器弹匣+15%，换弹时间-20%。"},
	6:{"magazine_mul":1.5,"info":"所有武器弹匣容量+50%。"},
	7:{"magazine_mul":1.3,"info":"所有武器弹匣容量+30%。"},
	8:{"magazine_mul":1.6,"info":"所有武器弹匣容量+60%。"},
	110:{"damage":0.05,"name":"精准瞄具","slot":"WEAPON_OPTICS","crit":0.08,"info":"伤害+5%、暴击+8个百分点。"},
	111:{"damage":0.08,"name":"束流聚焦镜","slot":"WEAPON_OPTICS","range_mul":1.2,"width_mul":0.85,"info":"伤害+8%、射程+20%；束流更聚焦。"},
	112:{"damage":0.08,"name":"补偿枪口","slot":"WEAPON_MUZZLE","spread_mul":0.75,"info":"伤害+8%；散布角-25%。"},
	113:{"damage_mul":1.1,"name":"棱镜扩散器","slot":"WEAPON_MUZZLE","width_mul":1.35,"angle_mul":1.35,"info":"伤害+10%；束宽/扇宽+35%。"},
	114:{"name":"过载枪管","slot":"WEAPON_BARREL","damage":0.15,"reload_mul":1.1,"info":"武器伤害+15%，装填时间+10%。"},
	115:{"reload_mul":0.85,"name":"能量散热器","slot":"WEAPON_BARREL","warmup_mul":0.9,"info":"换弹时间-15%；有预热/蓄力时等待-10%。"},
	116:{"reload_mul":0.9,"name":"抑震枪托","slot":"WEAPON_STOCK","recovery_mul":0.8,"info":"换弹时间-10%；局部回正时间-20%。"},
	117:{"damage":0.08,"name":"冲量支架","slot":"WEAPON_UNDERBARREL","impulse_mul":1.35,"info":"伤害+8%；对普通敌人击退+35%。"},
	118:{"damage":0.1,"name":"贯穿弹芯","slot":"WEAPON_AMMUNITION","pierce":1,"info":"伤害+10%；直射攻击额外贯穿1目标。"},
	119:{"damage":0.1,"name":"反弹弹壳","slot":"WEAPON_AMMUNITION","bounces":1,"bounce_retention":0.85,"info":"伤害+10%；反弹枪多1次反弹。"},
	120:{"damage":0.08,"name":"裂片弹头","slot":"WEAPON_AMMUNITION","shards":2,"shard_ratio":0.25,"info":"伤害+8%；实体直接命中产生有限裂片。"},
	121:{"damage":0.1,"name":"扩爆引信","slot":"WEAPON_AMMUNITION","radius_mul":1.2,"info":"伤害+10%；爆炸半径+20%。"},
	122:{"damage":0.1,"name":"电弧中继","slot":"WEAPON_TACTICAL","jumps":1,"info":"伤害+10%；链电多跳1个目标。"},
	123:{"damage":0.08,"name":"制导模块","slot":"WEAPON_TACTICAL","turn_mul":1.25,"lock_mul":1.15,"info":"伤害+8%；追踪转向+25%、寻找角+15%。"},
	124:{"name":"击杀回填器","slot":"WEAPON_PERKS","refill":1,"cooldown":0.2,"info":"此枪有效直接击杀最多每0.2秒向此枪弹匣返还1发，不超容量；派生与假人不触发。"}
}

static func compatible(_id: int, gun) -> bool:
	return is_instance_valid(gun) and gun.damage > 0 and gun.bullets_max_count > 0
