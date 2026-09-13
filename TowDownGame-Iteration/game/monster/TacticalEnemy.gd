extends "res://game/monster/DemoEnemy.gd"

var summoned = false
var born_epoch = 0
var max_hp = 1.0
var armor = 0.0
var facing = Vector2.LEFT
var attack_index = 0
var actions: Dictionary = {}
var phase_two = false
var heal_budget: Dictionary = {}
var children_ids: Array[int] = []
var owned_attacks: Array[WeakRef] = []
var locked_point = Vector2.ZERO
var summon_total = 0
var travelled = 0.0
var movement_clock = 0.0
var orbit_side = 1.0
var desired_point = Vector2.ZERO
var dash_speed = 300.0
var dash_seconds = 0.5
var dash_clock = 0.0
var phase_flash = 0.0
var attack_kind = ""
var phase_label: Label

func _ready():
	super._ready()
	var d = M5Content.definition(role)
	HP = d.hp; max_hp = HP; SPEED = d.speed; armor = d.get("armor",0.0)
	born_epoch = LevelServer.epoch
	orbit_side = 1.0 if get_instance_id()%2 else -1.0
	is_boss = role.begins_with("B")
	sprite_body.scale = Vector2.ONE*(1.8 if is_boss else (1.15 if role in ["E03","E07","E09"] else 1.0))
	phase = "spawn"; phase_time = 0.3
	if is_boss:
		var hull = CircleShape2D.new(); hull.radius = 11
		$CollisionShape2D.shape = hull; $CollisionShape2D.position = Vector2(0,-2)
		var title = Label.new(); phase_label = title; title.text = d.name+" · I"; title.position = Vector2(-22,-47); title.add_theme_font_size_override("font_size",8); add_child(title)
func remember(action: String):
	actions[action] = actions.get(action,0)+1
func move_towards(point: Vector2, delta: float, multiplier = 1.0):
	path_refresh -= delta
	if path_refresh <= 0 or global_position.distance_to(cached_step) < 6:
		cached_step = LevelServer.town.path_step(global_position,point) if is_instance_valid(LevelServer.town) else point
		path_refresh = 0.2
	velocity = global_position.direction_to(cached_step)*SPEED*multiplier*(1.0-slow_amount if slow_time > 0 else 1.0)
	var previous = global_position; move_and_slide(); travelled += previous.distance_to(global_position)
	anim.play("run" if velocity.length() > 1 else "idle")
func zone(kind: String, point: Vector2, reach: float, delay: float, time = 0.12):
	var node = load("res://game/monster/HostileZone.gd").new()
	node.mode = kind; node.radius = reach; node.length = reach; node.warning = delay; node.duration = time; node.direction = locked_direction; node.owner_ref = weakref(self)
	node.position = point
	if kind == "charge": node.width = 22 if is_boss else 18
	get_tree().current_scene.add_child(node)
	owned_attacks.append(weakref(node))
	remember(kind)
	return node
func shot(dir: Vector2, speed_value = 100.0, damage_value = 1.0, muzzle_flash = true) -> bool:
	if get_tree().get_nodes_in_group("enemy_projectiles").size() >= 180: return false
	var node = CharacterBody2D.new(); node.set_script(load("res://game/monster/EnemyShot.gd"))
	node.position = global_position; node.velocity = dir*speed_value; node.owner_ref = weakref(self)
	node.damage = damage_value
	get_tree().current_scene.add_child(node); owned_attacks.append(weakref(node)); remember("shot")
	if muzzle_flash: preload("res://game/effects/HostileVFX.gd").emit_at(get_tree().current_scene,global_position,12,dir)
	return true
func barrage(kind: String, count: int, waves: int, speed_value: float, spread_value = 0.85):
	var pattern = preload("res://game/monster/EnemyBarrage.gd").new()
	pattern.owner_ref = weakref(self); pattern.heading = locked_direction
	pattern.kind = kind; pattern.count = count; pattern.waves = waves
	pattern.speed = speed_value; pattern.spread = spread_value
	pattern.shift = 0.12*orbit_side
	get_tree().current_scene.add_child(pattern); owned_attacks.append(weakref(pattern))
func fan(count: int, spread: float, speed_value = 85.0):
	for i in count: shot(locked_direction.rotated(lerpf(-spread,spread,i/float(maxi(1,count-1)))),speed_value)
