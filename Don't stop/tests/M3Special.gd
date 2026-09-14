extends "res://tests/M3Weapons.gd"
func _ready():
	Demo.test_mode = true
	var main = load("res://game/map/Main.tscn").instantiate()
	add_child(main)
	Utils.gameStart(); PlayerData.gold = 100000; PlayerData.reward_point = 9999
	await wait(0.2)
	Utils.player.global_position = origin-Vector2(100,0)
	for id in [121,122,124]: Demo.try_purchase("weapon",str(id))
	LevelServer.state = "COMBAT"
	var target = enemy(origin+Vector2(45,0))
	var shielded = enemy(origin+Vector2(-40,0))
	var barrier = wall(origin+Vector2(-20,0),Vector2(4,200))
	var boss = enemy(origin+Vector2(0,45))
	boss.is_boss = true
	var field = load("res://game/effects/GravityField.gd").new()
	field.context = {"damage":5.0,"radius":64.0,"epoch":LevelServer.epoch}
	field.position = origin
	add_child(field)
	await wait(0.4)
	check(target.position.x < origin.x+45,"gravity actually attracts normal enemy")
	check(shielded.position == origin+Vector2(-40,0),"gravity cannot attract through wall")
	check(boss.position == origin+Vector2(0,45),"gravity boss pull immunity")
	await wait(0.7)
	check(target.HP < 100 and boss.HP < 100 and shielded.HP == 100,"gravity final explosion with wall and boss damage")
	barrier.queue_free()
	await clean()
	var disc = PlayerData.player_weapon_list[122]
	aim(disc)
	var victim = enemy(origin+Vector2(45,8))
	await wait(0.06)
	disc._shoot()
	await wait(1.3)
	check(is_equal_approx(100-victim.HP,disc.effective.damage*2),"disc actual one hit outbound and one return")
	await wait(1.1)
	check(get_tree().get_nodes_in_group("combat_transient").is_empty(),"disc safely returns or expires")
	await clean()
	aim(disc)
	get_tree().node_added.connect(trace_disc_lifecycle)
	var freed_victim = enemy(origin+Vector2(45,8))
	await wait(0.06)
	disc._shoot()
	await wait(0.1)
	check(freed_victim.HP < 100,"disc freed-target setup has actual outbound hit")
	freed_victim.queue_free()
	await wait(1.5)
	check(get_tree().get_nodes_in_group("combat_transient").is_empty(),"disc returns safely after hit target is freed")
	get_tree().node_added.disconnect(trace_disc_lifecycle)
	var rotary = PlayerData.player_weapon_list[124]
	aim(rotary)
	rotary.drive_spin(true,0.01)
	var slow = rotary.timer.wait_time
	rotary.drive_spin(true,3.0)
	check(rotary.timer.wait_time < slow and is_equal_approx(rotary.timer.wait_time,1.0/24.0),"rotary accelerates and caps 24 per second")
	rotary.drive_spin(false,0.4)
	check(rotary.spin > 0 and rotary.spin < 1 and rotary.timer.wait_time > 1.0/24.0,"rotary release gradually slows")
	for stop in ["pause","switch","death","camp"]:
		rotary.drive_spin(true,2)
		match stop:
			"pause": Demo.push_pause(self); Demo.pop_pause(self)
			"switch": Utils.player.changeWeapon(122)
			"death": Utils.player.is_dead = true; Demo.stop_attacks(); Utils.player.is_dead = false
			"camp": LevelServer.return_to_camp()
		check(rotary.spin == 0,"rotary stops "+stop)
		LevelServer.state = "COMBAT"
		aim(rotary)
	await clean()
	await wait(1.5)
	print("M3 SPECIAL SUMMARY checks=",checks," failures=",failures)
	get_tree().quit.call_deferred(1 if failures else 0)

func trace_disc_lifecycle(node):
	if not (node is BaseMonster or node is Bullet): return
	var identity = {"type":node.get_script().resource_path,"id":node.get_instance_id(),"created_ms":Time.get_ticks_msec(),"epoch":LevelServer.epoch}
	print("DISC LIFECYCLE created ",JSON.stringify(identity))
	node.tree_exiting.connect(func():
		print("DISC LIFECYCLE exiting ",JSON.stringify(identity)," destroyed_ms=",Time.get_ticks_msec()," epoch=",LevelServer.epoch))
