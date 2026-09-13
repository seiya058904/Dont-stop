extends "res://tests/M8Runtime.gd"
func _ready():
	await boot(); configure(124)
	for stage in [21,26]:
		LevelServer.town.depart(stage,true); LevelServer.timerStop(); await clean()
		var arena=LevelServer.town.arena
		Utils.player.global_position=arena.global_position
		PlayerData.player_hp_max=10000; PlayerData.player_hp=10000
		for side in M5Content.REGIONS[arena.region_id].sides:
			for role in ["E01","E02"]:
				var point=arena.spawn_near(Utils.player.global_position,145,280,side)
				check(point.is_finite(),"connected spawn for "+role+" region "+str(stage)+" side "+str(side))
				if not point.is_finite(): continue
				var actor=M5Content.spawn(role,arena,point)
				var start=actor.global_position
				await wait(2)
				check(is_instance_valid(actor) and actor.global_position.distance_to(start)>24,"isolated pursuit leaves spawn without wall lock "+role+" region "+str(stage)+" side "+str(side))
				if is_instance_valid(actor): actor.queue_free()
				await wait(0.1)
		LevelServer.return_to_camp(); await wait(0.3); dismiss()
	check(get_tree().get_nodes_in_group("monsters").is_empty() and get_tree().get_nodes_in_group("combat_transient").is_empty(),"navigation fixture cleanup")
	print("M11_NAVIGATION_CHECKS ",checks," FAILURES ",failures)
	await Demo.quit_game()
