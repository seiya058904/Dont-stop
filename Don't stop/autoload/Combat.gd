extends Node

var actor_exclusions: Array[RID] = []
var exclusions_dirty = true
var exclusions_revision := 0
var clear_query_revision := -1
var dispatch_depth = 0
var attacks = 0
var damage_events = 0
var kill_events = 0
var max_depth_seen = 0
var audio_pool: Array = []
var sound_clock = 0.0
var reduced_flash = false
var _group_cache_frame := -1
var _group_cache_tick := -1
var _monster_group_cache: Array = []
var _reward_group_cache: Array = []

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
		_group_cache_frame = -1
		node.tree_exiting.connect(_actors_changed,CONNECT_ONE_SHOT)
		# A callback may refresh while the node is still in its groups during exiting.
		node.tree_exited.connect(_actors_changed,CONNECT_ONE_SHOT)

func _actors_changed():
	exclusions_dirty = true
	_group_cache_frame = -1

func invalidate_group_cache() -> void:
	_group_cache_frame = -1
	_group_cache_tick = -1

func _refresh_group_cache() -> void:
	var frame = Engine.get_process_frames()
	var tick = Engine.get_physics_frames()
	if _group_cache_frame == frame and _group_cache_tick == tick: return
	_group_cache_frame = frame
	_group_cache_tick = tick
	_monster_group_cache = get_tree().get_nodes_in_group("monsters")
	_reward_group_cache = get_tree().get_nodes_in_group("reward")
	# Callers receive immutable snapshots; nested dispatch never mutates its parent.
	_monster_group_cache.make_read_only()
	_reward_group_cache.make_read_only()

func _monsters_for_frame() -> Array:
	_refresh_group_cache()
	return _monster_group_cache

func _rewards_for_frame() -> Array:
	_refresh_group_cache()
	return _reward_group_cache

func _refresh_exclusions():
	actor_exclusions.clear()
	if is_instance_valid(Utils.player): actor_exclusions.append(Utils.player.get_rid())
	for actor in get_tree().get_nodes_in_group("monsters"): actor_exclusions.append(actor.get_rid())
	exclusions_dirty = false
	exclusions_revision += 1

func sound(stream: AudioStream, position: Vector2):
	for player in audio_pool:
		if not player.playing:
			player.stream = stream
			player.global_position = position
			player.play()
			return

var measuring_hit := false
func hit(target, context: Dictionary) -> bool:
	if not B11Probe.enabled or measuring_hit: return _hit(target,context)
	measuring_hit = true
	var started := Time.get_ticks_usec()
	var result := _hit(target,context)
	B11Probe.cost("hit_outer_inclusive",started)
	measuring_hit = false
	return result

func _hit(target, context: Dictionary) -> bool:
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
	# `_hit` only adds a top-level resolution flag. Nested payloads (gun/spec data) are
	# read-only here; derived effects that mutate their context already deep-copy at
	# their own boundary. Avoid cloning the full payload for every real hit.
	var resolved_context = context.duplicate()
	resolved_context.hunter_applied = hunter_applied
	var critical = depth == 0 and randf() < context.get("crit",0.0)
	if critical: amount *= 1.5
	var old_depth = dispatch_depth
	dispatch_depth = depth + 1
	var rewards = _rewards_for_frame()
	if depth == 0:
		for reward in rewards:
			if not is_instance_valid(reward) or reward.is_queued_for_deletion(): continue
			if reward.connect_beforeAtk: amount += reward.beforeAtk(target,amount)
	if depth == 0:
		for reward in rewards:
			if not is_instance_valid(reward) or reward.is_queued_for_deletion(): continue
			if reward.has_method("modify_direct"): amount += reward.modify_direct(target,amount)
	amount = snappedf(amount,0.01)
	damage_events += 1
	var hp_before = target.HP
	target.receive_damage(amount, critical, resolved_context)
	if not target.training and hp_before > target.HP and context.get("native_attack",depth == 0):
		Demo.linked_blast(target.global_position,resolved_context)
		fission(target,resolved_context)
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
			if not is_instance_valid(reward) or reward.is_queued_for_deletion(): continue
			if reward.has_method("after_direct"): reward.after_direct(target,amount,critical,resolved_context)
	if depth == 0 and not target.is_die:
		for reward in rewards:
			if not is_instance_valid(reward) or reward.is_queued_for_deletion(): continue
			if reward.connect_afterAtk: reward.afterAtk(target,amount)
	dispatch_depth = old_depth
	return true

