extends RefCounted
class_name EffectiveStats

static func calculate(gun, upgrades = null, saved: Dictionary = {}) -> Dictionary:
	if upgrades == null: upgrades = Demo.owned_global_upgrades if saved.is_empty() else saved.get("owned_global_upgrades",[])
	var b = gun.base_stats
	var ranks = Demo.talents if saved.is_empty() else saved.talents
	var level_damage = PlayerData.player_damage if saved.is_empty() else 0.3 * saved.level
	var magazine_mul = 1.0
	var reload_mul = 1.0
	var damage_percent = PlayerData.base_bullet_damage + DemoConfig.talent_value("T01",int(ranks.get("T01",0)))
	var crit = PlayerData.base_aim_enh * 0.01
	var spread = 1.0
	var impulse = 1.0+0.15*RewardServer.rank(20)
	var radius = 1.0
	var jumps = 3
	var spec = WeaponCatalog.definition(gun.weapon_id)
	var extras = {"range":spec.get("range",320.0),"width":spec.get("width",6.0),"angle":spec.get("angle",0.4),"pierce":spec.get("pierce",0),"bounces":spec.get("bounces",0),"shards":spec.get("shards",0),"shard_ratio":0.35,"bounce_retention":1.0,"turn":spec.get("turn",0.0),"lock_angle":spec.get("lock_angle",0.0),"warmup":spec.get("charge",spec.get("warmup",0.0)),"recovery":1.0,"refill":0}
	var damage_mul = 1.0
	crit += DemoConfig.talent_value("T06",int(ranks.get("T06",0)))
	impulse += DemoConfig.talent_value("T18",int(ranks.get("T18",0)))
	extras.range *= 1.0+DemoConfig.talent_value("T05",int(ranks.get("T05",0)))
	if gun.weapon_id == 6: extras.range *= 1000.0/320.0
	if "straight" in gun.tags: extras.pierce += int(ranks.get("T13",0))
	var cycle = 1.0+DemoConfig.talent_value("T02",int(ranks.get("T02",0)))+RewardServer.momentum()+PlayerData.player_fire_rate-1.0
	if "continuous" in gun.tags: damage_mul *= cycle
	var applied = {}
	for upgrade in upgrades:
		var id = int(upgrade) if upgrade is String or upgrade is StringName or upgrade is int else upgrade.am_id
		if AttachmentCatalog.DEFINITIONS.has(id) and not applied.has(id):
			applied[id] = true
			var d = AttachmentCatalog.DEFINITIONS[id]
			magazine_mul *= d.get("magazine_mul",1.0)
			crit += d.get("crit",0.0)
			damage_percent += d.get("damage",0.0)
			damage_mul *= d.get("damage_mul",1.0)
			reload_mul *= d.get("reload_mul",1.0)
			spread *= d.get("spread_mul",1.0)
			impulse += d.get("impulse_mul",1.0)-1.0
			radius *= d.get("radius_mul",1.0)
			jumps += d.get("jumps",0)
			for key in ["range","width","angle","turn"]: extras[key] *= d.get(key+"_mul",1.0)
			extras.lock_angle *= d.get("lock_mul",1.0)
			extras.warmup *= d.get("warmup_mul",1.0)
			extras.recovery *= d.get("recovery_mul",1.0)
			for key in ["pierce","bounces","shards","refill"]: extras[key] += d.get(key,0)
			for key in ["shard_ratio","bounce_retention"]:
				if d.has(key): extras[key] = d[key]

	var result = {
		"tags":gun.tags, "damage": (b.damage + level_damage) * WeaponCatalog.power(gun.weapon_id) * (1.0 + damage_percent)*damage_mul,
		"magazine": maxi(1, int((b.magazine * magazine_mul) * (1.0 + PlayerData.base_magazine_count + DemoConfig.talent_value("T04",int(ranks.get("T04",0)))))),
		"reload": maxf(DemoConfig.MIN_RELOAD_SECONDS, b.reload * maxf(0.1, 1.0 - PlayerData.base_reload_speed - DemoConfig.talent_value("T03",int(ranks.get("T03",0)))) * reload_mul),
		"rate": 10.0 if "continuous" in gun.tags else clampf(b.rate * cycle * (1.0 + Demo.kill_stacks * DemoConfig.talent_value("T10",int(ranks.get("T10",0)))), 0.1, 24.0 if "rotary" in gun.tags else 60.0),
		"crit": clampf(crit, 0.0, 1.0), "spread":spread,
		"impulse": b.impulse * impulse, "radius":WeaponCatalog.definition(gun.weapon_id).get("radius",32.0) * radius, "jumps":jumps
	}

	result.merge(extras,true)
	if "projectile" in gun.tags:
		result.projectile_seconds = 2.0*extras.range/320.0
		result.projectile_speed = gun.bullet_speed*2.0
		result.projectile_path_limit = result.projectile_speed*result.projectile_seconds
	return result