func summon(count: int, id = "E02"):
	children_ids = children_ids.filter(func(instance): return is_instance_id_valid(instance))
	if summoned: return
	var cap = 8 if is_boss else 3
	for i in count:
		if children_ids.size() >= cap or summon_total >= (24 if is_boss else 3): break
		if get_tree().get_nodes_in_group("monsters").filter(func(m): return not m.is_die).size() >= 70: break
		var point = LevelServer.town.spawn_near(global_position,60.0,95.0)
		if point == Vector2.INF: continue
		var child = M5Content.spawn(id,get_parent(),point,true)
		if child:
			children_ids.append(child.get_instance_id()); summon_total += 1; remember("summon")
func choose_attack():
	attack_index += 1
	locked_direction = global_position.direction_to(Utils.player.global_position)
	locked_point = Utils.player.global_position
	var distance = global_position.distance_to(locked_point)
	phase = "warn"; phase_time = 0.65 if not phase_two else 0.5
	var delay = phase_time
	match role:
		"E03","E11":
			dash_speed = 265 if role == "E03" else 310
			dash_seconds = clampf((distance+25)/dash_speed,0.25,0.8)
			zone("charge",global_position,dash_speed*dash_seconds,delay).damage = 0
			attack_kind = "charge"
		"E06":
			zone("circle",global_position,42,0.8).damage = 0; phase_time = 0.8; attack_kind = "detonate"
		"E07","E08": attack_kind = "summon" if role == "E07" else "heal"
		"E09","E12": zone("cone",global_position,60,delay); attack_kind = "cone"
		"E10":
			if attack_index%2:
				zone("line",global_position,280,0.85,0.3); phase_time = 0.85; attack_kind = "beam"
			else: zone("circle",locked_point,40,0.95); phase_time = 0.95; attack_kind = "artillery"
		"B01":
			match attack_index%3:
				1:
					dash_speed = 330 if phase_two else 290
					dash_seconds = clampf((distance+55)/dash_speed,0.4,0.95)
					zone("charge",global_position,dash_speed*dash_seconds,delay).damage = 0; attack_kind = "charge"
				2: zone("cone",global_position,125,delay).angle = 0.95; attack_kind = "cleave"
				0: zone("circle",global_position,100 if phase_two else 85,delay); attack_kind = "slam"
		"B02":
			match attack_index%3:
				1:
					# A summon signal, not a damaging AoE or a promise of exact spawn positions.
					zone("summon",global_position,42 if phase_two else 34,delay).damage = 0
					attack_kind = "brood"
				2:
					zone("circle",locked_point,65,0.95)
					zone("circle",locked_point+Utils.player.velocity.limit_length(85)*0.7,48,1.35)
					if phase_two: zone("circle",locked_point-locked_direction.orthogonal()*80,45,1.55)
					phase_time = 0.95; attack_kind = "lockdown"
				0: zone("cone",global_position,160,delay).angle = 0.9; attack_kind = "pulse"
		"B03":
			match attack_index%3:
				1:
					dash_speed = 440
					var intercept = locked_point+Utils.player.velocity.limit_length(100)*0.25
					locked_direction = global_position.direction_to(intercept)
					dash_seconds = clampf(global_position.distance_to(intercept)/dash_speed,0.24,0.65)
					zone("charge",global_position,dash_speed*dash_seconds,delay).damage = 0; attack_kind = "dash"
				2:
					locked_direction = locked_direction.rotated(-orbit_side*0.25)
					zone("line",global_position,330,0.9,0.85).sweep = orbit_side*(1.3 if phase_two else 1.0)
					phase_time = 0.9; attack_kind = "sweep"
				0:
					zone("cone",global_position,240,delay).damage = 0; attack_kind = "burst"
	remember("windup_"+attack_kind)

