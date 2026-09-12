extends "res://tests/M3Weapons.gd"
func dismiss():
	for panel in Demo.pause_stack.duplicate(): Demo.pop_pause(panel); panel.queue_free()
func _ready():
	Demo.test_mode = true; seed(660)
	var main = load("res://game/map/Main.tscn").instantiate(); add_child(main); Utils.gameStart(); PlayerData.gold = 100000; PlayerData.reward_point = 9999; await wait(0.3)
	for id in [117,118,120,121,122,116,113,124]: Demo.try_purchase("weapon",str(id))
	Utils.player.global_position = origin-Vector2(100,0)
	PlayerData.player_hp_max = 500; PlayerData.player_hp = 500
	var source = {"damage":0.25,"depth":1,"epoch":LevelServer.epoch}
	for role in ["B01","B02","B03"]:
		for id in [117,118,120,121,122,116,113]:
			LevelServer.state = "COMBAT"
			var target = M5Content.spawn(role,LevelServer.town.monster_root,origin+Vector2(50,8)); target.SPEED = 0; target.armor = 0
			var gun = PlayerData.player_weapon_list[id]; aim(gun)
			target.HP = target.max_hp*0.5+0.01
			var hp = target.HP; var kills = Combat.kill_events
			await wait(0.06)
			if id == 113: gun.charge_time = gun.effective.warmup
			gun._shoot(); await wait(1.8 if id == 121 else 0.45)
			check(target.HP < hp,"actual mechanism crosses boss threshold "+role+"/"+str(id))
			check(target.phase_two and target.actions.get("phase_two",0) == 1,"mechanism phase exactly once "+role+"/"+str(id))
			check(not target.is_die and Combat.kill_events == kills,"threshold is not a death or reward "+role+"/"+str(id))
			var before = Combat.kill_events
			Combat.hit(target,{"damage":10000.0,"epoch":LevelServer.epoch})
			check(Combat.kill_events == before+1 and not Combat.hit(target,{"damage":10000.0}),"mechanism target death idempotent")
			await wait(2.3)
			# Loot intentionally remains collectible until camp. It is also tagged
			# combat_transient but is not a projectile, warning or damage effect.
			var attacks = get_tree().get_nodes_in_group("combat_transient").filter(func(n): return n is Bullet or (n.get_script() and n.get_script().resource_path in ["res://game/monster/EnemyShot.gd","res://game/monster/HostileZone.gd","res://game/effects/GravityField.gd","res://game/effects/CombatEffect.gd"]))
			check(attacks.is_empty(),"phase then death leaves no orphan attack")
			await clean()
	# Actual wall ricochet into shield, with direct path facing away from muzzle.
	LevelServer.state = "COMBAT"
	var gun = PlayerData.player_weapon_list[117]; aim(gun)
	var barrier = wall(origin+Vector2(60,0),Vector2(4,120))
	var shield = M5Content.spawn("E09",LevelServer.town.monster_root,origin+Vector2(-40,8)); shield.set_physics_process(false); shield.HP = 100
	var hp = shield.HP; await wait(0.06); gun._shoot(); await wait(0.6)
	check(shield.HP < hp and shield.HP > 0 and hp-shield.HP <= gun.effective.damage+0.01,"ricochet hits shield once after actual wall")
	barrier.queue_free(); await clean()
	# Fragment mother and separately owned summon behind it.
	gun = PlayerData.player_weapon_list[118]; aim(gun)
	var mother = M5Content.spawn("E07",LevelServer.town.monster_root,origin+Vector2(45,8)); mother.set_physics_process(false); mother.HP = 100
	var child = M5Content.spawn("E02",LevelServer.town.monster_root,origin+Vector2(85,8),true); child.set_physics_process(false); child.HP = 100
	await wait(0.06); gun._shoot(); await wait(0.5)
	check(mother.HP < 100 and child.HP < 100,"fragment hits distinct summoned target")
	check(Combat.max_depth_seen <= DemoConfig.MAX_DERIVATION,"fragment generation bounded")
	await clean()
	for id in [120,122]:
		gun = PlayerData.player_weapon_list[id]; aim(gun)
		var target = enemy(origin+Vector2(120,8)); await wait(0.06); gun._shoot()
		target.queue_free(); await wait(2.5)
		check(get_tree().get_nodes_in_group("combat_transient").is_empty(),"destroyed tracking or saw target finite lifetime "+str(id))
	# Large ordinary enemies remain pullable; Boss immunity is covered above
	# and by M3Special. No content HP or speed is changed in the audit runs.
	gun = PlayerData.player_weapon_list[121]; aim(gun)
	var large = M5Content.spawn("E03",LevelServer.town.monster_root,origin+Vector2(55,8)); large.set_physics_process(false)
	var initial = large.global_position
	await wait(0.06); gun._shoot(); await wait(0.65)
	check(large.global_position.distance_to(initial) > 0.1,"gravity moves large non-Boss enemy")
	await clean()
	gun = PlayerData.player_weapon_list[124]; aim(gun)
	var rotary_target = enemy(origin+Vector2(60,8),10000)
	gun.drive_spin(true,gun.effective.warmup)
	check(gun.timer.wait_time >= 1.0/24.0,"rotary maximum cadence contract")
	var prior_hits = Combat.damage_events
	for volley in 36:
		gun._shoot(); gun.timer.start(); await gun.timer.timeout
	await wait(0.2)
	check(Combat.damage_events-prior_hits == 36,"sustained rotary each projectile hits exactly once")
	check(rotary_target.HP < 10000,"sustained rotary actual damage")
	await clean(); await wait(2.5)
	check(get_tree().get_nodes_in_group("combat_transient").is_empty(),"rotary transient allocation fully released; no projectile pool exists")
	# Many live special effects share one epoch and are canceled by camp return.
	var target = enemy(origin+Vector2(55,8),10000)
	for id in [117,118,120,121,122,116,113,124]:
		gun = PlayerData.player_weapon_list[id]; aim(gun); gun._shoot()
	await wait(0.1); LevelServer.return_to_camp(); dismiss(); await wait(2.5)
	check(get_tree().get_nodes_in_group("monsters").is_empty() and get_tree().get_nodes_in_group("combat_transient").is_empty(),"simultaneous mechanisms epoch cleanup")
	check(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT) == 0,"no orphan node after mechanism matrix")
	print("M6 CROSS SUMMARY checks=",checks," failures=",failures)
	if failures: get_tree().quit(1)
	else: await Demo.quit_game()
