extends "res://tests/M5LongRun.gd"
# Three separate processes; real-time, unmodified encounter timers and enemy HP.
# A bot death is an observed result, never silently resurrected into a win.
var tier = "basic"
var rows = []
var row = {}
var last_hp = 0.0
var observing = false
var navigation_clock = 0.0
var seen_elites = {}
var damage_clock = 0.0
var last_damage_events = 0
func _ready():
	process_mode = Node.PROCESS_MODE_ALWAYS
	Demo.test_mode = true
	for arg in OS.get_cmdline_user_args():
		if arg in ["basic","middle","late"]: tier = arg
	seed(606)
	main = load("res://game/map/Main.tscn").instantiate()
	play_viewport = SubViewport.new(); play_viewport.size = Vector2i(1536,864)
	play_viewport.world_2d = get_viewport().world_2d
	play_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(play_viewport); play_viewport.add_child(main); Utils.gameStart()
	await wait(0.3)
	Demo.save_path = "res://evidence/m6-audit-"+tier+".json"
	get_tree().node_added.connect(observe_spawn)
	var id = 0 if tier == "basic" else (114 if tier == "middle" else 116)
	Demo.try_purchase("weapon",str(id))
	if tier != "basic":
		for talent in DemoConfig.TALENTS:
			for rank in (1 if tier == "middle" else DemoConfig.TALENTS[talent].max): Demo.try_purchase("talent",talent,"points")
	for am_id in (["1"] if tier == "basic" else Utils.am_dict.keys()):
		Demo.try_purchase("attachment",str(am_id))
	var configuration = Demo.snapshot() if Demo.has_method("snapshot") else {}
	started = Time.get_ticks_msec(); previous_frame = Time.get_ticks_usec()
	for stage in range(1,31):
		stop_input(); dismiss(); bot = false
		if Utils.player.is_dead: PlayerData.resurrectPlayer(PlayerData.player_hp_max,100)
		LevelServer.state = "CAMP"
		Demo.try_purchase("supply","health"); Demo.try_purchase("supply","ammo")
		PlayerData.changeWeapon(id,true)
		for am in PlayerData.player_am_list.values():
			if am.can_equip(Utils.player.gun): Utils.player.gun.addAttachMent(am)
		row = {"tier":tier,"stage":stage,"region":DemoConfig.ENCOUNTERS[stage].region,"boss":DemoConfig.ENCOUNTERS[stage].get("boss",""),"weapon":id,"hp_max":PlayerData.player_hp_max,"talents":Demo.talents.duplicate(),"enemy_composition":{},"spawn_total":0,"elite_total":0,"summon_total":0,"damage_taken":0.0,"dead":false,"watchdog":false,"path_failure_samples":0,"max_no_damage_seconds":0.0,"clear_seconds":null}
		seen_elites.clear(); damage_clock = 0; last_damage_events = Combat.damage_events
		row.elite_composition = {}
		last_hp = PlayerData.player_hp; observing = true
		check(LevelServer.town.depart(stage,true),"audit depart "+tier+"/"+str(stage))
		bot = true; pause_done = true; force_death_done = true
		round_started = Time.get_ticks_msec()
		while LevelServer.state == "COMBAT":
			await wait(0.2)
			if Time.get_ticks_msec()-round_started > 150000:
				row.watchdog = true; break
		row.seconds = (Time.get_ticks_msec()-round_started)/1000.0
		row.dead = Utils.player.is_dead
		row.completed = LevelServer.state == "CAMP" and not row.dead
		row.boss_seconds = row.seconds if row.boss != "" else null
		row.survival_seconds = row.seconds if row.boss == "" else null
		row.remaining_enemies = get_tree().get_nodes_in_group("monsters").filter(func(m): return not m.is_die).size()
		if row.completed and row.boss != "": row.clear_seconds = row.seconds
		# Normal encounters are timed survival, so a last enemy cannot block victory.
		row.last_enemy_blocks_victory = false if row.boss == "" else row.watchdog
		bot = false; stop_input(); observing = false
		LevelServer.return_to_camp(); dismiss(); await wait(2.0)
		row.cleanup = {"monsters":get_tree().get_nodes_in_group("monsters").size(),"transients":get_tree().get_nodes_in_group("combat_transient").size(),"orphans":Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)}
		check(row.cleanup.monsters == 0 and row.cleanup.transients == 0,"audit cleanup "+str(stage))
		rows.append(row.duplicate(true))
		print("M6 AUDIT ROW ",JSON.stringify(row))
		var file = FileAccess.open("res://docs/iteration/evidence/m6/audit-"+tier+".json",FileAccess.WRITE)
		file.store_string(JSON.stringify({"configuration":configuration,"rows":rows,"failures":failures},"\t")); file.close()
	print("M6 AUDIT COMPLETE tier=",tier," rows=",rows.size()," failures=",failures)
	await Demo.quit_game()
func _process(delta):
	if observing:
		row.damage_taken += maxf(0,last_hp-PlayerData.player_hp); last_hp = PlayerData.player_hp
		for actor in get_tree().get_nodes_in_group("monsters"):
			if actor.is_elite and not seen_elites.has(actor.get_instance_id()):
				seen_elites[actor.get_instance_id()] = true
				row.elite_total += 1
				var id = actor.get_meta("content_id","")
				row.elite_composition[id] = row.elite_composition.get(id,0)+1
		if Combat.damage_events != last_damage_events: damage_clock = 0
		elif not get_tree().paused and not get_tree().get_nodes_in_group("monsters").is_empty(): damage_clock += delta
		last_damage_events = Combat.damage_events
		row.max_no_damage_seconds = maxf(row.max_no_damage_seconds,damage_clock)
		if Utils.player.is_dead: bot = false; return
	super._process(delta)
	if not bot or get_tree().paused or LevelServer.state != "COMBAT": return
	navigation_clock += delta
	if navigation_clock < 0.1: return
	navigation_clock = 0
	var enemies = get_tree().get_nodes_in_group("monsters").filter(func(m): return not m.is_die and not m.is_queued_for_deletion())
	if enemies.is_empty(): return
	enemies.sort_custom(func(a,b): return a.global_position.distance_squared_to(Utils.player.global_position)<b.global_position.distance_squared_to(Utils.player.global_position))
	var target = enemies[0]
	var direction = Vector2.ZERO
	var distance = Utils.player.global_position.distance_to(target.global_position)
	if distance > 90 or not Combat.clear_line(Utils.player.global_position,target.global_position):
		var step = LevelServer.town.path_step(Utils.player.global_position,target.global_position)
		direction = Utils.player.global_position.direction_to(step)
		if direction == Vector2.ZERO and distance > 100: row.path_failure_samples += 1
	elif distance < 55: direction = target.global_position.direction_to(Utils.player.global_position).rotated(0.6)
	for pair in [["left",direction.x < -0.2],["right",direction.x > 0.2],["up",direction.y < -0.2],["down",direction.y > 0.2]]:
		if pair[1]: Input.action_press(pair[0])
		else: Input.action_release(pair[0])
func observe_spawn(node):
	if not observing or not node is BaseMonster: return
	var id = node.get_meta("content_id","")
	row.enemy_composition[id] = row.enemy_composition.get(id,0)+1
	row.spawn_total += 1
	if node.get("summoned") == true: row.summon_total += 1