func secondary_hit(source, context: Dictionary, damage: float, talent: String):
	if Demo.cooldown(talent) > 0: return
	var nearest = null
	var distance = DemoConfig.TALENTS[talent].radius
	for target in _monsters_for_frame():
		if not is_instance_valid(target) or target.is_queued_for_deletion(): continue
		if target == source or target.is_die: continue
		var d = source.global_position.distance_to(target.global_position)
		if d < distance and clear_line(source.global_position,target.global_position):
			nearest = target
			distance = d
	if nearest == null or not Demo.ready_trigger(talent): return
	var derived = context.duplicate(true)
	derived.damage = damage
	derived.depth = 1
	derived.native_attack = false
	derived.crit = 0.0
	hit(nearest,derived)
	if talent == "T23":
		var midpoint = (source.global_position+nearest.global_position)*0.5
		var normal = source.global_position.direction_to(nearest.global_position).orthogonal()*5.0
		trace([source.global_position,midpoint+normal,nearest.global_position,midpoint-normal,source.global_position],Color(0.9,0.65,1),1.0)
	else:
		trace([source.global_position,nearest.global_position],Color(0.4,0.85,1))

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
## Reuse the query and copy exclusions only when their generation changes.
## CombatFootprint also rebuilds this list; the revision (not dirty alone) is what
## prevents this query retaining freed RIDs after another consumer refreshed it.
var clear_query: PhysicsRayQueryParameters2D = null

func _clear_line_query(from: Vector2, to: Vector2) -> bool:
	var town = LevelServer.town
	var arena = town.arena if is_instance_valid(town) else null
	if is_instance_valid(arena) and arena.has_method("static_line_may_hit") and not arena.static_line_may_hit(from,to):
		if B11Probe.enabled: B11Probe.clear_line_static_skips += 1
		return true
	if clear_query == null:
		clear_query = PhysicsRayQueryParameters2D.create(from,to,CLEAR_LINE_MASK)
	else:
		clear_query.from = from
		clear_query.to = to
	if exclusions_dirty:
		_refresh_exclusions()
	if clear_query_revision != exclusions_revision:
		clear_query.exclude = actor_exclusions
		clear_query_revision = exclusions_revision
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
	for target in _monsters_for_frame():
		if not is_instance_valid(target) or target.is_queued_for_deletion(): continue
		if not target.is_die and Geometry2D.is_point_in_polygon(target.global_position,footprint) and clear_line(position,target.global_position):
			hit(target,context)
			heat_contact(target.global_position+Vector2(0,-8))
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
	var width = float(context.get("beam_width",gun.effective.width))
	var normal = direction.orthogonal()
	var targets = _monsters_for_frame().filter(func(t): return not t.is_die)
	targets.sort_custom(func(a,b): return start.distance_squared_to(a.global_position)<start.distance_squared_to(b.global_position))
	var count = 0
	for target in targets:
		var point = target.global_position+Vector2(0,-8)
		var along = (point-start).dot(direction)
		var lateral = (point-start).dot(normal)
		if along<0 or along>gun.effective.range or absf(lateral)>width*0.5+6: continue
		var lane_start = start+normal*clampf(lateral,-width*0.5,width*0.5)
		if not clear_line(start,lane_start) or not clear_line(lane_start,point): continue
		if hit(target,context):
			count += 1
			heat_contact(point)
		if count>=limit: break
	# Closely spaced strips cover the visual width; damage uses continuous geometry above.
	var strips = maxi(2,ceili(width/3.0))
	var batch = load("res://game/effects/CombatEffect.gd").new()
	batch.width = width/strips+0.3
	batch.color = Color(0.55,0.85,1)
	for i in strips:
		var from = start+normal*lerpf(-width*0.5,width*0.5,(i+0.5)/strips)
		if not clear_line(start,from): continue
		var end = from+direction*gun.effective.range
		var query = PhysicsRayQueryParameters2D.create(from,end,CLEAR_LINE_MASK)
		if exclusions_dirty: _refresh_exclusions()
		query.exclude = actor_exclusions
		var wall = gun.get_world_2d().direct_space_state.intersect_ray(query)
		batch.segments.append([from,wall.get("position",end)])
	get_tree().current_scene.add_child(batch)

