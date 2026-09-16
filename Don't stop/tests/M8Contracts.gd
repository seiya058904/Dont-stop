extends "res://tests/M8Runtime.gd"
func _ready():
	await boot(); configure(124)
	check(Utils.weapon_list.size()==24 and Utils.am_dict.size()==24 and DemoConfig.TALENTS.size()==24,"frozen player content")
	check(M5Content.ENEMIES.size()==15 and M5Content.BOSSES.size()==4 and DemoConfig.ENCOUNTERS.size()==40,"frozen combat content")
	var barrier = wall(Utils.player.global_position+Vector2(35,0),Vector2(8,80))
	await wait(0.06)
	var start = Utils.player.global_position
	Input.action_press("right"); await wait(0.65); Input.action_release("right")
	check(Utils.player.global_position.x < start.x+32,"player physically collides with arena wall layer")
	barrier.queue_free()
	Utils.player.set_physics_process(false); Utils.player.set_process(false)
	var root = Node2D.new(); add_child(root)
	var behavior = []
	for id in ["E03","E06","E07","E08","E09","E10","E11","E12"]:
		LevelServer.state = "COMBAT"; Utils.player.global_position = origin; PlayerData.player_hp_max = 500; PlayerData.player_hp = 500
		var actor = M5Content.spawn(id,root,origin+Vector2(180,0))
		var ally = M5Content.spawn("E01",root,origin+Vector2(95,-30)); ally.HP=1
		var before = actor.global_position; var travel = 0.0; var pursuit = 0.0; var recover_motion = 0.0; var attack_time = 0.0
		var first_distance = 180.0; var minimum = first_distance; var final_distance = first_distance
		for sample in 60:
			await wait(0.1)
			if not is_instance_valid(actor) or actor.is_die: break
			var pos = actor.global_position; var moved = pos-before; var distance = pos.distance_to(Utils.player.global_position)
			travel += moved.length(); minimum = minf(minimum,distance); final_distance = distance
			if moved.dot(before.direction_to(Utils.player.global_position))>0.4: pursuit += 0.1
			if actor.phase=="recover": recover_motion += moved.length()
			if actor.phase in ["warn","dash"]: attack_time += 0.1
			if sample==25: Utils.player.global_position = origin+Vector2(-75,-40)
			if sample==45: Utils.player.global_position = pos+Vector2(40,30)
			before = pos
		check(travel>25,"actual target acquisition and movement "+id)
		check(pursuit>0.3 and minimum<150,"actually closes distance "+id)
		if id not in ["E06"]: check(recover_motion>1,"cooldown reposition "+id)
		if is_instance_valid(actor):
			check(actor.summon_total <= 3,"finite summon lifetime "+id)
			behavior.append({"id":id,"travel":travel,"pursuit_seconds":pursuit,"attack_seconds":attack_time,"cooldown_motion":recover_motion,"first_distance":first_distance,"minimum_distance":minimum,"final_distance":final_distance,"actions":actor.actions.duplicate()})
		LevelServer.return_to_camp(); dismiss(); await wait(0.7)
		check(get_tree().get_nodes_in_group("monsters").is_empty() and get_tree().get_nodes_in_group("combat_transient").is_empty(),"restart clears actors and attacks "+id)
	var evidence_name = "r1-enemy-contracts.json" if "--r1" in OS.get_cmdline_user_args() else "enemy-contracts.json"
	var f = FileAccess.open("res://docs/iteration/evidence/m8/"+evidence_name,FileAccess.WRITE); f.store_string(JSON.stringify(behavior,"\t")); f.close()
	# Every warning is harmless until its authored deadline, then actually hits.
	for mode in ["circle","cone","line","charge"]:
		LevelServer.state = "COMBAT"; Utils.player.global_position = origin+Vector2(20,0)
		var zone = load("res://game/monster/HostileZone.gd").new(); zone.mode = mode; zone.global_position = origin; zone.warning = 0.35; zone.duration = 0.3; add_child(zone)
		await wait(0.22); check(zone.hit_count==0,"no early damage "+mode)
		await wait(0.2); check(zone.hit_count>0,"authored footprint hits after warning "+mode)
		LevelServer.return_to_camp(); dismiss(); await wait(0.2)
	# Player death pauses production attacks; return / new epoch invalidates all pending effects.
	LevelServer.state = "COMBAT"
	var active = M5Content.spawn("E10",root,origin+Vector2(130,0))
	await wait(0.8); PlayerData.player_hp = 0; await wait(0.1)
	check(LevelServer.state=="DEAD" and get_tree().paused,"natural death stops combat")
	dismiss(); PlayerData.resurrectPlayer(5,100); LevelServer.return_to_camp(); await wait(0.7)
	check(get_tree().get_nodes_in_group("combat_transient").is_empty(),"death restart cleans pending warning")
	print("M8 CONTRACTS SUMMARY checks=",checks," failures=",failures)
	if failures: get_tree().quit(1)
	else: await Demo.quit_game()
