extends "res://tests/M3Weapons.gd"
func _ready():
	Demo.test_mode=true; seed(551)
	var main=load("res://game/map/Main.tscn").instantiate(); add_child(main); Utils.gameStart(); PlayerData.gold = 100000; PlayerData.reward_point = 9999; await wait(0.5)
	Demo.try_purchase("weapon","117"); Utils.player.set_process(false); Utils.player.set_physics_process(false)
	for stage in [10,20,30]:
		PlayerData.player_hp_max=500; PlayerData.player_hp=500
		LevelServer.town.depart(stage,true); await wait(0.8)
		var boss=instance_from_id(LevelServer.boss_instance); var hp=PlayerData.player_hp
		await wait(14.0)
		print("BOSS OBSERVED ",boss.role," actions=",JSON.stringify(boss.actions)," damage_to_player=",hp-PlayerData.player_hp," movement=",boss.travelled)
		check(PlayerData.player_hp<hp,"boss natural attack actually damages player "+boss.role)
		var expected={10:["dash_end","cone","summon"],20:["summon","shot","circle"],30:["dash_end","line","shot"]}[stage]
		for action in expected: check(boss.actions.get(action,0)>0,"boss natural pattern "+boss.role+"/"+action)
		Combat.hit(boss,{"damage":10000.0,"epoch":LevelServer.epoch}); await wait(0.2)
		for panel in Demo.pause_stack.duplicate(): Demo.pop_pause(panel); panel.queue_free()
		await wait(0.8)
		check(LevelServer.state=="CAMP" and get_tree().get_nodes_in_group("combat_transient").is_empty() and get_tree().get_nodes_in_group("monsters").is_empty(),"boss death resolves and clears owned attacks")
	print("M5 BOSS COMBAT SUMMARY checks=",checks," failures=",failures)
	if failures: get_tree().quit(1)
	else: await Demo.quit_game()
