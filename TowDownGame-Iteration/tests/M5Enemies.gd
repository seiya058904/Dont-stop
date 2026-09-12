extends "res://tests/M3Weapons.gd"
func _ready():
	Demo.test_mode = true; seed(515)
	var main = load("res://game/map/Main.tscn").instantiate(); add_child(main); Utils.gameStart(); await wait(0.5)
	Demo.try_purchase("weapon","117")
	var town = LevelServer.town
	for id in M5Content.ENEMIES:
		await clean(); LevelServer.state = "COMBAT"; LevelServer.timerStop()
		PlayerData.player_hp_max = 200; PlayerData.player_hp = 200
		Utils.player.global_position = town.portal_lv1.global_position+Vector2(0,35)
		Utils.player.set_physics_process(false); Utils.player.set_process(false)
		var point = town.spawn_near(Utils.player.global_position,60,110)
		check(point != Vector2.INF,"safe enemy spawn "+id)
		if point == Vector2.INF: continue
		var enemy = M5Content.spawn(id,town.monster_root,point)
		var buddy = null
		if id == "E08":
			buddy = M5Content.spawn("E03",town.monster_root,point+Vector2(15,0)); buddy.HP = 3; buddy.set_physics_process(false)
		var hp = PlayerData.player_hp
		await wait(7.0 if id in ["E07","E08","E10"] else 4.5)
		check(is_instance_valid(enemy) or id == "E06","enemy acted without invalid lifetime "+id)
		if is_instance_valid(enemy):
			if id == "E07": check(enemy.summon_total > 0 and enemy.summon_total <= 3,"producer actual finite spawn")
			elif id == "E08": check(buddy.HP > 3 and buddy.HP <= 6,"support actual bounded healing")
			elif id in ["E01","E02","E04","E05"]: check(PlayerData.player_hp < hp,"baseline real pursuit or attack "+id)
			else: check(enemy.actions.get("attack",0)>0,"enemy executed attack "+id)
			enemy.set_physics_process(false)
			var before = enemy.HP
			origin = Vector2(0,-2000)
			enemy.global_position = origin+Vector2(45,8)
			Utils.player.global_position = origin-Vector2(100,0)
			aim(Utils.player.gun); Utils.player.gun._shoot(); await wait(0.15)
			check(enemy.HP < before,"real bullet damage enemy "+id)
			Combat.hit(enemy,{"damage":1000.0,"epoch":LevelServer.epoch})
			check(enemy.is_die,"enemy death once "+id)
		else: check(PlayerData.player_hp < hp,"self explosion actual player damage")
		LevelServer.return_to_camp(); await wait(0.8)
		check(get_tree().get_nodes_in_group("combat_transient").is_empty() and get_tree().get_nodes_in_group("monsters").is_empty(),"enemy camp cleanup "+id)
		for panel in Demo.pause_stack.duplicate(): Demo.pop_pause(panel); panel.queue_free()
	print("M5 ENEMIES SUMMARY checks=",checks," failures=",failures)
	await wait(1.0); get_tree().quit(1 if failures else 0)
