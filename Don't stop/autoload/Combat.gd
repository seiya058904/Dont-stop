extends Node

var actor_exclusions: Array[RID] = []
var exclusions_dirty = true
var dispatch_depth = 0
var attacks = 0
var damage_events = 0
var kill_events = 0
var max_depth_seen = 0
var audio_pool: Array = []
var sound_clock = 0.0
var reduced_flash = false

func _ready():
	get_tree().node_added.connect(_actor_added)
	for i in 8:
		var player = AudioStreamPlayer2D.new()
		player.bus = "SFX"
		player.volume_db = -15
		add_child(player)
		audio_pool.append(player)

func _actor_added(node: Node):
	if node is BaseMonster or node is Player:
		exclusions_dirty = true
		node.tree_exiting.connect(_actors_changed,CONNECT_ONE_SHOT)

func _actors_changed():
	exclusions_dirty = true

func _refresh_exclusions():
	actor_exclusions.clear()
	if is_instance_valid(Utils.player): actor_exclusions.append(Utils.player.get_rid())
	for actor in get_tree().get_nodes_in_group("monsters"): actor_exclusions.append(actor.get_rid())
	exclusions_dirty = false

func sound(stream: AudioStream, position: Vector2):
	for player in audio_pool:
		if not player.playing:
			player.stream = stream
			player.global_position = position
			player.play()
			return

func hit(target, context: Dictionary) -> bool:
	if not is_instance_valid(target) or target.is_die or get_tree().paused: return false
	if not target.training and (LevelServer.state != "COMBAT" or context.get("epoch",LevelServer.epoch) != LevelServer.epoch): return false
	var depth = int(context.get("depth",0))
	if depth > DemoConfig.MAX_DERIVATION: return false
	max_depth_seen = maxi(max_depth_seen,depth)
	var amount = maxf(0,context.get("damage",0.0))
	if target.is_elite and not target.is_boss: amount *= 1.0+context.get("elite_bonus",0.0)
	var hunter_applied = context.get("hunter_applied",false)
	if not hunter_applied and (target.is_elite or target.is_boss) and RewardServer.rank(14)>0:
		amount *= 1.0+0.05*RewardServer.rank(14); hunter_applied = true
	var resolved_context = context.duplicate(true)
	resolved_context.hunter_applied = hunter_applied
	var critical = depth == 0 and randf() < context.get("crit",0.0)
	if critical: amount *= 1.5
	var old_depth = dispatch_depth
	dispatch_depth = depth + 1
	var rewards = get_tree().get_nodes_in_group("reward")
	if depth == 0:
		for reward in rewards:
			if reward.connect_beforeAtk: amount += reward.beforeAtk(target,amount)
	if depth == 0:
		for reward in rewards:
			if reward.has_method("modify_direct"): amount += reward.modify_direct(target,amount)
	amount = snappedf(amount,0.01)
	damage_events += 1
	target.receive_damage(amount, critical, resolved_context)
	if depth == 0:
		if not target.is_die:
			if context.get("burn_talent",0.0) > 0: target.apply_burn("T15",context.burn_talent,DemoConfig.TALENTS.T15.seconds,context)
			if context.get("slow",0.0) > 0:
				target.apply_slow("T17",context.slow,DemoConfig.TALENTS.T17.seconds)
		if context.get("static_chance",0.0) > 0 and randf() < context.static_chance:
			secondary_hit(target,resolved_context,amount*DemoConfig.TALENTS.T14.damage,"T14")
		if critical and context.get("echo",0.0) > 0:
			secondary_hit(target,resolved_context,amount*context.echo,"T23")
	if depth == 0:
		for reward in rewards:
			if reward.has_method("after_direct"): reward.after_direct(target,amount,critical,resolved_context)
	if depth == 0 and not target.is_die:
		for reward in rewards:
			if reward.connect_afterAtk: reward.afterAtk(target,amount)
	dispatch_depth = old_depth
	return true

