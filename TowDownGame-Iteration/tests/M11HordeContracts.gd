extends "res://tests/M8Runtime.gd"
func _ready():
	await boot(); configure(124)
	LevelServer.town.depart(29,true); LevelServer.timerStop(); await clean()
	PlayerData.player_hp_max=10000; PlayerData.player_hp=10000
	Utils.player.global_position=LevelServer.town.arena.global_position
	for i in 90: LevelServer.onMonsterCreate()
	var actors=get_tree().get_nodes_in_group("monsters")
	check(actors.size()<=DemoConfig.ENCOUNTERS[29].cap and actors.size()>60,"reinforcements share encounter cap")
	check(LevelServer.horde_overlap_peak>=2 and LevelServer.horde_while_alive>0,"arrival windows overlap before previous cohort dies")
	check(LevelServer.horde_jobs.size()<=3,"at most three simultaneous arrival windows")
	var sides={}; var unsafe=0; var positions={}
	for actor in actors:
		var offset=actor.global_position-Utils.player.global_position
		sides[(0 if offset.x>0 else 2) if absf(offset.x)>absf(offset.y) else (1 if offset.y>0 else 3)]=true
		if offset.length()<145: unsafe+=1
		if actor.get_meta("content_id","") in ["E01","E02"]: positions[actor.get_instance_id()]={"ref":weakref(actor),"point":actor.global_position}
	check(unsafe==0 and sides.size()>=2,"safe arrivals from multiple visible directions")
	await wait(2)
	var moving=0
	for row in positions.values():
		var actor=row.ref.get_ref()
		if is_instance_valid(actor) and actor.global_position.distance_to(row.point)>12: moving+=1
	check(moving>=positions.size()*0.8,"at least 80 percent of simple cohort advances under crowd collision")
	LevelServer.return_to_camp(); await wait(0.3); dismiss()
	check(LevelServer.horde_jobs.is_empty() and get_tree().get_nodes_in_group("monsters").is_empty() and get_tree().get_nodes_in_group("combat_transient").is_empty(),"horde lifecycle fully cleaned")
	print("M11_HORDE_CONTRACTS_CHECKS ",checks," FAILURES ",failures)
	await Demo.quit_game()
