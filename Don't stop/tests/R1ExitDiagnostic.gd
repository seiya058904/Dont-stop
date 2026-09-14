extends "res://tests/R1LongRun.gd"
# Reproduce shutdown after actual timed encounters with the long-run profile.
func _ready():
	process_mode = Node.PROCESS_MODE_ALWAYS
	Demo.test_mode = true
	play_viewport = SubViewport.new()
	play_viewport.size = Vector2i(1536,864)
	play_viewport.world_2d = get_viewport().world_2d
	play_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(play_viewport)
	main = load("res://game/map/Main.tscn").instantiate()
	play_viewport.add_child(main)
	Utils.gameStart(); PlayerData.gold = 100000; PlayerData.reward_point = 9999
	await wait(0.3)
	Demo.save_path = "res://evidence/r1-long/camp.json"
	check(Demo.load_camp(),"exit diagnostic restores long profile")
	started = Time.get_ticks_msec(); previous_frame = Time.get_ticks_usec()
	for id in [123,3,2]:
		round_index += 1
		PlayerData.switch_deadline = 0
		PlayerData.changeWeapon(id,true)
		Demo.try_purchase("supply","ammo"); Demo.try_purchase("supply","health")
		check(LevelServer.town.depart(4,true),"exit diagnostic starts full encounter")
		bot = true; pause_done = false; force_death_done = false
		round_started = Time.get_ticks_msec()
		while LevelServer.state != "CAMP": await wait(0.2)
		bot = false; stop_input(); dismiss()
		await wait(2.0)
		check(get_tree().get_nodes_in_group("combat_transient").is_empty(),"exit diagnostic camp has no transients")
	print("EXIT DIAGNOSTIC seconds=",(Time.get_ticks_msec()-started)/1000.0," failures=",failures)
	await Demo.quit_game()
