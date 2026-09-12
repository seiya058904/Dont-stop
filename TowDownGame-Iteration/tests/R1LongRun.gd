extends Node
# Dedicated test process/path: never reads or writes the player's camp file.
var main
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
var weapon_ids = [0,6,112,114,123,3,5,8,7,1,2,4,9]
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
	Demo.test_mode = true
	seed(912)
	main = load("res://game/map/Main.tscn").instantiate()
	add_child(main)
	Utils.gameStart()
	await wait(0.3)
	DirAccess.make_dir_recursive_absolute("res://evidence/r1-long")
	Demo.save_path = "res://evidence/r1-long/camp.json"
	for id in Utils.weapon_list: Demo.try_purchase("weapon",id); purchases += 1
	Demo.try_purchase("legacy","6"); Demo.try_purchase("legacy","10")
	Demo.try_purchase("attachment","110")
	Demo.try_purchase("attachment","1")
	Demo.try_purchase("attachment","9")
	for id in DemoConfig.TALENTS: Demo.try_purchase("talent",id,"points")
	started = Time.get_ticks_msec()
	previous_frame = Time.get_ticks_usec()
	while Time.get_ticks_msec()-started < 1205000 or round_index < 10:
		round_index += 1
		stop_input(); dismiss()
		if PlayerData.player_hp < PlayerData.player_hp_max: Demo.try_purchase("supply","health")
		Demo.try_purchase("supply","ammo"); purchases += 1
		var talent = DemoConfig.TALENTS.keys()[(round_index-1)%6]
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
		Demo.open_panel(); config_events += 1
		await wait(0.6); dismiss(); await wait(0.1)
		LevelServer.town.practice(1 if round_index%2 else 3)
		await wait(0.1)
		var xp = PlayerData.player_exp
		bot = true
		await wait(2.0)
		bot = false; stop_input()
		check(PlayerData.player_exp == xp,"round practice has no XP")
		Demo.test_mode = false
		check(Demo.save_camp().success,"round save complete camp snapshot")
		Demo.test_mode = true
		check(Demo.load_camp(),"round restore snapshot")
		reloads += 1
		await wait(0.1)
		var epoch = LevelServer.epoch
		if round_index%2: LevelServer.town._on_portal_move_in(LevelServer.town.portal_lv1)
		else: LevelServer.town.depart([1,3,4][round_index%3],true)
		check(LevelServer.state == "COMBAT" and LevelServer.epoch == epoch+1,"round depart exactly once")
		bot = true; pause_done = false; force_death_done = false
		round_started = Time.get_ticks_msec()
		while LevelServer.state != "CAMP":
			await wait(0.2)
			if Time.get_ticks_msec()-round_started > 90000:
				check(false,"round watchdog exceeded 90s")
				LevelServer.return_to_camp(); break
		bot = false; stop_input(); dismiss()
		await wait(2.0)
		var voices = 0
		for type in ["AudioStreamPlayer","AudioStreamPlayer2D"]:
			for voice in get_tree().root.find_children("*",type,true,false):
				if voice.playing: voices += 1
		var cache = 0
		for reward in get_tree().get_nodes_in_group("reward"):
			if reward.id == 6: cache += reward.mark_dict.size()
		var sample = {"round":round_index,"seconds":(Time.get_ticks_msec()-started)/1000.0,"gun":id,"nodes":int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),"orphans":int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)),"transients":get_tree().get_nodes_in_group("combat_transient").size(),"monsters":get_tree().get_nodes_in_group("monsters").size(),"voices":voices,"marks":cache,"guns":PlayerData.player_weapon_list.size(),"attachments":PlayerData.player_am_list.size(),"damage_events":Combat.damage_events,"kills":Combat.kill_events,"revives":revives}
		samples.append(sample)
		check(sample.transients == 0 and sample.monsters == 0 and cache == 0,"round common camp cleanup empty")
		print("LONG ROUND ",JSON.stringify(sample))
		write_result(false)
	write_result(true)
	print("LONG COMPLETE seconds=",(Time.get_ticks_msec()-started)/1000.0," rounds=",round_index," failures=",failures)
	await Demo.quit_game()
func _process(_delta):
	if started == 0: return
	var now = Time.get_ticks_usec()
	if now-previous_frame > 0: frames_ms.append((now-previous_frame)/1000.0)
	previous_frame = now
	if not bot: return
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
		if round_index == 3 and not force_death_done and Time.get_ticks_msec()-round_started > 22000:
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
	var result = {"complete":complete,"seconds":(Time.get_ticks_msec()-started)/1000.0,"rounds":round_index,"failures":failures,"revives":revives,"purchases":purchases,"save_restores":reloads,"pause_events":pause_events,"configuration_panels":config_events,"gpu":RenderingServer.get_video_adapter_name(),"cpu":OS.get_processor_name(),"display":DisplayServer.get_name(),"window":str(DisplayServer.window_get_size()),"viewport":str(get_viewport().size),"frame_ms":{"p50":percentile(frames_ms,.5),"p95":percentile(frames_ms,.95),"p99":percentile(frames_ms,.99)},"frames":frames_ms.size(),"live_enemies_p50":percentile(sampled_enemies,.5),"live_enemies_peak":sampled_enemies.max() if not sampled_enemies.is_empty() else 0,"live_projectiles_p50":percentile(sampled_shots,.5),"live_projectiles_peak":sampled_shots.max() if not sampled_shots.is_empty() else 0,"cleanup_samples":samples}
	var file = FileAccess.open("res://evidence/r1-long/result.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(result,"\t")); file.close()