func perform_attack():
	remember("attack"); remember(attack_kind)
	preload("res://game/effects/HostileVFX.gd").emit_at(get_tree().current_scene,global_position,24 if is_boss else 12,locked_direction)
	phase = "recover"; phase_time = 0.75 if not phase_two else 0.45
	match role:
		"E03","E11":
			phase = "dash"; phase_time = dash_seconds
			if role == "E11" and is_elite: barrage("fan",3,1,110,0.65)
		"E06":
			if global_position.distance_to(Utils.player.global_position)<=42 and Combat.clear_line(global_position,Utils.player.global_position): Utils.player.onHit(1,self)
			last_context = {"depth":1}; onDie()
		"E07": summon(1); phase_time = 2.0
		"E08":
			var healed = 0
			for other in get_tree().get_nodes_in_group("monsters"):
				if other == self or other.is_die or other.is_boss or other.get_meta("content_id","") == "E08": continue
				var id = other.get_instance_id()
				if global_position.distance_to(other.global_position)>155 or not Combat.clear_line(global_position,other.global_position): continue
				var maximum = M5Content.definition(other.get_meta("content_id","E01")).get("hp",2.0)
				var amount = minf(1.0,minf(maximum-other.HP,3.0-heal_budget.get(id,0.0)))
				if amount<=0: continue
				other.HP += amount; heal_budget[id] = heal_budget.get(id,0.0)+amount; remember("heal")
				Combat.trace([global_position,other.global_position],Color(0.3,1,0.6)); healed += 1
				if healed == 2: break
			phase_time = 1.7
		"E10":
			phase_time = 0.9
			if attack_kind == "artillery": barrage("fan",5,1,100,0.8)
		"B01":
			if attack_kind == "charge": phase = "dash"; phase_time = dash_seconds
			elif attack_kind == "slam": barrage("ring",16 if phase_two else 12,2 if phase_two else 1,95)
		"B02":
			if attack_kind == "brood":
				summon(3,"E06" if phase_two else "E02")
				barrage("ring",24 if phase_two else 20,3 if phase_two else 2,100)
			elif attack_kind == "pulse": barrage("fan",19 if phase_two else 15,3 if phase_two else 2,115,1.25)
			phase_time = 1.0 if not phase_two else 0.65
		"B03":
			if attack_kind == "dash": phase = "dash"; phase_time = dash_seconds
			elif attack_kind == "burst": barrage("fan",13 if phase_two else 9,3 if phase_two else 2,145,0.9)

func _physics_process(delta):
	if is_die: return
	if born_epoch != LevelServer.epoch: queue_free(); return
	if LevelServer.state != "COMBAT" or not is_instance_valid(Utils.player) or Utils.player.is_dead: velocity = Vector2.ZERO; return
	phase_time -= delta; contact_cooldown = maxf(0,contact_cooldown-delta); phase_flash = maxf(0,phase_flash-delta); queue_redraw()
	if state_array.has(Utils.STATE_TYPE.STUN): return
	if hit: move_and_slide(); return
	owned_attacks = owned_attacks.filter(func(ref): return is_instance_valid(ref.get_ref()))
	if is_boss and HP<=max_hp*0.5 and not phase_two:
		phase_two = true; phase = "transition"; phase_time = 1.0; phase_flash = 1.0; remember("phase_two")
		phase_label.text = M5Content.definition(role).name+" · PHASE II"
		for ref in owned_attacks:
			if is_instance_valid(ref.get_ref()): ref.get_ref().queue_free()
		orbit_side *= -1
		if role == "B01": summon(2,"E09")
	if phase == "spawn" or phase == "transition":
		if phase == "spawn": move_towards(Utils.player.global_position,delta,0.8)
		if phase_time<=0: phase = "move"; phase_time = 0.3
		return
	if phase == "warn":
		velocity = Vector2.ZERO
		if phase_time<=0: perform_attack()
		return
	if phase == "dash":
		var previous = global_position; velocity = locked_direction*dash_speed; move_and_slide(); travelled += previous.distance_to(global_position)
		dash_clock += delta
		if dash_clock>0.08:
			dash_clock = 0; preload("res://game/effects/HostileVFX.gd").emit_at(get_tree().current_scene,previous,10,locked_direction)
		contact(24)
		if phase_time<=0 or get_slide_collision_count()>0: phase = "recover"; phase_time = 0.5; remember("dash_end"); orbit_side *= -1
		return
	var distance = global_position.distance_to(Utils.player.global_position)
	facing = facing.rotated(clampf(facing.angle_to(global_position.direction_to(Utils.player.global_position)),-delta*2.8,delta*2.8))
	movement_clock -= delta
	if movement_clock<=0:
		movement_clock = 0.25; desired_point = movement_target(distance)
	move_towards(desired_point,delta,1.15 if is_boss and (phase_two or distance>190) else 1.0)
	if role not in ["E08","E10"]: contact(24 if is_boss else 19)
	if phase == "recover":
		if phase_time<=0: phase = "move"; phase_time = 0.15
		return
	if role == "E07" and summoned: return
	var reach = 240.0
	if role in ["E09","E12"]: reach = 55
	elif role == "E06": reach = 34
	elif role == "E11": reach = 125
	elif role == "B01": reach = 260 if (attack_index+1)%3==1 else 95
	elif role == "B02": reach = 240 if (attack_index+1)%3!=0 else 145
	if distance<reach and phase_time<=0 and Combat.clear_line(global_position,Utils.player.global_position): choose_attack()

func contact(reach: float):
	if global_position.distance_to(Utils.player.global_position)<reach and contact_cooldown<=0:
		Utils.player.onHit(1,self); contact_cooldown = 0.85; remember("contact")

