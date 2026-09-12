extends "res://tests/M3Weapons.gd"
func dismiss():
	for panel in Demo.pause_stack.duplicate(): Demo.pop_pause(panel); panel.queue_free()
func _ready():
	Demo.test_mode = true
	add_child(load("res://game/map/Main.tscn").instantiate()); Utils.gameStart(); PlayerData.gold = 100000; PlayerData.reward_point = 9999; await wait(0.3)
	Demo.try_purchase("weapon","0")
	Utils.player.set_process(false); Utils.player.set_physics_process(false)
	for stage in [10,20,30]:
		PlayerData.resurrectPlayer(PlayerData.player_hp_max,100); dismiss()
		check(LevelServer.town.depart(stage,true),"live Boss death-flow starts "+str(stage)); await wait(0.8)
		var boss = instance_from_id(LevelServer.boss_instance)
		boss.locked_direction = Vector2.RIGHT
		var warning = boss.zone("circle",Utils.player.global_position,40,5.0)
		var point = boss.global_position; var phase_time = boss.phase_time; var actions = boss.actions.duplicate()
		Utils.player.onHit(PlayerData.player_hp+1)
		check(Utils.player.is_dead and LevelServer.state == "DEAD","actual player death retains living Boss")
		dismiss(); await wait(0.3)
		check(boss.global_position == point and boss.phase_time == phase_time and boss.actions == actions,"living Boss stops even with death menu dismissed")
		check(not is_instance_valid(warning),"player death clears pending warning")
		var hp = boss.HP
		PlayerData.resurrectPlayer(PlayerData.player_hp_max,100); LevelServer.state = "COMBAT"; LevelServer.timerStart(); await wait(0.2)
		check(not Utils.player.is_dead and not boss.is_die and boss.HP == hp,"revive retains existing Boss HP")
		check(boss.phase_time != phase_time,"Boss resumes active phase after revive")
		var wallet = PlayerData.gold
		LevelServer.return_to_camp(); dismiss(); await wait(1.0)
		check(PlayerData.gold == wallet,"abandon living Boss gives no victory reward")
		check(get_tree().get_nodes_in_group("monsters").is_empty() and get_tree().get_nodes_in_group("combat_transient").is_empty(),"living Boss return clears ownership graph")
	print("M6 BOSS STOPS SUMMARY checks=",checks," failures=",failures)
	if failures: get_tree().quit(1)
	else: await Demo.quit_game()
