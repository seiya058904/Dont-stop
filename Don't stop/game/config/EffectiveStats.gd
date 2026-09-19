extends RefCounted
class_name EffectiveStats

static func calculate(gun, upgrades = null, saved: Dictionary = {}, ledger = null) -> Dictionary:
	if upgrades == null: upgrades = Demo.owned_global_upgrades if saved.is_empty() else saved.get("owned_global_upgrades",[])
	var b = gun.base_stats
	var ranks = Demo.talents if saved.is_empty() else saved.talents
	var level_damage = PlayerData.player_damage if saved.is_empty() else PlayerData.PROGRESSION.damage(saved.level)
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
	if "straight" in gun.tags: extras.pierce += int(DemoConfig.talent_value("T13",int(ranks.get("T13",0))))
	var cycle = 1.0+DemoConfig.talent_value("T02",int(ranks.get("T02",0)))+RewardServer.momentum()+PlayerData.player_fire_rate-1.0
	cycle *= 1.0+Demo.kill_stacks*DemoConfig.talent_value("T10",int(ranks.get("T10",0)))
	if ledger:
		for stat in ["damage","magazine","reload","rate","impulse"]: ledger.add(stat,"base","weapon",TranslationServer.translate(gun.weapon_name),"flat",b[stat])
		ledger.add("damage","level","level","等级成长","flat",level_damage)
		ledger.add("damage","base","power","武器品阶强度","multiplier",WeaponCatalog.power(gun.weapon_id))
		for row in [["damage",PlayerData.base_bullet_damage],["magazine",PlayerData.base_magazine_count],["reload",-PlayerData.base_reload_speed]]:
			ledger.add(row[0],"legacy","legacy_base","原型全局成长","additive_percentage",row[1])
		ledger.add("crit","base","weapon","原型基础暴击","percentage_point",PlayerData.base_aim_enh*0.01)
		ledger.add("range","base","weapon","武器基础射程","flat",spec.get("range",320.0))
		ledger.add("spread","base","weapon","基础散布倍率","flat",1.0)
		for row in [["damage","T01"],["rate","T02"],["reload","T03"],["magazine","T04"],["range","T05"],["crit","T06"],["impulse","T18"]]:
			var value=DemoConfig.talent_value(row[1],int(ranks.get(row[1],0)))
			if row[0]=="reload": value=-value
			ledger.add(row[0],"talent",row[1],DemoConfig.TALENTS[row[1]].name,"percentage_point" if row[0]=="crit" else "additive_percentage",value,ranks.get(row[1],0)>0)
		ledger.add("rate","reward","8","琥珀镰刀","additive_percentage",PlayerData.player_fire_rate-1.0,PlayerData.player_fire_rate>1,"限时连杀增益")
		ledger.add("rate","reward","22","动量环","additive_percentage",RewardServer.momentum(),RewardServer.momentum()>0,"连续移动2秒")
		ledger.add("impulse","reward","20","冲量弹簧","additive_percentage",0.15*RewardServer.rank(20),RewardServer.rank(20)>0,"仅普通敌人")
		ledger.add("rate","condition","T10",DemoConfig.TALENTS.T10.name,"multiplier",1.0+Demo.kill_stacks*DemoConfig.talent_value("T10",int(ranks.get("T10",0))),Demo.kill_stacks>0,"有效击杀后限时层数")
		if gun.weapon_id==6: ledger.add("range","base","laser","原型激光距离换算","multiplier",1000.0/320.0)
	if "continuous" in gun.tags:
		damage_mul *= cycle
		if ledger: ledger.add("damage","condition","thermal_cycle","热流射速转每tick伤害","multiplier",cycle,true,"固定0.1秒tick；射速来源在射频项展开")
	elif "rotary" in gun.tags and b.rate*cycle > 24.0:
		var overflow = b.rate*cycle/24.0
		damage_mul *= overflow
		if ledger: ledger.add("damage","condition","rotary_cycle","转管超限射速转单发伤害","multiplier",overflow,true,"发射上限仍为24/s")
	var applied = {}
	for upgrade in upgrades:
		var id = int(upgrade) if upgrade is String or upgrade is StringName or upgrade is int else upgrade.am_id
		if AttachmentCatalog.DEFINITIONS.has(id) and not applied.has(id):
			applied[id] = true
			var d = AttachmentCatalog.DEFINITIONS[id]
			if ledger:
				for key in d:
					var mapping={"damage":["damage","additive_percentage"],"damage_mul":["damage","multiplier"],"crit":["crit","percentage_point"],"magazine_mul":["magazine","multiplier"],"reload_mul":["reload","multiplier"],"range_mul":["range","multiplier"],"spread_mul":["spread","multiplier"],"impulse_mul":["impulse","additive_percentage"],"shards":["shards","flat"],"pierce":["pierce","flat"]}
					if mapping.has(key):
						ledger.add(mapping[key][0],"upgrade",str(id),upgrade_name(id),mapping[key][1],d[key]-1 if key=="impulse_mul" else d[key])
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
				if d.has(key):
					# A purchased shard core adds fragments; it must not downgrade a
					# weapon's native fragments from 35% to the generic core's 25%.
					extras[key] = maxf(extras[key],d[key]) if key == "shard_ratio" and spec.get("shards",0) > 0 else d[key]

	var result = {
		"tags":gun.tags, "damage": (b.damage + level_damage) * WeaponCatalog.power(gun.weapon_id) * (1.0 + damage_percent)*damage_mul,
		"magazine": maxi(1, int((b.magazine * magazine_mul) * (1.0 + PlayerData.base_magazine_count + DemoConfig.talent_value("T04",int(ranks.get("T04",0)))))),
		"reload": maxf(DemoConfig.MIN_RELOAD_SECONDS, b.reload * maxf(0.1, 1.0 - PlayerData.base_reload_speed - DemoConfig.talent_value("T03",int(ranks.get("T03",0)))) * reload_mul),
		"rate": 10.0 if "continuous" in gun.tags else clampf(b.rate * cycle, 0.1, 24.0 if "rotary" in gun.tags else 60.0),
		"crit": clampf(crit, 0.0, 1.0), "spread":spread,
		"impulse": b.impulse * impulse, "radius":WeaponCatalog.definition(gun.weapon_id).get("radius",32.0) * radius, "jumps":jumps
	}

	result.merge(extras,true)
	if "projectile" in gun.tags:
		result.projectile_seconds = 2.0*extras.range/320.0
		result.projectile_speed = gun.bullet_speed*2.0
		result.projectile_path_limit = result.projectile_speed*result.projectile_seconds
	return result