func secondary_hit(source, context: Dictionary, damage: float, talent: String):
	if Demo.cooldown(talent) > 0: return
	var nearest = null
	var distance = DemoConfig.TALENTS[talent].radius
	for target in get_tree().get_nodes_in_group("monsters"):
		if target == source or target.is_die: continue
		var d = source.global_position.distance_to(target.global_position)
		if d < distance and clear_line(source.global_position,target.global_position):
			nearest = target
			distance = d
	if nearest == null or not Demo.ready_trigger(talent): return
	var derived = context.duplicate(true)
	derived.damage = damage
	derived.depth = 1
	derived.crit = 0.0
	hit(nearest,derived)
	trace([source.global_position,nearest.global_position])

func clear_line(from: Vector2, to: Vector2) -> bool:
	# B11.1 test-only counters (game/diag/B11Probe.gd). Read-only: they observe this query, they do
	# not change it. See that file for why the cost is measured in microseconds rather than being
	# inferred from the frame time - the browser build is vsync-locked, so frame time hides it.
	var started := Time.get_ticks_usec() if B11Probe.enabled else 0
	if B11Probe.enabled: B11Probe.clear_line_calls += 1
	if not is_instance_valid(Utils.player): return false
	var result := _clear_line_query(from,to)
	if started != 0: B11Probe.clear_line_usec += Time.get_ticks_usec()-started
	return result

const CLEAR_LINE_MASK := 2147483649
## B11.1: ONE reusable query for the line-of-sight check. `clear_line` is issued on the order of
## 500 times a second in a dense Hell round, and every call used to allocate a fresh
## `PhysicsRayQueryParameters2D` and re-assign an `exclude` list holding a RID for the player plus
## one per live monster - up to 85 entries, converted to a packed array each time. The mask never
## changes and the actor set only changes when something spawns or dies, so the query is built once
## and the `exclude` list is only re-applied on the same dirty flag that already guarded the
## refresh. Identical queries, identical answers, minus the per-call churn.
var clear_query: PhysicsRayQueryParameters2D = null

func _clear_line_query(from: Vector2, to: Vector2) -> bool:
	if clear_query == null:
		clear_query = PhysicsRayQueryParameters2D.create(from,to,CLEAR_LINE_MASK)
	else:
		clear_query.from = from
		clear_query.to = to
	if exclusions_dirty:
		_refresh_exclusions()
		clear_query.exclude = actor_exclusions
	return Utils.player.get_world_2d().direct_space_state.intersect_ray(clear_query).is_empty()

func explosion(position: Vector2, radius: float, damage: float, gun = null, depth = 0):
	if depth > DemoConfig.MAX_DERIVATION: return
	var context = {"damage":damage,"depth":depth,"epoch":LevelServer.epoch,"gun":gun}
	if is_instance_valid(gun):
		context = gun.damage_context(depth)
		context.damage = damage
	explosion_context(position,radius,context)

func explosion_context(position: Vector2, radius: float, context: Dictionary):
	if context.get("depth",0) > DemoConfig.MAX_DERIVATION: return
	var footprint = preload("res://game/effects/CombatFootprint.gd").polygon(position,radius)
	for target in get_tree().get_nodes_in_group("monsters"):
		if not target.is_die and Geometry2D.is_point_in_polygon(target.global_position,footprint) and clear_line(position,target.global_position):
			hit(target,context)
	var effect = Node2D.new()
	effect.set_script(load("res://game/effects/CombatEffect.gd"))
	effect.radius = radius
	for point in footprint: effect.footprint.append(point-position)
	effect.global_position = position
	get_tree().current_scene.add_child(effect)
	sound(load("res://audio/body_hit_finisher_52.wav"),position)

func trace(points: Array, color = Color(0.4,0.85,1), width = 2.0):
	var effect = load("res://game/effects/CombatEffect.gd").new()
	effect.points.assign(points)
	effect.color = color
	effect.width = width
	get_tree().current_scene.add_child(effect)

