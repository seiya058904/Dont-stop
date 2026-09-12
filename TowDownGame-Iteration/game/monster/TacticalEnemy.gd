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
func _ready():
	super._ready()
	var d = M5Content.definition(role)
	HP = d.hp; max_hp = HP; SPEED = d.speed; armor = d.get("armor",0.0)
	born_epoch = LevelServer.epoch
	is_boss = role.begins_with("B")
	sprite_body.scale = Vector2.ONE*(1.8 if is_boss else (1.15 if role in ["E03","E07","E09"] else 1.0))
	phase = "spawn"; phase_time = 0.7
	if is_boss:
		var hull = CircleShape2D.new(); hull.radius = 11
		$CollisionShape2D.shape = hull; $CollisionShape2D.position = Vector2(0,-2)
		var title = Label.new(); title.text = d.name; title.position = Vector2(-22,-47); title.add_theme_font_size_override("font_size",8); add_child(title)
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
	get_tree().current_scene.add_child(node)
	owned_attacks.append(weakref(node))
	remember(kind)
	return node
func shot(dir: Vector2, speed_value = 100.0):
	var node = CharacterBody2D.new(); node.set_script(load("res://game/monster/EnemyShot.gd"))
	node.position = global_position; node.velocity = dir*speed_value; node.owner_ref = weakref(self)
	get_tree().current_scene.add_child(node); owned_attacks.append(weakref(node)); remember("shot")
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
	phase = "warn"; phase_time = 0.7
	match role:
		"E03","E11": zone("line",global_position,150.0,0.7).damage = 0
		"E06": zone("circle",global_position,42.0,0.8).damage = 0; phase_time = 0.8
		"E07","E08": pass
		"E09","E12": zone("cone",global_position,52.0,0.7)
		"E10":
			if attack_index%2: zone("line",global_position,260.0,0.9).damage = 0; phase_time = 0.9
			else: zone("circle",locked_point,36.0,1.0); phase_time = 1.0
		"B01":
			if attack_index%3 == 1: zone("line",global_position,150.0,0.7).damage = 0
			elif attack_index%3 == 2: zone("cone",global_position,100,0.7)
		"B02":
			if attack_index%3 == 0: zone("circle",locked_point,58.0,1.0)
		"B03":
			if attack_index%3 == 1: zone("line",global_position,330.0,0.9,0.65).sweep = 0.45 if phase_two else 0.3; phase_time = 0.9
			elif attack_index%3 == 2:
				locked_direction = locked_direction.orthogonal()*(1 if attack_index%2 else -1)
				zone("line",global_position,160.0,0.7).damage = 0
func perform_attack():
	remember("attack")
	phase = "recover"; phase_time = 1.0 if not phase_two else 0.7
	match role:
		"E03","E11": phase = "dash"; phase_time = 0.4 if role == "E03" else 0.25
		"E06":
			if global_position.distance_to(Utils.player.global_position) <= 42 and Combat.clear_line(global_position,Utils.player.global_position): Utils.player.onHit(1,self)
			remember("detonate"); last_context = {"depth":1}; onDie()
		"E07": summon(1); phase_time = 3.0
		"E08":
			var healed = 0
			for other in get_tree().get_nodes_in_group("monsters"):
				if other == self or other.is_die or other.is_boss or other.get_meta("content_id","") == "E08": continue
				var id = other.get_instance_id()
				if global_position.distance_to(other.global_position) > 130 or not Combat.clear_line(global_position,other.global_position): continue
				var maximum = M5Content.definition(other.get_meta("content_id","E01")).get("hp",2.0)
				var amount = minf(1.0,minf(maximum-other.HP,3.0-heal_budget.get(id,0.0)))
				if amount <= 0: continue
				other.HP += amount; heal_budget[id] = heal_budget.get(id,0.0)+amount; remember("heal"); Combat.trace([global_position,other.global_position],Color(0.3,1,0.6)); healed += 1
				if healed == 2: break
			phase_time = 2.2
		"E10":
			if attack_index%2: shot(locked_direction,220)
			phase_time = 1.4
		"B01":
			if attack_index%3 == 1: phase = "dash"; phase_time = 0.55
			elif attack_index%3 == 2: pass
			else: summon(2); phase_time = 1.4
		"B02":
			if attack_index%3 == 1: summon(3,"E07" if phase_two else "E02")
			elif attack_index%3 == 2: fan(7 if phase_two else 5,1.1,80)
			phase_time = 1.5
		"B03":
			if attack_index%3 == 2:
				phase = "dash"; phase_time = 0.45
			elif attack_index%3 == 0:
				for i in 12: shot(Vector2.RIGHT.rotated(i*TAU/12),70)
				if phase_two: summon(2)
func _physics_process(delta):
	if is_die: return
	if born_epoch != LevelServer.epoch: queue_free(); return
	if LevelServer.state != "COMBAT" or not is_instance_valid(Utils.player) or Utils.player.is_dead: return
	phase_time -= delta; contact_cooldown = maxf(0,contact_cooldown-delta); queue_redraw()
	if state_array.has(Utils.STATE_TYPE.STUN): return
	if hit: move_and_slide(); return
	if role == "E07" and summoned:
		if phase == "spawn" and phase_time > 0: return
		move_towards(Utils.player.global_position,delta)
		if global_position.distance_to(Utils.player.global_position)<18 and contact_cooldown<=0:
			Utils.player.onHit(1,self); contact_cooldown=0.9; remember("contact")
		return
	owned_attacks = owned_attacks.filter(func(ref): return is_instance_valid(ref.get_ref()))
	if is_boss and HP <= max_hp*0.5 and not phase_two:
		phase_two = true; phase = "recover"; phase_time = 1.1; remember("phase_two")
		for ref in owned_attacks:
			if is_instance_valid(ref.get_ref()): ref.get_ref().queue_free()
	if phase == "spawn" or phase == "recover":
		if phase_time <= 0: phase = "move"; phase_time = 0.5
		return
	if phase == "warn":
		if phase_time <= 0: perform_attack()
		return
	if phase == "dash":
		var previous = global_position; velocity = locked_direction*(210 if is_boss else 195); move_and_slide(); travelled += previous.distance_to(global_position)
		if global_position.distance_to(Utils.player.global_position) < 22 and contact_cooldown <= 0: Utils.player.onHit(1,self); contact_cooldown = 1.0; remember("contact")
		if phase_time <= 0 or get_slide_collision_count() > 0: phase = "recover"; phase_time = 1.0; remember("dash_end")
		return
	var distance = global_position.distance_to(Utils.player.global_position)
	facing = facing.rotated(clampf(facing.angle_to(global_position.direction_to(Utils.player.global_position)),-delta*1.6,delta*1.6))
	var point = Utils.player.global_position
	if role in ["E07","E08","E10","B02"]:
		if distance < 115: point = global_position+(global_position-Utils.player.global_position).normalized()*70
		elif distance < 210: point = global_position
	elif role in ["E11","B03"] and distance > 70: point = Utils.player.global_position+facing.orthogonal()*85
	move_towards(point,delta)
	var reach = 42 if role in ["E09","E12"] else (35 if role == "E06" else 260)
	if role == "E11": reach = 120
	if distance < reach and phase_time <= 0 and Combat.clear_line(global_position,Utils.player.global_position): choose_attack()
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
