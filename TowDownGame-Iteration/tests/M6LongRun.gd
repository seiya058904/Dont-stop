extends Node
# Dedicated test process/path: never reads or writes the player's camp file.
var main
var play_viewport: Viewport
var started = 0
var previous_frame = 0
var frames_ms: Array = []
var samples: Array = []
var round_index = 0
var bot = false
var aim_clock = 0.0
var pause_done = false
var force_death_done = false
var round_started = 0
var revives = 0
var failures = 0
var purchases = 0
var reloads = 0
var sampled_enemies: Array = []
var sampled_shots: Array = []
var pause_events = 0
var config_events = 0
# Headless uses an engine-only trigger adapter; no OS pointer/keyboard events.
# It exercises real weapon timers, projectiles and collisions, not desktop input/rendering.
var background = DisplayServer.get_name() == "headless"
var background_aim = Vector2.ZERO
var background_smoke = "background-smoke" in OS.get_cmdline_user_args()
var diagnostic = "diagnostic" in OS.get_cmdline_user_args() or background_smoke
var live_entities = {}
var cleanup_trace = []
var recording_cleanup = false
var mouse_events = []
var last_trace = 0
var stage_ids = range(1,31)
var lifecycle_events: Array = []
var lifecycle_total = 0
var peak_hostile = 0
var content_seen = {}
var mechanisms_seen = {}
var boss_wins = {}
var weapon_ids = [117,118,119,120,111,113,115,116,121,122,124,0,6,112,114,123,3,5,8,7,1,2,4,9]
func check(ok,name):
	if not ok: failures += 1
	print(("PASS " if ok else "FAIL ")+name)
func wait(seconds):
	await get_tree().create_timer(seconds,true).timeout
func stop_input():
	for action in ["shoot","left","right","up","down","dash"]: Input.action_release(action)
	Demo.stop_attacks()
func dismiss():
	for menu in Demo.pause_stack.duplicate():
		Demo.pop_pause(menu)
		if menu != self: menu.queue_free()