func beam(gun, start: Vector2, direction: Vector2, context: Dictionary, limit: int):
	var visited = []
	for lane in [0.0,-0.5,0.5]:
		var from = start+direction.orthogonal()*gun.effective.width*lane
		var end = from+direction*gun.effective.range
		var query = PhysicsRayQueryParameters2D.create(from,end,2147483651)
		query.exclude = [Utils.player.get_rid()]
		var count = 0
		for step in limit:
			var result = gun.get_world_2d().direct_space_state.intersect_ray(query)
			if result.is_empty(): break
			var target = result.collider
			if not target is BaseMonster:
				end = result.position
				break
			if not target.get_instance_id() in visited and visited.size() < limit:
				visited.append(target.get_instance_id())
				hit(target,context)
			count += 1
			var excluded = query.exclude
			excluded.append(target.get_rid())
			query.exclude = excluded
			if count == limit: end = result.position
		trace([from,end],Color(0.7,0.9,1),maxf(1,gun.effective.width/3.0))

func cone(gun, start: Vector2, direction: Vector2, context: Dictionary):
	var length = gun.effective.range
	var angle = gun.effective.angle
	var footprint = preload("res://game/effects/CombatFootprint.gd").polygon(start,length,direction,angle)
	for target in get_tree().get_nodes_in_group("monsters"):
		var point = target.global_position+Vector2(0,-8)
		var offset = point-start
		if Geometry2D.is_point_in_polygon(point,footprint) and clear_line(start,point):
			hit(target,context)
			if context.has("burn") and not target.is_die: target.apply_burn("thermal",context.burn,1.0,context)
	var edge = Array(footprint)
	edge.append(start)
	trace(edge,Color(1,0.5,0.2) if context.has("burn") else Color(0.4,0.9,1),1.0)

func fragments(position: Vector2, angle: float, context: Dictionary, ignored, speed: float):
	for i in mini(3,context.get("shards",0)):
		var shard = load("res://game/bullets/SmpBullet.tscn").instantiate()
		shard.context = context.duplicate(true)
		shard.context.depth = 1
		shard.context.shards = 0
		shard.context.damage *= context.get("shard_ratio",0.25)
		shard.context.crit = 0.0
		shard.hurt = shard.context.damage
		shard.speed = speed
		get_tree().current_scene.add_child(shard)
		shard.global_position = position
		shard.rotation = angle+(i-(context.shards-1)*0.5)*0.28
		shard.add_collision_exception_with(ignored)
		shard.fire()

func arc(gun, start: Vector2, direction: Vector2):
	attacks += 1
	var query = PhysicsRayQueryParameters2D.create(start,start+direction*gun.effective.range,2147483651)
	query.exclude = [Utils.player.get_rid()]
	var hit_result = gun.get_world_2d().direct_space_state.intersect_ray(query)
	var points: Array[Vector2] = [start]
	var target = hit_result.get("collider")
	if not target is BaseMonster:
		points.append(hit_result.get("position",start+direction*gun.effective.range))
	else:
		var visited: Array = []
		var amount = gun.effective.damage
		for hop in range(gun.effective.jumps+1):
			if not is_instance_valid(target) or target in visited: break
			var location = target.global_position
			visited.append(target)
			points.append(location)
			var context = gun.damage_context(0 if hop == 0 else 1)
			context.damage = amount
			hit(target,context)
			amount *= 0.75
			var nearest = null
			var distance = 88.0
			for candidate in get_tree().get_nodes_in_group("monsters"):
				if candidate in visited or candidate.is_die: continue
				var d = location.distance_to(candidate.global_position)
				if d < distance and clear_line(location,candidate.global_position):
					nearest = candidate
					distance = d
			target = nearest
			if target == null: break
	var line = Node2D.new()
	line.set_script(load("res://game/effects/CombatEffect.gd"))
	line.points = points
	get_tree().current_scene.add_child(line)
