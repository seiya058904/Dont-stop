extends Node

var actor_exclusions: Array[RID] = []
var dispatch_depth = 0
var attacks = 0
var damage_events = 0
var kill_events = 0
var max_depth_seen = 0
var audio_pool: Array = []
var sound_clock = 0.0
var reduced_flash = false

func _ready():
	for i in 8:
		var player = AudioStreamPlayer2D.new()
		player.bus = "SFX"
		player.volume_db = -15
		add_child(player)
		audio_pool.append(player)

func _physics_process(_delta):
	actor_exclusions.clear()
	if is_instance_valid(Utils.player): actor_exclusions.append(Utils.player.get_rid())
	for actor in get_tree().get_nodes_in_group("monsters"): actor_exclusions.append(actor.get_rid())

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
	var critical = depth == 0 and randf() < context.get("crit",0.0)
	if critical: amount *= 1.5
	var old_depth = dispatch_depth
	dispatch_depth = depth + 1
	var rewards = get_tree().get_nodes_in_group("reward")
	if depth == 0:
		for reward in rewards:
			if reward.connect_beforeAtk: amount += reward.beforeAtk(target,amount)
	amount = snappedf(amount,0.01)
	damage_events += 1
	target.receive_damage(amount, critical, context)
	if depth == 0 and not target.is_die:
		for reward in rewards:
			if reward.connect_afterAtk: reward.afterAtk(target,amount)
	dispatch_depth = old_depth
	return true

func clear_line(from: Vector2, to: Vector2) -> bool:
	if not is_instance_valid(Utils.player): return false
	var query = PhysicsRayQueryParameters2D.create(from,to,2147483649)
	var actors = get_tree().get_nodes_in_group("monsters")
	if actor_exclusions.size() != actors.size()+1:
		actor_exclusions = [Utils.player.get_rid()]
		for actor in actors: actor_exclusions.append(actor.get_rid())
	query.exclude = actor_exclusions
	return Utils.player.get_world_2d().direct_space_state.intersect_ray(query).is_empty()

func explosion(position: Vector2, radius: float, damage: float, gun = null, depth = 0):
	if depth > DemoConfig.MAX_DERIVATION: return
	var context = {"damage":damage,"depth":depth,"epoch":LevelServer.epoch,"gun":gun}
	if is_instance_valid(gun):
		context = gun.damage_context(depth)
		context.damage = damage
	explosion_context(position,radius,context)

func explosion_context(position: Vector2, radius: float, context: Dictionary):
	if context.get("depth",0) > DemoConfig.MAX_DERIVATION: return
	for target in get_tree().get_nodes_in_group("monsters"):
		if not target.is_die and position.distance_to(target.global_position) <= radius and clear_line(position,target.global_position):
			hit(target,context)
	var effect = Node2D.new()
	effect.set_script(load("res://game/effects/CombatEffect.gd"))
	effect.radius = radius
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
	for target in get_tree().get_nodes_in_group("monsters"):
		var point = target.global_position+Vector2(0,-8)
		var offset = point-start
		if offset.length() <= length and absf(direction.angle_to(offset)) <= angle and clear_line(start,point):
			hit(target,context)
			if context.has("burn") and not target.is_die: target.apply_burn("thermal",context.burn,1.0,context)
	var edge = [start]
	for i in 9: edge.append(start+direction.rotated(lerpf(-angle,angle,i/8.0))*length)
	edge.append(start)
	trace(edge,Color(1,0.5,0.2) if context.has("burn") else Color(0.4,0.9,1),1.0)

func arc(gun, start: Vector2, direction: Vector2):
	attacks += 1
	var query = PhysicsRayQueryParameters2D.create(start,start+direction*320,2147483651)
	query.exclude = [Utils.player.get_rid()]
	var hit_result = gun.get_world_2d().direct_space_state.intersect_ray(query)
	var points: Array[Vector2] = [start]
	var target = hit_result.get("collider")
	if not target is BaseMonster:
		points.append(hit_result.get("position",start+direction*320))
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