func _ready():
	process_mode = Node.PROCESS_MODE_ALWAYS
	if not background: push_error("M6 mixed fixture only permits headless execution"); get_tree().quit(2); return
	get_tree().node_added.connect(record_lifecycle)
	Demo.test_mode = true
	seed(912)
	main = load("res://game/map/Main.tscn").instantiate()
	play_viewport = get_viewport()
	if background:
		# Root headless Window has no mouse; SubViewport stores engine-local input.
		play_viewport = SubViewport.new()
		play_viewport.size = Vector2i(1536,864)
		play_viewport.world_2d = get_viewport().world_2d
		play_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
		add_child(play_viewport)
		play_viewport.add_child(main)
	else: add_child(main)
	Utils.gameStart(); PlayerData.gold = 100000; PlayerData.reward_point = 9999
	LevelServer.roundVictory.connect(func():
		var boss = DemoConfig.ENCOUNTERS[LevelServer.level].get("boss", "")
		if boss != "": boss_wins[boss] = boss_wins.get(boss,0)+1)
	await wait(0.3)
	DirAccess.make_dir_recursive_absolute("res://evidence/m6-long")
	Demo.save_path = "res://evidence/m6-long/diagnostic-camp.json" if diagnostic else "res://evidence/m6-long/camp.json"
	for id in Utils.weapon_list: Demo.try_purchase("weapon",id); purchases += 1
	Demo.try_purchase("legacy","6"); Demo.try_purchase("legacy","10")
	Demo.try_purchase("attachment","110")
	Demo.try_purchase("attachment","1")
	Demo.try_purchase("attachment","9")
	for id in DemoConfig.TALENTS:
		for rank in DemoConfig.TALENTS[id].max: Demo.try_purchase("talent",id,"points")
	for id in Utils.am_dict: Demo.try_purchase("attachment",id)
	started = Time.get_ticks_msec()
	previous_frame = Time.get_ticks_usec()
	while (round_index < (3 if background_smoke else 24) if diagnostic else (Time.get_ticks_msec()-started < 1805000 or round_index < 36)):
		round_index += 1
		stop_input(); dismiss()
		if PlayerData.player_hp < PlayerData.player_hp_max: Demo.try_purchase("supply","health")
		Demo.try_purchase("supply","ammo"); purchases += 1
		var talent = DemoConfig.TALENTS.keys()[(round_index-1)%DemoConfig.TALENTS.size()]
		Demo.try_purchase("talent",talent,"gold" if round_index%2 else "points")
		var id = weapon_ids[(round_index-1)%weapon_ids.size()]
		PlayerData.switch_deadline = 0
		check(PlayerData.changeWeapon(id,true),"round "+str(round_index)+" select gun "+str(id))
		var gun = Utils.player.gun
		var optic = PlayerData.player_am_list.values()[0]
		if optic.can_equip(gun): gun.addAttachMent(optic); gun.removeAttachMent(optic); gun.addAttachMent(optic)
		var magazine = PlayerData.player_am_list.values()[1]
		if magazine.can_equip(gun): gun.addAttachMent(magazine)
		if id == 0: gun.addAttachMent(PlayerData.player_am_list.values()[2])
		# Representative high configuration, one compatible instance per slot.
		for am in PlayerData.player_am_list.values():
			if am.can_equip(gun) and am.am_id >= 110: gun.addAttachMent(am)
		Demo.open_panel(); config_events += 1
		await wait(0.6); dismiss(); await wait(0.1)
		LevelServer.town.practice(1 if round_index%2 else 3)
		await wait(0.1)
		var xp = PlayerData.player_exp
		var practice_hits = Combat.damage_events
		bot = true
		await wait(2.0)
		bot = false; stop_input()
		check(PlayerData.player_exp == xp,"round practice has no XP")
		if background: check(Combat.damage_events > practice_hits,"background real practice collision gun "+str(id))
		Demo.test_mode = false
		check(Demo.save_camp().success,"round save complete camp snapshot")
		Demo.test_mode = true
		check(Demo.load_camp(),"round restore snapshot")
		reloads += 1
		await wait(0.1)
		var epoch = LevelServer.epoch
		var stage = stage_ids[(round_index-1)%stage_ids.size()]
		check(LevelServer.town.depart(stage,true),"selected M6 encounter "+str(stage))
		check(LevelServer.state == "COMBAT" and LevelServer.epoch == epoch+1,"round depart exactly once")
		if diagnostic: LevelServer.level_time = 2.0
		bot = true; pause_done = false; force_death_done = false
		round_started = Time.get_ticks_msec()
		while LevelServer.state != "CAMP":
			await wait(0.2)
			if Time.get_ticks_msec()-round_started > 90000:
				check(false,"round watchdog exceeded 90s")
				LevelServer.return_to_camp(); break
		bot = false; stop_input(); dismiss()
		cleanup_trace.clear(); recording_cleanup = true
		await wait(2.0)
		recording_cleanup = false
		var voices = 0
		for type in ["AudioStreamPlayer","AudioStreamPlayer2D"]:
			for voice in get_tree().root.find_children("*",type,true,false):
				if voice.playing: voices += 1
		var cache = 0
		for reward in get_tree().get_nodes_in_group("reward"):
			if reward.id == 6: cache += reward.mark_dict.size()
		var sample = {"round":round_index,"seconds":(Time.get_ticks_msec()-started)/1000.0,"gun":id,"nodes":int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),"orphans":int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)),"transients":get_tree().get_nodes_in_group("combat_transient").size(),"monsters":get_tree().get_nodes_in_group("monsters").size(),"voices":voices,"marks":cache,"guns":PlayerData.player_weapon_list.size(),"attachments":PlayerData.player_am_list.size(),"damage_events":Combat.damage_events,"kills":Combat.kill_events,"revives":revives}
		sample.stage = stage
		sample.region = DemoConfig.ENCOUNTERS[stage].region
		sample.boss = DemoConfig.ENCOUNTERS[stage].get("boss","")
		sample.telemetry = persistent_telemetry()
		sample.hazards = get_tree().get_nodes_in_group("hostile_zone").size()
		sample.projectiles = get_tree().get_nodes_in_group("combat_transient").filter(func(n): return n is Bullet).size()
		sample.summons = get_tree().get_nodes_in_group("monsters").filter(func(n): return n.get("summoned") == true).size()
		sample.lifecycle_total = lifecycle_total
		sample.lifecycle_tail = lifecycle_events.duplicate(true)
		sample.remaining = []
		for entity in get_tree().get_nodes_in_group("combat_transient"):
			sample.remaining.append({"script":entity.get_script().resource_path if entity.get_script() else "","age_ms":Time.get_ticks_msec()-live_entities.get(entity.get_instance_id(),Time.get_ticks_msec()),"position":str(entity.global_position)})
		if sample.transients > 0:
			sample.cleanup_trace = cleanup_trace.duplicate(true)
			sample.native_mouse_events = mouse_events.duplicate(true)
		sample.input_shoot = Input.is_action_pressed("shoot")
		sample.bot = bot
		sample.fire_released = Demo.fire_released
		sample.generation = Utils.player.gun.action_generation
		samples.append(sample)
		check(sample.transients == 0 and sample.monsters == 0 and cache == 0,"round common camp cleanup empty")
		print("LONG ROUND ",JSON.stringify(sample))
		write_result(false)
	write_result(true)
	print("LONG COMPLETE seconds=",(Time.get_ticks_msec()-started)/1000.0," rounds=",round_index," failures=",failures)
	await Demo.quit_game()