static func describe(s: Dictionary) -> String:
	var text = "伤害 %.2f %s · %.2f次/秒\n弹匣 %d · 装填 %.2f秒 · 暴击 %.0f%%" % [s.damage,damage_unit(s),s.rate,s.magazine,s.reload,s.crit*100]
	if "beam" in s.tags and not "pulse" in s.tags and not "charged" in s.tags: text += "\n激光tick：0.1秒；射速为脉冲次数"
	if "beam" in s.tags or "pulse_cone" in s.tags: text += "\n射程 %.1f 像素 · 判定宽 %.1f" % [s.range,s.width]
	if "projectile" in s.tags: text += "\n弹速 %.0f像素/秒 · 最长飞行 %.2f秒\n无提前碰撞时累计路径上限 %.0f像素（引力落地/锯盘回收可提前结束）" % [s.projectile_speed,s.projectile_seconds,s.projectile_path_limit]
	if "pulse_cone" in s.tags: text += " · 扇面全角 %.1f度" % rad_to_deg(s.angle*2)
	if "straight" in s.tags: text += "\n总目标上限 %d；不穿墙" % mini(8,s.pierce+1)
	if "ricochet" in s.tags: text += "\n墙面反弹 %d次，反弹伤害保留 %.0f%%" % [mini(4,s.bounces),s.bounce_retention*100]
	if "homing" in s.tags: text += "\n转向 %.2f弧度/秒 · 寻找半角 %.1f度" % [s.turn,rad_to_deg(s.lock_angle)]
	if s.warmup > 0: text += "\n蓄力/预热上限 %.2f秒" % s.warmup
	if s.shards > 0: text += "\n首次命中裂片 %d枚 × %.0f%%；有限一代" % [s.shards,s.shard_ratio*100]
	if s.refill > 0: text += "\n直接击杀弹匣+1，冷却0.2秒"
	if s.recovery != 1.0: text += "\n局部回正时间 ×%.2f" % s.recovery
	if "projectile" in s.tags or "beam" in s.tags: text += "\n对普通敌人冲量 %.1f" % s.impulse
	if "spread" in s.tags: text += " · 散布倍率 %.2f" % s.spread
	if "explosive" in s.tags: text += "\n爆炸半径 %.1f" % s.radius
	if "chain" in s.tags: text += "\n电弧后跳 %d" % s.jumps
	return text

static func damage_unit(s: Dictionary) -> String:
	if "gravity" in s.tags: return "/目标/场终结爆炸"
	if "returning" in s.tags: return "/目标/出行或回行（各至多一次）"
	if "homing" in s.tags: return "/枚导弹爆炸；每组2枚"
	if "explosive" in s.tags and "spread" in s.tags: return "/枚火箭爆炸；每组3枚"
	if "continuous" in s.tags: return "/tick（0.1秒）"
	if "charged" in s.tags: return "/基础贯穿；满蓄×2.5"
	if "pulse" in s.tags: return "/单束；3束独立交集"
	if "pulse_cone" in s.tags: return "/目标/次扇面"
	if "beam" in s.tags: return "/tick（0.1秒）"
	if "chain" in s.tags: return "/主目标；每后跳×75%"
	if "burst" in s.tags: return "/弹；3发一组"
	if "spread" in s.tags: return "/弹丸（多弹丸分别结算）"
	return "/弹"
