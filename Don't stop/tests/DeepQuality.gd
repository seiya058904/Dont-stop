extends "res://tests/M8Runtime.gd"

func _ready():
	await boot()
	dismiss()
	var total := 0
	for region in RegionTheme.FLOOR:
		var arena = preload("res://game/map/CombatArena.gd").new()
		arena.region_id = region
		play_view.add_child(arena)
		arena.position = Vector2(133,-57)
		var exact := true
		for target_index in [0,arena.cells.size()/3,arena.cells.size()-1]:
			var b: Vector2i = arena.cells[target_index]
			for index in range(0,arena.cells.size(),7):
				var a: Vector2i = arena.cells[index]
				var raw = arena.grid.get_point_path(a,b)
				var expected: Vector2 = arena.to_global(raw[1] if raw.size()>1 else arena.grid.get_point_position(b))
				var from: Vector2 = arena.to_global(arena.grid.get_point_position(a))
				var to: Vector2 = arena.to_global(arena.grid.get_point_position(b))
				exact = exact and arena.path_step(from,to).is_equal_approx(expected)
				exact = exact and arena.path_step(from,to).is_equal_approx(expected)
				total += 1
		check(exact,region+" cached steps equal original A* including transformed arenas")
		check(arena.path_cache_hits >= arena.path_searches,region+" repeat requests reuse exact results")
		check(arena._step_cache.size() <= arena.STEP_CACHE_LIMIT,region+" navigation cache is bounded")
		if region == "R2":
			for target_index in 65:
				for start_index in 64:
					arena.path_step(arena.to_global(arena.grid.get_point_position(arena.cells[start_index])),arena.to_global(arena.grid.get_point_position(arena.cells[target_index])))
			check(arena._step_cache.size() <= arena.STEP_CACHE_LIMIT and arena.path_searches > arena.STEP_CACHE_LIMIT,"cache eviction stays bounded after more than 4096 distinct routes")
			var from: Vector2 = arena.to_global(arena.grid.get_point_position(arena.cells[0]))
			var target := arena.to_global(Vector2(2000,2000))
			var edge := arena.nearest(target)
			var raw: PackedVector2Array = arena.grid.get_point_path(arena.cells[0],edge)
			var expected: Vector2 = arena.to_global(raw[1] if raw.size()>1 else arena.grid.get_point_position(edge))
			check(arena.path_step(from,target).is_equal_approx(expected),"out-of-bounds targets preserve original nearest-cell fallback")
			arena.position += Vector2(24,19)
			check(arena.path_step(from+Vector2(24,19),target+Vector2(24,19)).is_equal_approx(expected+Vector2(24,19)),"cached local waypoint follows a later arena transform")
		arena.queue_free()
		await get_tree().process_frame
	configure(0,false)
	var gun: BaseGun = Utils.player.gun
	var tip: Vector2 = gun.gun_tip.position
	var body_scale: Vector2 = gun.gun_image.scale
	gun.play_shot_feedback(0.1)
	check(gun.gun_image.scale == body_scale,"metal receiver keeps its authored dimensions during recoil")
	check(gun.idle_visual.action_remaining > 0,"ballistic working parts cycle on a real recoil event")
	gun.cancel_actions()
	check(gun.idle_visual.action_remaining == 0 and gun.gun_tip.position == tip,"interrupted action resets without changing firing anchor")
	var script = preload("res://game/monster/EnemyShot.gd")
	var shots: Array = []
	for i in 2:
		var shot = script.new()
		shot.velocity = Vector2(0,100)
		play_view.add_child(shot)
		shot.set_physics_process(false)
		shots.append(shot)
	check(shots[0].get_child(0).shape == shots[1].get_child(0).shape,"hostile shots share immutable collision geometry")
	check(is_equal_approx(shots[0]._body_ink.rotation,PI/2),"projectile nose follows launch heading")
	for shot in shots: shot.queue_free()
	await get_tree().process_frame
	var feedback = preload("res://ui/widgets/HitLabel.tscn").instantiate()
	feedback.position.y = -12
	gun.add_child(feedback)
	feedback.age = 0.65
	feedback._update_motion()
	check(is_equal_approx(feedback.position.y,-36) and feedback.scale == Vector2.ONE,"damage-number travel and scale retain their original endpoints")
	check(is_equal_approx(feedback.modulate.a,pow(1.0-0.1/0.22,3)),"damage-number fade retains the cubic curve and delay")
	feedback.queue_free()
	LevelServer.town.depart(10,true)
	var boss = LevelServer.get_boss()
	boss.set_physics_process(false)
	var root_at: Vector2 = boss.global_position
	var hull_at: Vector2 = boss.get_node("CollisionShape2D").position
	boss.phase = "warn"; boss.phase_time = 1.0; boss.attack_kind = "charge"
	boss.locked_direction = Vector2.RIGHT
	boss._request_visual_redraw(0.1)
	boss.phase_time = 0.1
	boss._request_visual_redraw(0.1)
	check(boss.sprite_body.position.x < boss._body_rest.x,"attack anticipation pulls only the artwork opposite the real locked direction")
	check(boss.global_position == root_at and boss.get_node("CollisionShape2D").position == hull_at and boss.locked_direction == Vector2.RIGHT,"anticipation preserves root, collision and aim lock")
	boss.phase = "recover"
	for i in 60: boss._request_visual_redraw(1.0/60)
	check(boss._body_offset == Vector2.ZERO and boss.sprite_body.position == boss._body_rest,"recovered artwork settles exactly without perpetual transform updates")
	print("DEEP_QUALITY path_pairs=",total," checks=",checks," failures=",failures)
	if failures: get_tree().quit(1)
	else: await Demo.quit_game()