func movement_target(distance: float) -> Vector2:
	var player = Utils.player.global_position
	var radial = player.direction_to(global_position)
	if role == "E08":
		var ally = null; var best = 240.0
		for other in get_tree().get_nodes_in_group("monsters"):
			if other == self or other.is_die or other.get_meta("content_id","") in ["E08","E10"]: continue
			var d = other.global_position.distance_to(player)
			if d<best: best = d; ally = other
		if ally and distance>65: return ally.global_position+radial*40+radial.orthogonal()*orbit_side*25
		return player+radial.rotated(orbit_side*0.65)*90
	if role == "E10":
		return player+radial.rotated(orbit_side*0.6)*145 if distance<190 else player
	if role == "E07":
		return player+radial.rotated(orbit_side*0.6)*70 if not summoned and distance<130 else player
	if role in ["E11","B03"]:
		if distance>145 or not Combat.clear_line(global_position,player): return player
		return player+radial.rotated(orbit_side*0.9)*(45 if phase_two or role == "E11" else 70)
	if role == "B02":
		return player if attack_index%3 == 2 or phase_two else player+radial.rotated(orbit_side*0.7)*95
	if role == "E09":
		# A broad pushing front with alternating sides instead of a single-file queue.
		return player+radial.orthogonal()*orbit_side*minf(32,distance*0.15)
	return player

func receive_damage(amount: float, critical: bool, context: Dictionary):
	if armor > 0:
		var source = context.get("impact_origin",Utils.player.global_position)
		var protected = role != "E09" or absf(facing.angle_to(global_position.direction_to(source))) < 1.05
		if protected:
			armor = maxf(0,armor-amount); amount *= 0.45; remember("armor_hit")
			if armor == 0: remember("armor_break"); flash_time = 0.15
	super.receive_damage(amount,critical,context)
func onDie(effects = true):
	if is_die: return
	for ref in owned_attacks:
		if is_instance_valid(ref.get_ref()): ref.get_ref().queue_free()
	if LevelServer.state == "COMBAT" and born_epoch == LevelServer.epoch:
		if role == "E07" and not summoned: summon(2)
		if role == "E12" and last_context.get("depth",0) < DemoConfig.MAX_DERIVATION:
			var blast = load("res://game/monster/HostileZone.gd").new(); blast.radius = 58; blast.warning = 0.08; blast.position = global_position
			blast.friendly_context = {"damage":4.0,"depth":last_context.get("depth",0)+1,"epoch":born_epoch}
			get_tree().current_scene.add_child(blast)
	if is_boss:
		for id in children_ids:
			var child = instance_from_id(id)
			if is_instance_valid(child): child.queue_free()
	super.onDie(effects)
	if is_boss: LevelServer.boss_defeated.call_deferred(born_epoch)
func _draw():
	super._draw()
	if is_die: return
	var color = Color(0.4,0.9,1) if armor <= 0 else Color(1,0.8,0.3)
	if role in ["E03","E09","B01"]:
		var dir = facing.angle(); draw_arc(Vector2(0,-7),18 if not is_boss else 28,dir-1.05,dir+1.05,12,color,3)
	if role == "E08": draw_line(Vector2(-5,-26),Vector2(5,-26),Color(0.3,1,0.6),2); draw_line(Vector2(0,-31),Vector2(0,-21),Color(0.3,1,0.6),2)
	if role == "E07": draw_arc(Vector2(0,-18),9,0,TAU,6,Color(0.6,0.8,1),2)
	if role == "E06": draw_circle(Vector2(0,-22),4,Color(1,0.3+0.2*sin(phase_time*25),0.1))
	if role == "E10": draw_line(Vector2(0,-18),facing*17+Vector2(0,-18),Color(1,0.7,0.3),2)
	if role == "E11": draw_polyline(PackedVector2Array([Vector2(-10,-20),Vector2(0,-27),Vector2(10,-20)]),Color(0.8,0.4,1),2)
	if role == "E12": draw_circle(Vector2(0,-20),5,Color(0.2,0.9,1))
	if is_boss:
		draw_rect(Rect2(-27,-37,54,4),Color(0.1,0.1,0.1)); draw_rect(Rect2(-27,-37,54*maxf(0,HP/max_hp),4),Color(1,0.4,0.2) if phase_two else Color(0.9,0.8,0.3))
		draw_line(Vector2(0,-38),Vector2(0,-32),Color(0.05,0.04,0.02),2)
		if phase_two: draw_arc(Vector2(0,-8),30,0,TAU,36,Color(1,0.4,0.12,0.65),2,true)