static func upgrade_name(id: int) -> String:
	var item=Utils.am_dict[str(id)].instantiate()
	var title=TranslationServer.translate(item.am_name)
	item.free()
	return title+"（永久配件）"

static func player_values() -> Dictionary:
	var boots=Utils.player.reward_root.get_node_or_null("REWARD BLUE BOOTS") if is_instance_valid(Utils.player) else null
	return {"speed":100*PlayerData.player_speed+100*DemoConfig.talent_value("T08",Demo.rank("T08"))+(5*mini(boots.count,6) if boots else 0)+100*RewardServer.momentum(),"max_hp":PlayerData.player_hp_max,"hp":PlayerData.player_hp,"level":PlayerData.player_level,"exp":PlayerData.player_exp,"exp_max":PlayerData.getMaxExp(),"points":PlayerData.reward_point,"normal_incoming":DemoConfig.NORMAL_INCOMING,"boss_incoming":DemoConfig.BOSS_INCOMING}

static func inspect(gun) -> Dictionary:
	var ledger=preload("res://game/config/StatLedger.gd").new()
	var final=calculate(gun,null,{},ledger)
	var player=player_values()
	player.shield_unlocked=Demo.rank("T19")>0
	player.shield_cooldown=Demo.cooldown("T19")
	player.pickup_multiplier=1.0+RewardServer.pickup_bonus()
	player.pickup=player.pickup_multiplier
	ledger.add("pickup","base","base","基础拾取范围","flat",1.0)
	ledger.add("pickup","talent","T09",DemoConfig.TALENTS.T09.name,"additive_percentage",DemoConfig.talent_value("T09",Demo.rank("T09")),Demo.rank("T09")>0)
	ledger.add("pickup","reward","23","拾取奖励","additive_percentage",RewardServer.pickup_bonus()-DemoConfig.talent_value("T09",Demo.rank("T09")),RewardServer.rank(23)>0)
	player.reserve_magazines=PlayerData.reserve_magazines
	ledger.add("speed","base","base","基础移动","flat",100*PlayerData.player_speed)
	ledger.add("speed","talent","T08",DemoConfig.TALENTS.T08.name,"flat",100*DemoConfig.talent_value("T08",Demo.rank("T08")),Demo.rank("T08")>0)
	ledger.add("speed","reward","5","蓝靴","flat",5*mini(RewardServer.rank(5),6),RewardServer.rank(5)>0)
	ledger.add("speed","reward","22","动量环","flat",100*RewardServer.momentum(),RewardServer.momentum()>0,"连续移动2秒")
	var level_hp=PlayerData.PROGRESSION.HP_PER_LEVEL*(PlayerData.player_level-1)
	var talent_hp=DemoConfig.talent_value("T07",Demo.rank("T07"))
	ledger.add("max_hp","base","base","初始生命","flat",5)
	ledger.add("max_hp","level","level","等级生命","flat",level_hp)
	ledger.add("max_hp","talent","T07",DemoConfig.TALENTS.T07.name,"flat",talent_hp,Demo.rank("T07")>0)
	# Old saves preserve historical HP; do not fabricate purchases that were never recorded.
	var helmet=3*mini(RewardServer.rank(2),4)
	ledger.add("max_hp","reward","2","头盔（当前有效层）","flat",helmet,helmet>0)
	ledger.add("max_hp","history","saved_hp","已保存的原型成长/历史差额","flat",player.max_hp-5-level_hp-talent_hp-helmet,true,"含细菌击杀成长及旧档历史；不重复授予")
	ledger.add("damage","condition","T22",DemoConfig.TALENTS.T22.name,"multiplier",1.0+DemoConfig.talent_value("T22",Demo.rank("T22")),Demo.crowd_active,"100范围至少3敌")
	var first_shot=gun.first_round or gun.boosted_frame==Engine.get_process_frames()
	var first_multiplier=1.0+DemoConfig.talent_value("T12",Demo.rank("T12")) if gun.first_round else gun.volley_boost
	ledger.add("damage","condition","T12",DemoConfig.TALENTS.T12.name,"multiplier",first_multiplier,first_shot,"实际装填后的下一次发射；同次齐射共享")
	final.damage=gun.preview_damage_context().damage
	final.maximum_rate=final.rate
	if "rotary" in gun.tags:
		final.rate=1.0/gun.timer.wait_time
		ledger.add("rate","condition","spin","当前转管转速","multiplier",final.rate/final.maximum_rate,true,"实际计时器；满转上限 %.1f/s" % final.maximum_rate)
	final.rpm=final.rate*60
	final.projectile_count=gun.projectile_count()
	ledger.add("projectile_count","base","weapon","当前武器发射机制","flat",final.projectile_count,true,"每次发射；连续束流显示1条，后续裂片另列")
	ledger.add("shards","base","weapon","武器基础裂片","flat",WeaponCatalog.definition(gun.weapon_id).get("shards",0))
	ledger.add("pierce","base","weapon","武器基础贯穿","flat",WeaponCatalog.definition(gun.weapon_id).get("pierce",0))
	ledger.add("pierce","talent","T13",DemoConfig.TALENTS.T13.name,"flat",DemoConfig.talent_value("T13",Demo.rank("T13")),"straight" in gun.tags,"仅直射；最多8目标")
	for stat in ["magazine","reload","rate","crit"]:
		ledger.add(stat,"rule","bounds","运行时边界/取整","rule",{"magazine":"取整，至少1发","reload":"至少%.2f秒" % DemoConfig.MIN_RELOAD_SECONDS,"rate":"热流10 tick/s；转管至多24，其余60","crit":"0–100%"}[stat])
	var upgrade_deltas={}
	var current=calculate(gun)
	for id in Demo.owned_global_upgrades:
		var without=calculate(gun,Demo.owned_global_upgrades.filter(func(other): return str(other)!=str(id)))
		var delta={}
		for stat in ["damage","crit","magazine","reload","range","spread","impulse","shards","pierce"]:
			var contribution=float(current[stat])-float(without[stat])
			if not is_zero_approx(contribution): delta[stat]=contribution
		upgrade_deltas[str(id)]=delta
	return {"weapon":final,"player":player,"ledger":ledger,"conditions":conditions(gun),"upgrade_deltas":upgrade_deltas}