func cone(gun, start: Vector2, direction: Vector2, context: Dictionary):
	var length = gun.effective.range
	var angle = gun.effective.angle
	var footprint = preload("res://game/effects/CombatFootprint.gd").polygon(start,length,direction,angle)
	for target in _monsters_for_frame():
		if not is_instance_valid(target) or target.is_queued_for_deletion(): continue
		var point = target.global_position+Vector2(0,-8)
		var offset = point-start
		if Geometry2D.is_point_in_polygon(point,footprint) and clear_line(start,point):
			hit(target,context)
			if context.has("burn"): heat_contact(point)
			if context.has("burn") and not target.is_die: target.apply_burn("thermal",context.burn,1.0,context)
	var edge = Array(footprint)
	edge.append(start)
	if context.has("burn"):
		# Refresh one visual per sustained gun; the hit/tick/footprint above is unchanged.
		if not is_instance_valid(gun.thermal_visual) or gun.thermal_visual.is_queued_for_deletion():
			gun.thermal_visual = load("res://game/effects/ThermalStream.gd").new()
			get_tree().current_scene.add_child(gun.thermal_visual)
		gun.thermal_visual.refresh_cone(edge,Color(1,0.5,0.2))
	else:
		trace(edge,Color(0.4,0.9,1),1.0)

func fragments(position: Vector2, angle: float, context: Dictionary, ignored, speed: float):
	for i in mini(3,context.get("shards",0)):
		var shard = load("res://game/bullets/SmpBullet.tscn").instantiate()
		shard.context = context.duplicate(true)
		shard.context.depth = 1
		shard.context.native_attack = false
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

var heat_cells: Dictionary = {}
var heat_created := 0
func heat_contact(point: Vector2):
	var key = Vector2i(floori(point.x/8.0),floori(point.y/8.0))
	if heat_cells.has(key):
		var existing = heat_cells[key].get_ref()
		if is_instance_valid(existing) and not existing.is_queued_for_deletion() and existing.epoch == LevelServer.epoch:
			existing.age = 0.0
			existing.global_position = point
			return
		heat_cells.erase(key)
	if heat_cells.size() >= 32: return
	var fx = load("res://game/effects/HeatContact.gd").new()
	fx.global_position = point
	get_tree().current_scene.add_child(fx)
	heat_cells[key] = weakref(fx)
	var identity = fx.get_instance_id()
	fx.tree_exiting.connect(func():
		var current = heat_cells.get(key)
		if current and is_instance_valid(current.get_ref()) and current.get_ref().get_instance_id() == identity: heat_cells.erase(key),CONNECT_ONE_SHOT)
	heat_created += 1

