extends Node

var normal = "normal" in OS.get_cmdline_user_args()
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
	seed(333)
	main = load("res://game/map/Main.tscn").instantiate()
	add_child(main)
	Utils.gameStart(); PlayerData.gold = 100000; PlayerData.reward_point = 9999
	for frame in 8: await get_tree().physics_frame
	Demo.try_purchase("weapon","112")
	Demo.try_purchase("weapon","114")
	Demo.try_purchase("weapon","6")
	for id in DemoConfig.TALENTS:
		for rank in DemoConfig.TALENTS[id].max: Demo.try_purchase("talent",id,"points")
	gun = PlayerData.player_weapon_list[114]
	Utils.player.changeWeapon(114)
	main.get_node("Town").depart(4,true)
	if not normal: LevelServer.timerStop()
	# Dedicated pressure fixture: measured live entities. No wallet/save mutations escape it.
	Utils.player.global_position = Vector2(280,530)
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
		for i in range(150-enemies.size()):
			var enemy = load("res://game/monster/Monster 2/Monster2.tscn").instantiate()
			enemy.HP = 3
			enemy.SPEED = 90
			enemy.global_position = LevelServer.town.navigation.get_point_position(LevelServer.town.walkable.pick_random())
			main.add_child(enemy)
		var projectiles = get_tree().get_nodes_in_group("combat_transient").filter(func(n): return n is Bullet)
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
	var result = {"scenario":"normal" if normal else "pressure", "encounter_completed":completed,"seconds":elapsed,"display":DisplayServer.get_name(),"viewport":str(get_viewport().size),"gpu":RenderingServer.get_video_adapter_name(),"frame_ms":{"p50":percentile(frames,0.5),"p95":percentile(frames,0.95),"p99":percentile(frames,0.99)},"live_enemy_p50":percentile(sampled_enemies,0.5),"live_enemy_peak":sampled_enemies.max(),"live_projectile_p50":percentile(sampled_shots,0.5),"live_projectile_peak":sampled_shots.max(),"node_start":start_nodes,"node_end":Performance.get_monitor(Performance.OBJECT_NODE_COUNT),"orphan_nodes":Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT),"damage_events":Combat.damage_events}
	DirAccess.make_dir_recursive_absolute("res://evidence")
	var file = FileAccess.open("res://evidence/normal.json" if normal else "res://evidence/pressure.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(result,"\t"))
	file.close()
	print("PRESSURE ",JSON.stringify(result))
	await Demo.quit_game()