func _process(_delta):
	if started == 0: return
	peak_hostile = maxi(peak_hostile,get_tree().get_nodes_in_group("hostile_zone").size())
	var current_entities = {}
	for entity in get_tree().get_nodes_in_group("combat_transient"):
		current_entities[entity.get_instance_id()] = live_entities.get(entity.get_instance_id(),Time.get_ticks_msec())
	live_entities = current_entities
	var now = Time.get_ticks_usec()
	if now-previous_frame > 0: frames_ms.append((now-previous_frame)/1000.0)
	previous_frame = now
	if recording_cleanup and Time.get_ticks_msec()-last_trace >= 100:
		last_trace = Time.get_ticks_msec()
		cleanup_trace.append({"ms":last_trace,"shoot":Input.is_action_pressed("shoot"),"bot":bot,"ammo":Utils.player.gun.bullets_count,"generation":Utils.player.gun.action_generation,"paused":get_tree().paused,"state":LevelServer.state,"transients":get_tree().get_nodes_in_group("combat_transient").size()})
	if not bot: return
	if background: drive_background_trigger()
	if LevelServer.state == "DEAD":
		stop_input()
		for menu in Demo.pause_stack.duplicate():
			if menu.has_method("_on_button_pressed"):
				menu._on_button_pressed(); revives += 1
		return
	if not Demo.pause_stack.is_empty(): dismiss()
	if LevelServer.state == "COMBAT":
		if not pause_done and Time.get_ticks_msec()-round_started > 12000:
			pause_done = true; pause_events += 1
			bot = false; stop_input(); Demo.open_panel()
			await wait(0.8); dismiss(); bot = true
			return
		if (round_index == 3 or (diagnostic and round_index%3 == 0)) and not force_death_done and Time.get_ticks_msec()-round_started > (1000 if diagnostic else 22000):
			force_death_done = true
			Utils.player.onHit(PlayerData.player_hp+1)
			return
	aim_clock += _delta
	if aim_clock < 0.1: return
	aim_clock = 0
	var enemies = get_tree().get_nodes_in_group("monsters").filter(func(m): return not m.is_die and not m.is_queued_for_deletion())
	sampled_enemies.append(enemies.size())
	sampled_shots.append(get_tree().get_nodes_in_group("combat_transient").filter(func(n): return n is Bullet).size())
	if enemies.is_empty(): Input.action_release("shoot"); return
	enemies.sort_custom(func(a,b): return a.global_position.distance_squared_to(Utils.player.global_position)<b.global_position.distance_squared_to(Utils.player.global_position))
	var target = enemies.front()
	var point = target.global_position-Vector2(0,9)
	if background:
		background_aim = point
		var motion = InputEventMouseMotion.new()
		motion.position = play_viewport.get_canvas_transform()*point
		play_viewport.push_input(motion,true)
	else:
		get_viewport().warp_mouse(get_viewport().get_canvas_transform()*point)
		Input.mouse_mode = Input.MOUSE_MODE_CONFINED_HIDDEN
	Demo.fire_released = true
	Input.action_press("shoot")
	if Utils.player.gun.bullets_count == 0 and not Utils.player.gun.is_reloading: Utils.player.gun.reload_ammo()
	var direction = Vector2.ZERO
	if LevelServer.state == "COMBAT" and target.global_position.distance_to(Utils.player.global_position) < 70:
		direction = target.global_position.direction_to(Utils.player.global_position).rotated(0.7)
	for pair in [["left",direction.x < -0.2],["right",direction.x > 0.2],["up",direction.y < -0.2],["down",direction.y > 0.2]]:
		if pair[1]: Input.action_press(pair[0])
		else: Input.action_release(pair[0])
func percentile(values, fraction):
	var sorted = values.duplicate(); sorted.sort()
	return sorted[mini(sorted.size()-1,int(sorted.size()*fraction))] if not sorted.is_empty() else 0
