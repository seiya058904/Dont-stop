extends Node

var normal = false
var baseline = "baseline" in OS.get_cmdline_user_args()
var spawn_counter = 0
var special_index = 0
var original_enemy_samples: Array = []
var original_projectile_samples: Array = []
var completed = false
var main
var frames: Array[float] = []
var elapsed = 0.0
var shot_clock = 0.0
var sampled_enemies: Array[int] = []
var sampled_shots: Array[int] = []
var finishing = false
var gun
var start_nodes = 0

func _ready():
	Demo.test_mode = true
	if DisplayServer.get_name() != "headless": get_tree().quit(2); return
	seed(333)
	main = load("res://game/map/Main.tscn").instantiate()
	add_child(main)
	Utils.gameStart()
	for frame in 8: await get_tree().physics_frame
	Demo.try_purchase("weapon","112")
	Demo.try_purchase("weapon","114")
	Demo.try_purchase("weapon","6")
	for id in [117,118,120,121,122,116]: Demo.try_purchase("weapon",str(id))
	for id in DemoConfig.TALENTS:
		for rank in DemoConfig.TALENTS[id].max: Demo.try_purchase("talent",id,"points")
	gun = PlayerData.player_weapon_list[114]
	Utils.player.changeWeapon(114)
	main.get_node("Town").depart(24,true)
	if not normal: LevelServer.timerStop()
	# Dedicated pressure fixture: measured live entities. No wallet/save mutations escape it.
	Utils.player.global_position = LevelServer.town.arena.global_position
	Utils.player.set_physics_process(false); Utils.player.set_process(false)
	start_nodes = int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	process_mode = Node.PROCESS_MODE_ALWAYS

func _process(delta):
	if gun == null or finishing: return
	if not Demo.pause_stack.is_empty():
		for owner_node in Demo.pause_stack.duplicate():
			Demo.pop_pause(owner_node)
			if owner_node != self: owner_node.queue_free()
	if Utils.player.is_dead:
		PlayerData.resurrectPlayer(PlayerData.player_hp_max,100)
		LevelServer.state = "COMBAT"
		if normal: LevelServer.timerStart()
	elapsed += delta
	if elapsed > 3: frames.append(delta*1000)
	shot_clock += delta
	if normal:
		if LevelServer.state == "CAMP": completed = true
		if shot_clock > 0.3 and LevelServer.state == "COMBAT":
			shot_clock = 0
			var enemies = get_tree().get_nodes_in_group("monsters").filter(func(e): return not e.is_die)
			if not enemies.is_empty():
				var target = enemies.front()
				gun.set_process(false)
				gun.direction = gun.gun_tip.global_position.direction_to(target.global_position-Vector2(0,8))
				if gun.bullets_count <= 0: gun.reload_ammo()
				if not gun.is_reloading and gun.bullets_count > 0: gun._shoot()
			sampled_enemies.append(enemies.size())
			sampled_shots.append(get_tree().get_nodes_in_group("combat_transient").filter(func(n): return n is Bullet).size())
		if elapsed >= 48:
			finishing = true
			finish()
		return
	if shot_clock > 0.12:
		shot_clock = 0
		var enemies = get_tree().get_nodes_in_group("monsters").filter(func(e): return not e.is_die)
		original_enemy_samples.append(enemies.size())
		for i in range(150-enemies.size()):
			var arena = LevelServer.town.arena
			var point = arena.to_global(arena.grid.get_point_position(arena.cells.pick_random()))
			var id = "E01" if baseline else M5Content.ENEMIES.keys()[spawn_counter%12]
			M5Content.spawn(id,main,point)
			spawn_counter += 1

		var projectiles = get_tree().get_nodes_in_group("combat_transient").filter(func(n): return n is Bullet)
		original_projectile_samples.append(projectiles.size())
		for i in range(400-projectiles.size()):
			var bullet = gun.bullet_scene.instantiate()
			bullet.global_position = Utils.player.global_position+Vector2(randf_range(-170,170),randf_range(-90,90))
			bullet.rotation = randf()*TAU
			main.add_child(bullet)
			bullet.gun = gun
			bullet.hurt = gun.effective.damage
			bullet.context = gun.damage_context()
			bullet.speed = 90
			bullet.fire()
		if not baseline:
			var special = PlayerData.player_weapon_list[[117,118,120,121,122,116][special_index%6]]; special_index += 1
			special.set_use(true); special.set_process(false); special.set_physics_process(false); special.bullets_count=special.bullets_max_count
			special.direction = Vector2.RIGHT.rotated(elapsed); special._shoot(); special.set_use(false)
		Combat.arc(PlayerData.player_weapon_list[112],Utils.player.global_position,Vector2.RIGHT.rotated(elapsed))
		Combat.explosion(Utils.player.global_position+Vector2(90,20),38.4,4,gun)
		var laser = PlayerData.player_weapon_list[6]
		laser.set_use(true)
		laser.bullets_count = 5
		laser.openFire()
		sampled_enemies.append(get_tree().get_nodes_in_group("monsters").filter(func(e): return not e.is_die).size())
		sampled_shots.append(get_tree().get_nodes_in_group("combat_transient").filter(func(n): return n is Bullet).size())
	if elapsed >= 12 and not FileAccess.file_exists("res://evidence/pressure.png") and DisplayServer.get_name() != "headless":
		DirAccess.make_dir_recursive_absolute("res://evidence")
		get_viewport().get_texture().get_image().save_png("res://evidence/pressure.png")
	if elapsed >= 33:
		finishing = true
		finish()

func percentile(values: Array, fraction: float):
	var sorted = values.duplicate()
	sorted.sort()
	return sorted[mini(sorted.size()-1,int(sorted.size()*fraction))] if not sorted.is_empty() else 0

func finish():
	var result = {"fixture":"old E01 pressure" if baseline else "M5 mixed pressure with six special mechanisms","pre_refill_enemy_p50":percentile(original_enemy_samples,0.5),"pre_refill_projectile_p50":percentile(original_projectile_samples,0.5),"scenario":"normal" if normal else "pressure", "encounter_completed":completed,"seconds":elapsed,"display":DisplayServer.get_name(),"viewport":str(get_viewport().size),"gpu":RenderingServer.get_video_adapter_name(),"frame_ms":{"p50":percentile(frames,0.5),"p95":percentile(frames,0.95),"p99":percentile(frames,0.99)},"live_enemy_p50":percentile(sampled_enemies,0.5),"live_enemy_peak":sampled_enemies.max(),"live_projectile_p50":percentile(sampled_shots,0.5),"live_projectile_peak":sampled_shots.max(),"node_start":start_nodes,"node_end":Performance.get_monitor(Performance.OBJECT_NODE_COUNT),"orphan_nodes":Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT),"damage_events":Combat.damage_events}
	DirAccess.make_dir_recursive_absolute("res://evidence")
	var file = FileAccess.open("res://evidence/m5-pressure-baseline.json" if baseline else "res://evidence/m5-pressure-mixed.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(result,"\t"))
	file.close()
	print("PRESSURE ",JSON.stringify(result))
	LevelServer.return_to_camp()
	for panel in Demo.pause_stack.duplicate(): Demo.pop_pause(panel); panel.queue_free()
	await get_tree().create_timer(2.0).timeout
	print("PRESSURE CLEANUP nodes=",Performance.get_monitor(Performance.OBJECT_NODE_COUNT)," orphans=",Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)," transients=",get_tree().get_nodes_in_group("combat_transient").size()," enemies=",get_tree().get_nodes_in_group("monsters").size())
	await Demo.quit_game()
