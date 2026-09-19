extends "res://tests/M8Runtime.gd"

func _ready():
	await boot()
	dismiss()
	var rows: Array = []
	for cycle in 10:
		configure([116,124,111][cycle%3],false)
		check(LevelServer.town.depart(6,true),"lifecycle departure "+str(cycle))
		PlayerData.player_hp_max = 10000
		PlayerData.player_hp = 10000
		await wait(0.2)
		fire_at(Utils.player.global_position+Vector2(100,0),0.11)
		await wait(0.15)
		stop()
		LevelServer.return_to_camp()
		dismiss()
		await wait(0.8)
		check(get_tree().get_nodes_in_group("combat_transient").is_empty(),"no residual combat visuals "+str(cycle))
		check(load("res://game/effects/CombatEffect.gd").detail_slots == 0,"all decoration slots released "+str(cycle))
		check(load("res://game/effects/HostileVFX.gd").alive == 0,"all hostile bursts released "+str(cycle))
		check(not ArenaVisibility.fog_active(),"camp visibility restored "+str(cycle))
		rows.append({"cycle":cycle,"nodes":get_tree().get_node_count(),"orphans":Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT),"memory":OS.get_static_memory_usage()})
	# Static caches may warm during the first three weapon families. Afterwards
	# identical cycles must converge; memory is retained as a gauge, not a fake leak proof.
	check(rows[9].nodes <= rows[3].nodes,"ten cycles converge to the warmed node count")
	check(rows[9].orphans <= rows[3].orphans,"ten cycles do not accumulate orphan nodes")
	print("PRESENTATION_LIFECYCLE ",JSON.stringify(rows))
	print("PRESENTATION_LIFECYCLE CHECKS=",checks," FAILURES=",failures)
	if failures: get_tree().quit(1)
	else: await Demo.quit_game()