func write_result(complete):
	var result = {"content_seen":content_seen,"mechanisms_seen":mechanisms_seen,"boss_wins":boss_wins,"content_counts":{"weapons":Utils.weapon_list.size(),"attachments":Utils.am_dict.size(),"talents":DemoConfig.TALENTS.size(),"enemies":M5Content.ENEMIES.size(),"bosses":M5Content.BOSSES.size(),"regions":M5Content.REGIONS.size(),"encounters":DemoConfig.ENCOUNTERS.size()},"peak_hostile_zones":peak_hostile,"complete":complete,"seconds":(Time.get_ticks_msec()-started)/1000.0,"rounds":round_index,"failures":failures,"revives":revives,"purchases":purchases,"save_restores":reloads,"pause_events":pause_events,"configuration_panels":config_events,"gpu":RenderingServer.get_video_adapter_name(),"cpu":OS.get_processor_name(),"display":DisplayServer.get_name(),"input_backend":"engine trigger adapter" if background else "engine input in native window","max_fps":Engine.max_fps,"window":str(DisplayServer.window_get_size()),"viewport":str(play_viewport.size),"frame_ms":{"p50":percentile(frames_ms,.5),"p95":percentile(frames_ms,.95),"p99":percentile(frames_ms,.99)},"frames":frames_ms.size(),"live_enemies_p50":percentile(sampled_enemies,.5),"live_enemies_peak":sampled_enemies.max() if not sampled_enemies.is_empty() else 0,"live_projectiles_p50":percentile(sampled_shots,.5),"live_projectiles_peak":sampled_shots.max() if not sampled_shots.is_empty() else 0,"cleanup_samples":samples}
	var file = FileAccess.open(("res://evidence/m6-long/diagnostic.json" if diagnostic else "res://evidence/m6-long/result.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify(result,"\t")); file.close()

func _input(event):
	if event is InputEventMouseButton:
		mouse_events.append({"ms":Time.get_ticks_msec(),"button":event.button_index,"pressed":event.pressed})
		if mouse_events.size() > 16: mouse_events.pop_front()

func drive_background_trigger():
	var gun = Utils.player.gun
	if get_tree().paused or Utils.player.is_dead or not is_instance_valid(gun): return
	gun.look_at(background_aim)
	gun.direction = gun.gun_tip.global_position.direction_to(background_aim)
	if gun.weapon_id == 116:
		# Exercise the same accumulator as physics input, without headless mouse capture.
		gun.set_physics_process(false)
		gun.handle_thermal(Input.is_action_pressed("shoot") and Demo.fire_released,get_process_delta_time())
		if Input.is_action_pressed("shoot"): mechanisms_seen["heat_trigger_frames"] = mechanisms_seen.get("heat_trigger_frames",0)+1
		return
	# Equivalent cooldown/reload gates to BaseGun._process; headless has no captured mouse.
	if Input.is_action_pressed("shoot") and Demo.fire_released and gun.is_use and gun.can_shoot and not gun.is_reloading:
		gun.can_shoot = false
		gun.timer.start()
		if gun.bullets_count > 0: gun._shoot()
		else: gun.reload_ammo()

func persistent_telemetry() -> Dictionary:
	var nodes = get_tree().root.find_children("*","Node",true,false)
	var timers = 0; var connections = 0; var active_timers = 0
	for node in nodes:
		if node is Timer:
			timers += 1
			if not node.is_stopped(): active_timers += 1
		for descriptor in node.get_signal_list(): connections += node.get_signal_connection_list(descriptor.name).size()
	return {"active_timers":active_timers,"timers":timers,"signal_connections":connections,"resources":int(Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT)),"objects":int(Performance.get_monitor(Performance.OBJECT_COUNT)),"static_bytes":int(Performance.get_monitor(Performance.MEMORY_STATIC)),"tweens":get_tree().get_processed_tweens().size()}
func record_lifecycle(node):
	if node is BaseMonster:
		var id = node.get_meta("content_id", "practice")
		content_seen[id] = content_seen.get(id,0)+1
	if node.get("spec") is Dictionary:
		var mode = node.spec.get("mode", "unknown")
		mechanisms_seen[mode] = mechanisms_seen.get(mode,0)+1
	var path = node.get_script().resource_path if node.get_script() else ""
	if not (node is BaseMonster or node is Bullet or path in ["res://game/monster/HostileZone.gd","res://game/monster/EnemyShot.gd","res://game/effects/GravityField.gd"]): return
	var identity = {"id":node.get_instance_id(),"type":path,"created_ms":Time.get_ticks_msec(),"epoch":LevelServer.epoch}
	lifecycle_total += 1
	node.tree_exiting.connect(func():
		var record = identity.duplicate(); record.destroyed_ms=Time.get_ticks_msec(); record.destroyed_epoch=LevelServer.epoch
		lifecycle_events.append(record)
		if lifecycle_events.size()>16: lifecycle_events.pop_front())
