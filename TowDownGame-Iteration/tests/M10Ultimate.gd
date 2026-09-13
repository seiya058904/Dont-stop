extends "res://tests/M8Runtime.gd"
func _ready():
	await boot(); configure(0)
	Utils.player.set_physics_process(false)
	var actors = Node2D.new(); add_child(actors)
	var rows = []
	for role in ["B01","B02","B03"]:
		for max_hp in [5.0,20.0]:
			LevelServer.state = "COMBAT"; LevelServer.timerStop(); LevelServer.epoch += 1
			Utils.player.global_position = origin+Vector2(20,0)
			PlayerData.player_hp_max = max_hp; PlayerData.player_hp = max_hp
			var boss = M5Content.spawn(role,actors,origin); boss.set_physics_process(false)
			boss.phase_two = false; boss.choose_attack()
			check(get_tree().get_nodes_in_group("boss_ultimate").is_empty(),"no phase I ultimate")
			for node in get_tree().get_nodes_in_group("combat_transient"): node.queue_free()
			await wait(0.1)
			boss.phase_two = true; boss.ultimate_cooldown = 0; boss.choose_attack()
			var ultimate = get_tree().get_nodes_in_group("boss_ultimate")[0]
			var fraction = ultimate.fraction
			check(ultimate.warning>=1.3 and ultimate.warning<=1.8 and boss.ultimate_cooldown==15,"warning and cooldown")
			await wait(ultimate.warning-0.15)
			check(PlayerData.player_hp==max_hp,"no early percentage damage")
			await wait(0.3)
			check(is_equal_approx(max_hp-PlayerData.player_hp,max_hp*fraction),"actual max HP percentage "+role)
			var after = PlayerData.player_hp
			await wait(0.15)
			check(PlayerData.player_hp==after and after>0,"one hit and no full HP kill")
			rows.append({"role":role,"max_hp":max_hp,"fraction":fraction,"applied":max_hp-after,"activated":boss.actions.get("ultimate_activated",0)})
			await clean()
	LevelServer.state = "COMBAT"; PlayerData.player_hp_max = 20; PlayerData.player_hp = 20
	Demo.talents.T19 = 1; Demo.talent_cooldowns.clear()
	Utils.player.on_percentage_hit(0.3)
	check(PlayerData.player_hp==20 and Demo.cooldown("T19")>0,"percentage follows shield contract")
	Utils.player.on_percentage_hit(0.3)
	check(PlayerData.player_hp==14,"shield cooldown does not erase second percentage hit")
	var file = FileAccess.open("res://docs/iteration/evidence/m10/ultimate.json",FileAccess.WRITE); file.store_string(JSON.stringify({"checks":checks,"failures":failures,"rows":rows},"\t")); file.close()
	print("M10_ULTIMATE_CHECKS ",checks," FAILURES ",failures)
	LevelServer.return_to_camp(); await Demo.quit_game()
