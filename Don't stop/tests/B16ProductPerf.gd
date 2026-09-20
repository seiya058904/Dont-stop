extends "res://tests/B12WeaponBench.gd"

func _ready():
	await boot()
	var all_rows = []
	for stage in [39,40]:
		stop(); dismiss(); LevelServer.return_to_camp(); await wait(0.2)
		configure(116 if stage == 39 else 112,true)
		load("res://game/map/ArenaHazardDirector.gd").fixed_seed = 808
		LevelServer.town.depart(stage,true)
		Utils.aim_override = get_viewport().get_canvas_transform()*(Utils.player.global_position+Vector2(80,0))
		driving = true; moving = true; target_boss = stage == 40
		var start = Time.get_ticks_usec(); var previous = start; var next_sample = 0.0
		var frames = []; var counts = []
		while Time.get_ticks_usec()-start < 45000000 and LevelServer.state == "COMBAT":
			PlayerData.player_hp = PlayerData.player_hp_max
			await get_tree().process_frame
			var now = Time.get_ticks_usec(); var seconds = (now-start)/1000000.0
			frames.append([seconds,(now-previous)/1000.0,Performance.get_monitor(Performance.TIME_PROCESS)*1000,Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)*1000])
			previous = now
			if seconds >= next_sample:
				next_sample += 1
				counts.append({"seconds":seconds,"enemies":get_tree().get_nodes_in_group("monsters").size(),"nodes":get_tree().get_node_count(),"heat_cells":Combat.heat_cells.size(),"transients":get_tree().get_nodes_in_group("combat_transient").size()})
		all_rows.append({"stage":stage,"weapon":116 if stage == 39 else 112,"frames":frames,"counts":counts,"method":"native Forward+ real stage, full purchased growth, actual movement/fire, HP replenished for measurement; not survival proof; not same workload as fixed fixture","true_per_frame_cpu":null,"gpu_ms":null})
	stop(); LevelServer.return_to_camp()
	var f = FileAccess.open("res://evidence/visual-upgrade-20260919/b16-product-perf.json",FileAccess.WRITE)
	f.store_string(JSON.stringify(all_rows));f.close()
	print("B16_PRODUCT_PERF runs=",all_rows.size())
	get_tree().quit()