static func conditions(gun) -> Array:
	var rows=[]
	for id in Demo.talents:
		if id in ["T01","T02","T03","T04","T05","T06","T07","T08","T09","T18"]: continue
		rows.append({"name":DemoConfig.TALENTS[id].name,"source":"天赋","info":DemoConfig.talent_info(id),"status":Demo.talent_status(id)})
	for reward in Utils.player.reward_root.get_children():
		rows.append({"name":TranslationServer.translate(reward.reward_name),"source":"奖励 NPC · %d层" % reward.count,"info":TranslationServer.translate(reward.reward_info),"status":"生效" if reward.id==22 and reward.get("moving_buff")==true else "按条件触发 / 效果上限见说明"})
	rows.append({"name":"全局强化与 Attachment","source":"永久配件","info":"当前设计中两者是同一组全枪强化，购买一次，无装备槽；来源不会重复计算。","status":"%d / 24" % Demo.owned_global_upgrades.size()})
	return rows

static func describe(s: Dictionary) -> String:
	var text = "伤害 %.2f %s · %.2f次/秒\n弹匣 %d · 装填 %.2f秒 · 暴击 %.0f%%" % [s.damage,damage_unit(s),s.rate,s.magazine,s.reload,s.crit*100]
	if "beam" in s.tags and not "pulse" in s.tags and not "charged" in s.tags: text += "\n激光tick：0.1秒；射速为脉冲次数"
	if "beam" in s.tags or "pulse_cone" in s.tags: text += "\n射程 %.1f 像素 · 判定宽 %.1f" % [s.range,s.width]
	if "projectile" in s.tags: text += "\n弹速 %.0f像素/秒 · 最长飞行 %.2f秒\n无提前碰撞时累计路径上限 %.0f像素（引力落地/锯盘回收可提前结束）" % [s.projectile_speed,s.projectile_seconds,s.projectile_path_limit]
	if "pulse_cone" in s.tags: text += " · 扇面全角 %.1f度" % rad_to_deg(s.angle*2)
	if "straight" in s.tags: text += "\n总目标上限 %d；不穿墙" % mini(8,s.pierce+1)
	if "charged" in s.tags: text += "\n满蓄循环至少 %.2f秒（蓄力+冷却，不含装填）；轻点减少宽度/贯穿" % (s.warmup+1.0/s.rate)
	if "rotary" in s.tags: text += "\n24发/秒封顶；超限射速已转为单发伤害"
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
