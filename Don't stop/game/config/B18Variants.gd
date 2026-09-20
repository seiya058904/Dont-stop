extends RefCounted

## B19 keeps the B18 arrival hook, but allocates variants against the authored Hell
## population ratios instead of a fixed small live cap. The counters are per epoch so
## the same spawn order produces the same tier distribution in Web, native, and tests.
static var generation := -1
static var arrivals := 0
static var enchanted_arrivals := 0
static var tier_two_arrivals := 0

const ENCHANTMENT_TOTAL_RATIOS := [0.10,0.15,0.22,0.32,0.45,0.58,0.70,0.82,0.90]
const ENCHANTMENT_TIER_TWO_RATIOS := [0.00,0.00,0.03,0.05,0.08,0.12,0.18,0.25,0.30]
const GIANT_PERIOD := 24

static func enchantment_total_ratio(stage: int) -> float:
	if stage < 31 or stage > 39: return 0.0
	return ENCHANTMENT_TOTAL_RATIOS[stage-31]

static func enchantment_tier_two_ratio(stage: int) -> float:
	if stage < 31 or stage > 39: return 0.0
	return ENCHANTMENT_TIER_TWO_RATIOS[stage-31]

static func _reset_if_needed() -> void:
	if generation == LevelServer.epoch: return
	generation = LevelServer.epoch
	arrivals = 0
	enchanted_arrivals = 0
	tier_two_arrivals = 0

static func _target_count(population: int, ratio: float) -> int:
	return ceili(float(population)*ratio)

static func _giant_count(tree: SceneTree) -> int:
	var count := 0
	for actor in tree.get_nodes_in_group("monsters"):
		if actor.is_die or actor.is_queued_for_deletion(): continue
		if actor.get_meta("giant",false): count += 1
	return count

static func _ensure_variant_layer(actor) -> void:
	var parent = actor.get_parent()
	if not is_instance_valid(parent): return
	var layer = parent.get_node_or_null("B19EnchantmentLayer")
	if is_instance_valid(layer): return
	layer = preload("res://game/monster/B19EnchantmentLayer.gd").new()
	layer.name = "B19EnchantmentLayer"
	parent.add_child(layer)

static func select(id: String, tree: SceneTree, point: Vector2, summoned: bool, ordinary_radius: float) -> Dictionary:
	var result = {"kind":0,"point":point,"enchantment":0}
	var stage = LevelServer.level
	# Stage 40 is the final boss encounter; ordinary Hell variants stop at stage 39.
	if stage < 31 or stage > 39 or summoned or id not in ["E01","E02","E05"]: return result
	_reset_if_needed()
	arrivals += 1

	# Giant arrivals stay rare and independent from the ordinary HP axis. A failed point
	# check falls through to the normal enchantment allocator for this same arrival.
	var giant_due = stage >= 33 and id == "E01" and arrivals%GIANT_PERIOD == 0
	if giant_due:
		var giant_cap = 3 if stage >= 37 else 1
		if _giant_count(tree) < giant_cap:
			var town = LevelServer.town
			var radius = ordinary_radius*2.2
			if is_instance_valid(town) and is_instance_valid(town.arena):
				if not town.arena.point_clear(point,radius): point = town.spawn_point(radius)
				if point.is_finite():
					# A giant may very rarely carry the first enchantment tier, but its
					# final HP remains the independent B04-reference value.
					var rare_enchantment = 1 if stage >= 37 and arrivals%48 == 0 else 0
					return {"kind":3,"point":point,"enchantment":rare_enchantment}

	# Desired cumulative counts implement the authored total and absolute tier-2
	# percentages without converting every tactical actor into an elite-looking unit.
	var total_target = _target_count(arrivals,enchantment_total_ratio(stage))
	var tier_two_target = _target_count(arrivals,enchantment_tier_two_ratio(stage))
	if enchanted_arrivals < total_target:
		var kind = 1
		if tier_two_arrivals < tier_two_target:
			kind = 2; tier_two_arrivals += 1
		enchanted_arrivals += 1
		result.kind = kind
		result.enchantment = kind
	return result

static func _apply_enchantment(actor, tier: int, giant := false) -> void:
	if tier <= 0: return
	actor.set_meta("enchantment",tier)
	actor.set_meta("variant_name","强化附魔" if tier == 1 else "重度附魔")
	# Giant HP and speed are independent from enchantment. The rare giant enchantment
	# only adds the readable attack identity and damage axis.
	if not giant:
		actor.HP *= 2.0 if tier == 1 else 4.0
		actor.SPEED *= 1.08 if tier == 1 else 1.15
	actor.variant_damage = 2.0 if tier == 1 else 4.0

static func apply(actor, kind: int, giant_enchantment := 0) -> void:
	if kind == 0 or actor.get_meta("variant_applied",false): return
	actor.set_meta("variant_applied",true)
	if kind == 3:
		actor.set_meta("giant",true)
		actor.set_meta("variant_name","巨型追击者")
		actor.HP = M5Content.giant_final_hp(LevelServer.level)
		actor.SPEED *= 0.55
		actor.sprite_body.scale *= 2.2
		var body = actor.get_node("CollisionShape2D")
		body.scale *= 2.2; body.position *= 2.2
		actor.get_node("Area2D").scale *= 2.2
		actor.get_node("UndeadShadow").scale *= 2.2
		_apply_enchantment(actor,giant_enchantment,true)
	else:
		_apply_enchantment(actor,kind)
	var tier := int(actor.get_meta("enchantment",0))
	# A deterministic visual phase; consumes no gameplay random numbers.
	actor.set_enchantment_visual(tier,arrivals%8)
	actor.set_meta("initialized_hp",actor.HP)
	actor.set_meta("initialized_speed",actor.SPEED)
	if actor.get("max_hp") != null: actor.max_hp = actor.HP
	_ensure_variant_layer(actor)
	actor.queue_redraw()
