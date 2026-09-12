extends "res://tests/M3Weapons.gd"
var play_view: SubViewport
var driving = false
var moving = true
var target_boss = false
var shots_fired = 0
var movement = 0.0
var bot_clock = 0.0
var last_position = Vector2.ZERO
var dash_cooldown = 0.0
func boot():
	Demo.test_mode = true; seed(808)
	play_view = SubViewport.new(); play_view.size = Vector2i(410,230); play_view.world_2d = get_viewport().world_2d
	play_view.render_target_update_mode = SubViewport.UPDATE_ALWAYS if DisplayServer.get_name() != "headless" else SubViewport.UPDATE_DISABLED
	add_child(play_view); play_view.add_child(load("res://game/map/Main.tscn").instantiate()); Utils.gameStart(); await wait(0.3)
	PlayerData.gold = 100000; PlayerData.reward_point = 9999
func dismiss():
	for menu in Demo.pause_stack.duplicate(): Demo.pop_pause(menu); menu.queue_free()
func stop():
	driving = false
	for action in ["shoot","left","right","up","down","dash"]: Input.action_release(action)
	Demo.stop_attacks()
func configure(gun_id: int, full = false):
	LevelServer.state = "CAMP"
	if not PlayerData.player_weapon_list.has(gun_id): Demo.try_purchase("weapon",str(gun_id))
	if full:
		for id in Utils.am_dict: Demo.try_purchase("attachment",id)
		for id in DemoConfig.TALENTS:
			while Demo.rank(id) < DemoConfig.TALENTS[id].max: Demo.try_purchase("talent",id,"points")
	Utils.player.changeWeapon(gun_id)
	var gun = Utils.player.gun
	# M7 comparison retains its legal one-per-slot installation; M8 needs none.
	if Demo.get("owned_global_upgrades") == null:
		for am in PlayerData.player_am_list.values(): gun.addAttachMent(am)
	gun.set_process(false); gun.set_physics_process(false)
	gun.bullets_count = gun.bullets_max_count; PlayerData.reserve_magazines = 100
	PlayerData.player_hp = PlayerData.player_hp_max
	last_position = Utils.player.global_position
func fire_at(point: Vector2, delta: float):
	var gun = Utils.player.gun
	gun.set_process(false); gun.set_physics_process(false)
	var motion = InputEventMouseMotion.new(); motion.position = play_view.get_canvas_transform()*point; play_view.push_input(motion,true)
	gun.look_at(point); gun.direction = gun.gun_tip.global_position.direction_to(point)
	var before = gun.bullets_count
	if gun.weapon_id == 113:
		gun.handle_charge(not (gun.charging and gun.charge_time >= gun.effective.warmup),delta)
	elif gun.weapon_id == 116: gun.handle_thermal(true,delta)
	else:
		if gun.weapon_id == 124: gun.drive_spin(not gun.is_reloading,delta)
		if gun.can_shoot and not gun.is_reloading:
			if gun.bullets_count == 0: gun.reload_ammo()
			else: gun._shoot(); gun.can_shoot = false; gun.timer.start()
	if gun.bullets_count < before: shots_fired += 1