func arc(gun, start: Vector2, direction: Vector2, snapshot: Dictionary = {}):
	attacks += 1
	if snapshot.is_empty(): snapshot = gun.shot_context()
	var spec = WeaponCatalog.ARC
	var budget = mini(16,int(spec.targets)+maxi(0,int(gun.effective.jumps)-3))
	var candidates: Array = []
	var range_sq := float(gun.effective.range)*float(gun.effective.range)
	var link_range_sq := float(spec.link_range)*float(spec.link_range)
	# The graph is resolved synchronously, so positions and instance ids cannot change while
	# this list is used. Capture them once: the old sort comparator and every link candidate
	# re-read global_position, which made one held W112 shot pay the same property/native
	# boundary cost hundreds of times before doing any gameplay work.
	for target in _monsters_for_frame():
		if not is_instance_valid(target) or target.is_die or target.is_queued_for_deletion(): continue
		var target_position: Vector2 = target.global_position
		candidates.append([start.distance_squared_to(target_position),target,target_position+Vector2(0,-8),target.get_instance_id()])
	candidates.sort_custom(func(a,b): return a[0]<b[0])
	var visited = {}
	var queue = []
	var fx = load("res://game/effects/ArcDischarge.gd").new()
	# Resolve the entire bounded graph before damage can free a target.
	for candidate in candidates:
		if queue.size() >= int(spec.roots): break
		var target: BaseMonster = candidate[1]
		var p: Vector2 = candidate[2]
		var offset := p-start
		if offset.length_squared()>range_sq or absf(direction.angle_to(offset))>float(spec.root_angle) or not clear_line(start,p): continue
		queue.append({"target":target,"point":p,"from":start,"hop":0})
		visited[candidate[3]] = true
	var index = 0
	while index < queue.size() and queue.size()<budget:
		var parent = queue[index]; index += 1
		var children = 0
		for candidate in candidates:
			if queue.size()>=budget or children>=2: break
			if visited.has(candidate[3]): continue
			var target: BaseMonster = candidate[1]
			var p: Vector2 = candidate[2]
			if parent.point.distance_squared_to(p)>link_range_sq or not clear_line(parent.point,p): continue
			visited[candidate[3]] = true
			queue.append({"target":target,"point":p,"from":parent.point,"hop":parent.hop+1})
			children += 1
	for node in queue:
		var context = snapshot.duplicate(true)
		context.damage *= maxf(0.6,pow(0.9,node.hop))
		context.depth = 0 if node.hop==0 else 1
		context.native_attack = true
		context.attack_id = attacks
		if hit(node.target,context):
			fx.contacts.append(node.point)
			fx.edges.append([node.from,node.point])
	if queue.is_empty():
		var end = start+direction*minf(35,gun.effective.range)
		if clear_line(start,end): fx.edges.append([start,end])
	get_tree().current_scene.add_child(fx)

func fission(source, context: Dictionary):
	var gun = context.get("gun")
	if not is_instance_valid(gun) or not "120" in Demo.owned_global_upgrades or Demo.cooldown("A120") > 0: return
	if "straight" in gun.tags and "projectile" in gun.tags: return # Existing real fragments.
	var direction = gun.gun_tip.global_position.direction_to(source.global_position)
	var candidates = _monsters_for_frame().filter(func(t):
		return t != source and not t.is_die and source.global_position.distance_to(t.global_position)<=100.0 and direction.dot(source.global_position.direction_to(t.global_position))>=-0.1 and clear_line(source.global_position,t.global_position))
	if candidates.is_empty(): return
	candidates.sort_custom(func(a,b): return source.global_position.distance_squared_to(a.global_position)<source.global_position.distance_squared_to(b.global_position))
	Demo.talent_cooldowns.A120 = 0.4
	var derived = context.duplicate(true)
	derived.depth = 1; derived.native_attack = false; derived.crit = 0.0
	derived.damage = maxf(context.damage*0.35,context.get("link_damage",context.damage)*0.16)
	for target in candidates.slice(0,2):
		if hit(target,derived): trace([source.global_position,target.global_position],Color(0.65,1.0,0.8),2.0)
