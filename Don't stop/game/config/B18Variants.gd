extends RefCounted
# Lightweight numerical variants. No elite AI, extra attack or reward multiplier.
static var generation := -1
static var arrivals := 0

static func select(id: String, tree: SceneTree, point: Vector2, summoned: bool, ordinary_radius: float) -> Dictionary:
	var result = {"kind":0,"point":point}
	var stage = LevelServer.level
	if stage < 31 or stage > 40 or summoned or id not in ["E01","E02","E05"]: return result
	if generation != LevelServer.epoch:
		generation = LevelServer.epoch; arrivals = 0
	arrivals += 1
	var giant_due = stage >= 33 and id == "E01" and arrivals%24 == 0
	var period = [20,19,18,17,16,14,12,10,9,12][stage-31]
	if not giant_due and arrivals%period != 0: return result
	var giants = 0; var enchanted = 0
	for actor in tree.get_nodes_in_group("monsters"):
		if actor.is_die or actor.is_queued_for_deletion(): continue
		if actor.get_meta("giant",false): giants += 1
		if actor.get_meta("enchantment",0)>0: enchanted += 1
	if giant_due and giants < (3 if stage >= 37 else 1):
		var town = LevelServer.town
		var radius = ordinary_radius*2.2
		if is_instance_valid(town) and is_instance_valid(town.arena):
			if not town.arena.point_clear(point,radius): point = town.spawn_point(radius)
			if point.is_finite(): return {"kind":3,"point":point}
	if arrivals%period == 0 and enchanted < (8 if stage >= 37 else 4):
		result.kind = 2 if stage >= 35 and int(arrivals/period)%3 == 0 else 1
	return result

static func apply(actor, kind: int):
	if kind == 0 or actor.get_meta("variant_applied",false): return
	actor.set_meta("variant_applied",true)
	if kind == 3:
		actor.set_meta("giant",true)
		actor.set_meta("variant_name","巨型追击者")
		actor.HP *= 12.0
		actor.SPEED *= 0.55
		actor.sprite_body.scale *= 2.2
		var body = actor.get_node("CollisionShape2D")
		body.scale *= 2.2; body.position *= 2.2
		actor.get_node("Area2D").scale *= 2.2
		actor.get_node("UndeadShadow").scale *= 2.2
	else:
		actor.set_meta("enchantment",kind)
		actor.set_meta("variant_name","强化附魔" if kind == 1 else "重度附魔")
		actor.HP *= 2.0 if kind == 1 else 4.0
		actor.SPEED *= 1.08 if kind == 1 else 1.15
		actor.variant_damage = 2.0 if kind == 1 else 4.0
	actor.set_meta("initialized_hp",actor.HP)
	actor.set_meta("initialized_speed",actor.SPEED)
	if actor.get("max_hp") != null: actor.max_hp = actor.HP
	actor.queue_redraw()
