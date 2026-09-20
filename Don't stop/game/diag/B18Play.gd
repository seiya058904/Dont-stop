extends "res://game/diag/B18Run.gd"
# Normal HP diagnostic: same legal purchases and real input as the product.
# No HP refill, forced phase, forced kill, enemy removal or hidden immunity.
var movement_mode := "avoid"
var steering_clock := 0.0

func run():
	stop_boss_at_limit = false
	Demo.test_mode = true
	for arg in OS.get_cmdline_args()+OS.get_cmdline_user_args():
		if arg.begins_with("--b18-normal="): movement_mode = arg.substr(13)
	await get_tree().create_timer(3.0).timeout
	await _boot_to_camp()
	_grant_everything()
	var weapon = presentation_weapons[0] if not presentation_weapons.is_empty() else 112
	Utils.player.changeWeapon(weapon)
	await release_after_switch()
	seed(run_seed)
	load("res://game/map/ArenaHazardDirector.gd").fixed_seed = run_seed
	var departed = LevelServer.town.depart(stage,true)
	Utils.set_gameplay_mouse_mode()
	await release_after_switch()
	print("[stress] round=1 depart=",departed," state=",LevelServer.state)
	var started = Time.get_ticks_msec()
	var previous = Time.get_ticks_usec()
	var start_hp = PlayerData.player_hp
	_rounds = 1
	while LevelServer.state == "COMBAT" and not Utils.player.is_dead and simulation < seconds and Time.get_ticks_msec()-started < (seconds+60)*1000:
		Input.action_press("shoot")
		_drive_movement(Time.get_ticks_msec())
		await get_tree().process_frame
		var now = Time.get_ticks_usec()
		_ms.append((now-previous)/1000.0); previous = now
		_phys.append(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)*1000)
		_proc.append(Performance.get_monitor(Performance.TIME_PROCESS)*1000)
		_draws.append(int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)))
		_flags.append(0); _beams.append(0); _combat_seconds.append(simulation); _round_of.append(1)
		_sample_gauges()
	_total_combat_s = simulation
	for action in ["shoot","left","right","up","down"]: Input.action_release(action)
	print("B18_NORMAL ",JSON.stringify({"stage":stage,"seed":run_seed,"weapon":weapon,"driver":movement_mode,"seconds":simulation,"start_hp":start_hp,"hp":PlayerData.player_hp,"hp_max":PlayerData.player_hp_max,"dead":Utils.player.is_dead,"completed":LevelServer.state=="CAMP" and not Utils.player.is_dead,"state":LevelServer.state,"method":"normal HP, legal full growth, real input; no human acceptance"}))
	_dump()
	await Demo.quit_game()

func _drive_movement(_now: int):
	if movement_mode == "still": return
	if movement_mode == "circle":
		super._drive_movement(_now); return
	steering_clock -= get_process_delta_time()
	if steering_clock > 0: return
	steering_clock = 0.12
	var player = Utils.player
	var best = Vector2.ZERO
	var best_score = -INF
	var actors = get_tree().get_nodes_in_group("monsters")
	var pellets = get_tree().get_nodes_in_group("enemy_projectiles")
	for i in 8:
		var direction = Vector2.RIGHT.rotated(i*TAU/8.0)
		if player.test_move(player.global_transform,direction*28): continue
		var point = player.global_position+direction*32
		var score = 0.0
		for actor in actors:
			if not actor.is_die:
				var distance = point.distance_to(actor.global_position)
				score -= 1500.0/maxf(8,distance)
		for p in pellets:
			var distance = Geometry2D.get_closest_point_to_segment(point,p.global_position,p.global_position+p.velocity*0.3).distance_to(point)
			if distance < 30: score -= (30-distance)*12
		if score > best_score: best_score = score; best = direction
	for pair in [["left",best.x < -0.2],["right",best.x > 0.2],["up",best.y < -0.2],["down",best.y > 0.2]]:
		if pair[1]: Input.action_press(pair[0])
		else: Input.action_release(pair[0])
