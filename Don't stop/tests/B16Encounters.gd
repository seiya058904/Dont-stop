extends "res://tests/B12WeaponBench.gd"

func _ready():
	await boot()
	for run_seed in [808,809]:
		if "--single" in OS.get_cmdline_user_args() and run_seed != 808: continue
		for stage in [31,35,39,40]:
			if "--single" in OS.get_cmdline_user_args() and stage != 31: continue
			stop(); dismiss()
			LevelServer.return_to_camp()
			await wait(0.2)
			configure(112,true)
			PlayerData.player_hp = PlayerData.player_hp_max
			load("res://game/map/ArenaHazardDirector.gd").fixed_seed = run_seed
			check(LevelServer.town.depart(stage,true),"normal departure %d seed %d" % [stage,run_seed])
			Utils.aim_override = get_viewport().get_canvas_transform()*(Utils.player.global_position+Vector2(80,0))
			driving = true; moving = true; target_boss = stage == 40
			var director = load("res://game/map/ArenaHazardDirector.gd").last_director.get_ref()
			var spawned = 0
			var observed = 0.0
			var duration = 75.0 if "--complete" in OS.get_cmdline_user_args() and run_seed == 808 else 16.0
			while observed < duration and LevelServer.state == "COMBAT":
				if is_instance_valid(director): spawned = maxi(spawned,director.meteor_spawned)
				await wait(0.25)
				observed += 0.25
			check(spawned > 0,"normal visible meteor %d seed %d" % [stage,run_seed])
			if duration > 16 and stage != 40: check(LevelServer.state != "COMBAT" and not Utils.player.is_dead,"complete ordinary encounter "+str(stage))
			print("B16_ENCOUNTER stage=",stage," seed=",run_seed," hp=",PlayerData.player_hp," state=",LevelServer.state)
	stop(); dismiss(); LevelServer.return_to_camp()
	print("B16 ENCOUNTERS checks=",checks," failures=",failures)
	get_tree().quit(1 if failures else 0)
