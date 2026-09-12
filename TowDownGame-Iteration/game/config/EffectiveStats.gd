extends RefCounted
class_name EffectiveStats

static func calculate(gun, attachments: Array, saved: Dictionary = {}) -> Dictionary:
	var b = gun.base_stats
	var ranks = Demo.talents if saved.is_empty() else saved.talents
	var level_damage = PlayerData.player_damage if saved.is_empty() else 0.3 * saved.level
	var magazine_flat = 0
	var reload_mul = 1.0
	var damage_percent = PlayerData.base_bullet_damage + int(ranks.get("T01",0)) * 0.08
	var crit = PlayerData.base_aim_enh * 0.01
	var spread = 1.0
	var impulse = 1.0
	var radius = 1.0
	var jumps = 3
	for am in attachments:
		match am.am_id:
			0: reload_mul *= 0.8
			1: magazine_flat += 10
			2: magazine_flat += 20
			3:
				reload_mul *= 0.8
				magazine_flat += 10
			5:
				reload_mul *= 0.8
				magazine_flat += 5
			6: magazine_flat += 50
			7: magazine_flat += 19
			8: magazine_flat += 70
			110: crit += 0.08
			112: spread *= 0.75
			114:
				damage_percent += 0.15
				reload_mul *= 1.1
			117: impulse *= 1.35
			121: radius *= 1.2
			122: jumps += 1
	return {
		"tags":gun.tags, "damage": (b.damage + level_damage) * (1.0 + damage_percent),
		"magazine": maxi(1, int((b.magazine + magazine_flat) * (1.0 + PlayerData.base_magazine_count + int(ranks.get("T04",0)) * 0.1))),
		"reload": maxf(0.15, b.reload * maxf(0.1, 1.0 - PlayerData.base_reload_speed - int(ranks.get("T03",0)) * 0.05) * reload_mul),
		"rate": clampf(b.rate * PlayerData.player_fire_rate * (1.0 + Demo.kill_stacks * int(ranks.get("T10",0)) * 0.03), 0.1, 60.0),
		"crit": clampf(crit, 0.0, 1.0), "spread":spread,
		"impulse": b.impulse * impulse, "radius":32.0 * radius, "jumps":jumps
	}

static func describe(s: Dictionary) -> String:
	var text = "伤害 %.2f %s · %.2f次/秒\n弹匣 %d · 装填 %.2f秒 · 暴击 %.0f%%" % [s.damage,damage_unit(s),s.rate,s.magazine,s.reload,s.crit*100]
	if "beam" in s.tags: text += "\n激光tick：0.1秒；射速为脉冲次数"
	if "projectile" in s.tags or "beam" in s.tags: text += "\n对普通敌人冲量 %.1f" % s.impulse
	if "spread" in s.tags: text += " · 散布倍率 %.2f" % s.spread
	if "explosive" in s.tags: text += "\n爆炸半径 %.1f" % s.radius
	if "chain" in s.tags: text += "\n电弧后跳 %d" % s.jumps
	return text

static func damage_unit(s: Dictionary) -> String:
	if "beam" in s.tags: return "/tick（0.1秒）"
	if "chain" in s.tags: return "/主目标；每后跳×75%"
	if "burst" in s.tags: return "/弹；3发一组"
	if "spread" in s.tags: return "/弹丸（多弹丸分别结算）"
	return "/弹"
