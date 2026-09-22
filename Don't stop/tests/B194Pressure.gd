extends "res://tests/M8Runtime.gd"

class QuietDriver extends "res://game/diag/B11Stress.gd":
	func _ready() -> void: pass

func reference_top_up(driver, budget: int) -> int:
	var target: int = mini(driver.enemies,driver._stage_cap())
	var roles: Array = driver._stage_roles()
	var attempts := 0
	var added := 0
	while driver._live_enemies() < target and attempts < budget:
		attempts += 1
		var role := str(roles[(attempts-1)%roles.size()])
		var point: Vector2 = LevelServer.town.spawn_point(M5Content.radius_for(role))
		if point == Vector2.INF: continue
		var actor = M5Content.spawn(role,LevelServer.town.monster_root,point)
		if actor == null: continue
		actor.set_meta("b11_topped_up",true)
		added += 1
	return added

func roster() -> Array:
	var result: Array = []
	for actor in get_tree().get_nodes_in_group("monsters"):
		actor.set_physics_process(false)
		result.append([actor.get_meta("content_id"),actor.global_position,actor.HP,actor.get_meta("enchantment",0)])
	return result

func _ready():
	await boot(); configure(112,true)
	LevelServer.return_to_camp(); dismiss(); await wait(0.1)
	LevelServer.town.depart(39,true); LevelServer.timerStop(); await clean()
	Utils.player.set_physics_process(false)
	Utils.player.global_position = LevelServer.town.arena.global_position
	var driver := QuietDriver.new()
	driver.stage = 39; driver.scenario = "P"; driver.enemies = 12
	add_child(driver)
	driver.set_physics_process(false)
	driver._tracked_kill_events = Combat.kill_events
	get_tree().node_added.connect(driver._count_added)
	get_tree().node_removed.connect(driver._count_removed)
	var actor = M5Content.spawn("E01",LevelServer.town.monster_root,Utils.player.global_position+Vector2(90,0))
	actor.set_physics_process(false)
	check(driver._tracked_enemy_count == 1,"birth enters live counter")
	actor.onDie(false)
	driver._sync_live_enemy_count()
	check(driver._tracked_enemy_count == 0 and driver._live_enemies() == 0,"death leaves live counter before corpse is freed")
	await wait(0.7)
	driver._sync_live_enemy_count()
	check(driver._tracked_enemy_count == 0,"delayed corpse free cannot count death twice")
	actor = M5Content.spawn("E01",LevelServer.town.monster_root,Utils.player.global_position+Vector2(90,0))
	actor.set_physics_process(false); actor.queue_free()
	await get_tree().process_frame; await get_tree().process_frame
	driver._sync_live_enemy_count()
	check(driver._tracked_enemy_count == 0,"alive cleanup removes exactly one actor")
	# Compare the frozen old scan-per-attempt loop against the bounded local count,
	# through the same real factory, collision world, variant sequence and RNG.
	preload("res://game/config/B18Variants.gd").generation = -1
	seed(922240)
	var expected_added := reference_top_up(driver,8)
	var expected := roster()
	var next_random := randi()
	await clean()
	preload("res://game/config/B18Variants.gd").generation = -1
	seed(922240)
	var actual_added := driver._top_up_enemies(8)
	var actual := roster()
	check(actual_added == expected_added and actual == expected,"top-up preserves births, roles, positions, HP and variants")
	check(randi() == next_random,"top-up preserves random sequence")
	driver._sync_live_enemy_count()
	check(driver._tracked_enemy_count == driver._live_enemies(),"live counter agrees with independent group scan")
	LevelServer.return_to_camp(); dismiss(); await wait(0.2)
	driver._sync_live_enemy_count()
	check(driver._tracked_enemy_count == 0,"camp cleanup drains live counter")
	# The formal window is a real 180-enemy peak followed by kill/refill churn. A
	# short population dip is evidence in the window, not a reason to erase it.
	driver._pressure_phase = driver.PRESSURE_BUILD
	driver._effective_tick = 1
	driver._update_pressure_phase(180)
	check(driver._pressure_phase == driver.PRESSURE_SETTLING,"floor starts settling")
	driver._update_pressure_phase(179)
	check(driver._pressure_phase == driver.PRESSURE_SETTLING,"single sampled shortfall stays in settling")
	driver._update_pressure_phase(180)
	driver._effective_tick += int(driver.PRESSURE_SETTLING_SECONDS*Engine.physics_ticks_per_second)
	driver._update_pressure_phase(180)
	check(driver._pressure_phase == driver.PRESSURE_STEADY,"qualified settling enters steady")
	driver._pressure_steady_seconds = driver.seconds
	driver._pressure_steady_samples = 1
	check(driver._pressure_measurement_valid(),"full qualified window may pass")
	driver._enemy_count_mismatches = 1
	check(not driver._pressure_measurement_valid(),"independent count mismatch rejects acceptance")
	driver._enemy_count_mismatches = 0
	driver._pressure_steady_ms.append(8.0)
	driver._update_pressure_phase(179)
	check(driver._pressure_measurement_valid() and not driver._pressure_steady_ms.is_empty() and driver._pressure_steady_seconds == driver.seconds,"shortfall stays inside the qualified churn window")
	print("B194_PRESSURE checks=",checks," failures=",failures)
	if failures: get_tree().quit(1)
	else: await Demo.quit_game()
