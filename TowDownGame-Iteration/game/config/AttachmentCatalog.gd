extends RefCounted
class_name AttachmentCatalog
const DEFINITIONS = {
	110:{"name":"精准瞄具","slot":"WEAPON_OPTICS","crit":0.08,"info":"非持续攻击暴击率+8个百分点；持续tick不兼容。"},
	111:{"name":"束流聚焦镜","slot":"WEAPON_OPTICS","range_mul":1.2,"width_mul":0.85,"info":"束流射程+20%、束宽-15%；聚焦后的判定同步变窄。"},
	112:{"name":"补偿枪口","slot":"WEAPON_MUZZLE","spread_mul":0.75,"info":"有散布的实体枪散布角-25%，不改变移动。"},
	113:{"name":"棱镜扩散器","slot":"WEAPON_MUZZLE","width_mul":1.35,"angle_mul":1.35,"damage_mul":0.9,"info":"束宽/扇宽+35%，每束/每tick伤害-10%，实际判定同步。"},
	114:{"name":"过载枪管","slot":"WEAPON_BARREL","damage":0.15,"reload_mul":1.1,"info":"武器伤害+15%，装填时间+10%。"},
	115:{"name":"能量散热器","slot":"WEAPON_BARREL","reload_mul":0.85,"warmup_mul":0.9,"info":"能量/转管装填时间-15%；仅有蓄力/预热者等待-10%。"},
	116:{"name":"抑震枪托","slot":"WEAPON_STOCK","recovery_mul":0.8,"info":"局部枪体形变/反冲回正时间-20%；不改变屏幕震动设置，不虚构命中率。"},
	117:{"name":"冲量支架","slot":"WEAPON_UNDERBARREL","impulse_mul":1.35,"info":"支持冲量的攻击对普通敌人击退+35%；Boss不受推移。"},
	118:{"name":"贯穿弹芯","slot":"WEAPON_AMMUNITION","pierce":1,"info":"兼容直射实体或轨道炮额外贯穿1目标；总目标数有上限，实墙阻断。"},
	119:{"name":"反弹弹壳","slot":"WEAPON_AMMUNITION","bounces":1,"bounce_retention":0.85,"info":"支持反弹的实体弹+1次反弹，反弹后保留85%伤害；最多4次。"},
	120:{"name":"裂片弹头","slot":"WEAPON_AMMUNITION","shards":2,"shard_ratio":0.25,"info":"常规非分裂直射实体首次命中生成2枚25%伤害裂片；不可再次裂片。"},
	121:{"name":"扩爆引信","slot":"WEAPON_AMMUNITION","radius_mul":1.2,"info":"爆炸半径+20%，效果圈同步。"},
	122:{"name":"电弧中继","slot":"WEAPON_TACTICAL","jumps":1,"info":"链式武器额外后跳1目标，不把普通枪变链电。"},
	123:{"name":"制导模块","slot":"WEAPON_TACTICAL","turn_mul":1.25,"lock_mul":1.15,"info":"追踪转向速率+25%，寻找半角+15%；仍有限转向且不能穿墙。"},
	124:{"name":"击杀回填器","slot":"WEAPON_PERKS","refill":1,"cooldown":0.2,"info":"此枪有效直接击杀最多每0.2秒向此枪弹匣返还1发，不超容量；派生与假人不触发。"}
}

static func compatible(id: int, gun) -> bool:
	if not is_instance_valid(gun) or gun.tags.is_empty(): return false
	var tags = gun.tags
	match id:
		110: return not "continuous" in tags and gun.weapon_id != 6
		111: return "beam" in tags and gun.weapon_id != 6
		112: return "spread" in tags
		113: return ("beam" in tags and gun.weapon_id != 6) or "pulse_cone" in tags
		114: return gun.damage > 0
		115: return "energy" in tags or "rotary" in tags
		116: return gun.weapon_id != 6 # Original laser uses its own feedback timeline.
		117: return "projectile" in tags or "beam" in tags or "pulse_cone" in tags
		118: return "straight" in tags
		119: return "ricochet" in tags
		120: return "straight" in tags and "projectile" in tags and not "split" in tags
		121: return "explosive" in tags
		122: return "chain" in tags
		123: return "homing" in tags
		124: return gun.bullets_max_count > 0
	return false