func _process(delta):
	if not driving or get_tree().paused or not is_instance_valid(Utils.player) or Utils.player.is_dead or LevelServer.state != "COMBAT": return
	dash_cooldown = maxf(0,dash_cooldown-delta)
	var actors = get_tree().get_nodes_in_group("monsters").filter(func(a): return not a.is_die and not a.is_queued_for_deletion())
	if actors.is_empty(): return
	actors.sort_custom(func(a,b): return a.global_position.distance_squared_to(Utils.player.global_position)<b.global_position.distance_squared_to(Utils.player.global_position))
	var target = actors[0]
	if target_boss:
		var boss = instance_from_id(LevelServer.boss_instance)
		if is_instance_valid(boss) and not boss.is_die: target = boss
	var aim_target = target
	if target_boss and actors[0]!=target and actors[0].global_position.distance_to(Utils.player.global_position)<95:
		aim_target = actors[0]
	var aim_point = aim_target.global_position-Vector2(0,8)
	if target_boss and Utils.player.gun.weapon_id == 117:
		var flight = Utils.player.global_position.distance_to(aim_target.global_position)/Utils.player.gun.effective.projectile_speed
		aim_point += aim_target.velocity*minf(flight,0.5)
	fire_at(aim_point,delta)
	movement += last_position.distance_to(Utils.player.global_position); last_position = Utils.player.global_position
	bot_clock += delta
	if bot_clock < 0.1: return
	bot_clock = 0
	var direction = Vector2.ZERO
	var offset = target.global_position-Utils.player.global_position
	if moving:
		if offset.length()>110 or not Combat.clear_line(Utils.player.global_position,target.global_position):
			var step = LevelServer.town.path_step(Utils.player.global_position,target.global_position)
			direction = Utils.player.global_position.direction_to(step)
		elif offset.length()<65: direction = -offset.normalized().rotated(0.5)
		else: direction = offset.normalized().orthogonal()*0.7
		if target_boss and target.is_boss:
			var best = -INF
			var wanted = direction
			var zones = get_tree().get_nodes_in_group("hostile_zone")
			# Choose actual movement inputs with wall/telegraph lookahead; no teleport or invulnerability.
			for i in 16:
				var candidate = Vector2.RIGHT.rotated(i*TAU/16)
				if Utils.player.test_move(Utils.player.global_transform,candidate*24): continue
				var next = Utils.player.global_position+candidate*38
				var score = candidate.dot(wanted)*1.5
				# Keep a firing lane instead of circling indefinitely behind an arena column.
				if not Combat.clear_line(next,target.global_position): score -= 3
				if is_instance_valid(LevelServer.town.arena):
					var local = LevelServer.town.arena.to_local(next)
					if absf(local.x)>320 or absf(local.y)>230: score -= 1.5
				for actor in actors:
					var distance = next.distance_to(actor.global_position)
					if distance<62: score -= (62-distance)*0.2
				for zone in zones:
					if zone.damage<=0 and zone.mode not in ["charge","circle"]: continue
					var relative = next-zone.global_position
					var danger = relative.length()<zone.radius+16
					if zone.mode in ["line","charge"]:
						danger = Geometry2D.get_closest_point_to_segment(next,zone.global_position,zone.global_position+zone.direction*zone.length).distance_to(next)<zone.width+18
					elif zone.mode=="cone": danger = relative.length()<zone.radius+16 and absf(zone.direction.angle_to(relative))<zone.angle+0.15
					if danger:
						# A graded exit distance still chooses an escape when every nearby sample is inside.
						var depth = maxf(0,zone.radius+16-relative.length())
						if zone.mode == "cone": depth = minf(depth,relative.length()*maxf(0,zone.angle+0.15-absf(zone.direction.angle_to(relative))))
						elif zone.mode in ["line","charge"]: depth = zone.width+18-Geometry2D.get_closest_point_to_segment(next,zone.global_position,zone.global_position+zone.direction*zone.length).distance_to(next)
						score -= 8+depth*0.6
				for shot in get_tree().get_nodes_in_group("combat_transient"):
					if shot.get_script() and shot.get_script().resource_path == "res://game/monster/EnemyShot.gd":
						if Geometry2D.get_closest_point_to_segment(next,shot.global_position,shot.global_position+shot.velocity*0.3).distance_to(next)<18: score -= 4
				if score>best: best=score; direction=candidate
	for pair in [["left",direction.x < -0.2],["right",direction.x > 0.2],["up",direction.y < -0.2],["down",direction.y > 0.2]]:
		if pair[1]: Input.action_press(pair[0])
		else: Input.action_release(pair[0])
	if target_boss and target.is_boss and dash_cooldown<=0 and actors[0].global_position.distance_to(Utils.player.global_position)<65:
		dash_cooldown = 0.85
		Input.action_press("dash")
		var event = InputEventAction.new(); event.action = "dash"; event.pressed = true
		Utils.player._input(event)
		Input.action_release("dash")
