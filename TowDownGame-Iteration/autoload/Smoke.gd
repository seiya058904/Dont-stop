extends Node

## Automated browser/CI smoke run. Inert unless launched with the `--smoke`
## argument (web loader maps ?smoke=1 to engine args). Drives camp -> combat,
## a weapon switch and a real shot, printing machine-readable markers that the
## Playwright smoke script asserts on. Touches no save file.
##
## `--e2e` additionally enters a driver-friendly mode used by
## tools/pointer-lock-e2e.js: the player is invincible (real inputs are tested
## against a live character) and the game streams aim/gun/projectile state so
## the external script can assert on real Pointer Lock behaviour.

var e2e := false
var _transients := 0

func _ready() -> void:
	var args := OS.get_cmdline_args()
	args.append_array(OS.get_cmdline_user_args())
	if not ("--smoke" in args):
		# Stay instantiated (inert) so autoload cross-references stay valid.
		return
	e2e = "--e2e" in args
	print("[smoke] user_dir=", OS.get_user_data_dir())
	print("[smoke] renderer=", ProjectSettings.get_setting("rendering/renderer/rendering_method"))
	if FileAccess.file_exists("user://camp-v1.json"):
		var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("user://camp-v1.json"))
		if data is Dictionary:
			print("[smoke] save_state gold=\"%s\" equipped=\"%s\"" % [str(data.get("gold")), str(data.get("equipped"))])
		else:
			print("[smoke] save_state none")
	else:
		print("[smoke] save_state none")
	var stutter := "--stutter" in args
	_run.call_deferred()
	if e2e:
		_e2e_stream.call_deferred()
	if stutter:
		_stutter_run.call_deferred()

func e2e_invincible() -> bool:
	return e2e

## Track combat transients; report new projectile velocity to the E2E driver.
func _e2e_stream() -> void:
	print("[e2e] mode=on")
	# The external driver starts clicking once it sees "ready"; make sure the
	# camp -> combat transition (and its pause-panel blink) is fully done.
	await _wait_until(func(): return LevelServer.state == "COMBAT", 300000)
	await _wait_until(func(): return get_tree().get_nodes_in_group("monsters").size() > 0, 60000)
	await _wait_until(func(): return Demo.pause_stack.is_empty(), 30000)
	print("[e2e] ready")
	print("[e2e] loop-armed")
	var deadline := Time.get_ticks_msec() + 300000
	var tick := 0
	while Time.get_ticks_msec() < deadline:
		await get_tree().create_timer(0.25).timeout
		tick += 1
		if tick % 4 == 0:
			print("[e2e] alive tick=%d" % tick)
		var gunrot := 999.0
		var gunid := -1
		if Utils.player != null and Utils.player.gun != null:
			gunrot = rad_to_deg(Utils.player.gun.rotation)
			gunid = Utils.player.gun.weapon_id
		print("[e2e] mousemode=%d aimvp=%s aimworld=%s gunrot=%.1f gunid=%d playerpos=%s hp=%.1f paused=%s panels=%d" % [
			Input.mouse_mode, Utils.get_aim_viewport_position(), Utils.get_aim_world_position(),
			gunrot, gunid,
			Utils.player.global_position if Utils.player != null else Vector2.ZERO,
			PlayerData.player_hp if Utils.player != null else 0.0,
			str(not Demo.pause_stack.is_empty()),
			Demo.pause_stack.size()])

## Windows cold-path probe: first fire per weapon class + steady-state stats.
func _stutter_run() -> void:
	await _wait_until(func(): return LevelServer.state == "COMBAT", 300000)
	await _wait_until(func(): return get_tree().get_nodes_in_group("monsters").size() > 0, 60000)
	print("[stutter] combat-ready monsters=%d" % get_tree().get_nodes_in_group("monsters").size())
	var classes := ["0", "1", "2", "3", "4", "5", "6", "7", "8", "9", "112", "114", "123"]
	for id in classes:
		if not Utils.weapon_list.has(id):
			continue
		if not PlayerData.player_weapon_list.has(int(id)):
			PlayerData.add_weapon(Utils.weapon_list[id].instantiate())
		PlayerData.changeWeapon(int(id), true)
		await get_tree().create_timer(0.9).timeout
		# Clearing a round can open the reward panel (paused); close it so the
		# probe can re-enter combat.
		if not Demo.pause_stack.is_empty():
			for menu in Demo.pause_stack.duplicate():
				menu.queue_free()
				Demo.pop_pause(menu)
			await get_tree().create_timer(0.5).timeout
		if LevelServer.state == "CAMP":
			LevelServer.town.depart(1, true)
			await _wait_until(func(): return LevelServer.state == "COMBAT", 60000)
		if not Demo.pause_stack.is_empty():
			for menu in Demo.pause_stack.duplicate():
				menu.queue_free()
				Demo.pop_pause(menu)
		_mark_frames()
		Input.action_press("shoot")
		await get_tree().create_timer(0.35).timeout
		Input.action_release("shoot")
		_report_frames("firstshot-gun" + id, 40)
		await get_tree().create_timer(0.25).timeout
	# Reload cold path with the current gun.
	_mark_frames()
	Input.action_press("reload")
	await get_tree().create_timer(0.1).timeout
	Input.action_release("reload")
	await get_tree().create_timer(2.5).timeout
	_report_frames("first-reload", 60)
	# Steady-state window with periodic firing.
	var sample: Array[float] = []
	var t_end := Time.get_ticks_msec() + 15000
	while Time.get_ticks_msec() < t_end:
		sample.append(get_process_delta_time() * 1000.0)
		if randi() % 40 == 0:
			Input.action_press("shoot")
		if randi() % 37 == 0:
			Input.action_release("shoot")
		if not Demo.pause_stack.is_empty():
			for menu in Demo.pause_stack.duplicate():
				menu.queue_free()
				Demo.pop_pause(menu)
		if LevelServer.state == "CAMP":
			LevelServer.town.depart(1, true)
		await get_tree().process_frame
	var srt := sample.duplicate(); srt.sort()
	var sum := 0.0
	for v in sample: sum += v
	print("[stutter] steady n=%d p50=%.1f p95=%.1f p99=%.1f max=%.1f avg=%.1f" % [
		srt.size(), srt[int(srt.size() * 0.50)], srt[int(srt.size() * 0.95)],
		srt[int(srt.size() * 0.99)], srt.back(), sum / sample.size()])
	print("[stutter] done")
	get_tree().quit(0)

func _wait_until(predicate: Callable, timeout_ms: int) -> void:
	var deadline := Time.get_ticks_msec() + timeout_ms
	while Time.get_ticks_msec() < deadline:
		if predicate.call():
			return
		await get_tree().create_timer(0.5).timeout

func _enter_camp_from_title() -> void:
	# Reproduce the title screen "开始游戏" behaviour (ui/MainUI.gd) without UI.
	if not Utils.is_game_start:
		Utils.gameStart()
		Demo.open_panel()
		await get_tree().create_timer(1.0).timeout
		for menu in Demo.pause_stack.duplicate():
			menu.queue_free()
			Demo.pop_pause(menu)

var _frame_times: Array[float] = []
var _mark := -1

var _last_mode := -1
func _process(_delta: float) -> void:
	_frame_times.append(get_process_delta_time() * 1000.0)
	if e2e:
		_track_transients()
		if Input.mouse_mode != _last_mode:
			_last_mode = Input.mouse_mode
			print("[e2e] mode-change mousemode=%d paused=%s t=%.1f" % [
				_last_mode, str(not Demo.pause_stack.is_empty()),
				Time.get_ticks_msec() / 1000.0])

func _track_transients() -> void:
	var nodes := get_tree().get_nodes_in_group("combat_transient")
	if nodes.size() > _transients:
		for node in nodes:
			if "velocity" in node and is_instance_valid(node) and not node.has_meta("e2e_reported"):
				node.set_meta("e2e_reported", true)
				var v: Vector2 = node.velocity
				print("[e2e] proj vx=%.1f vy=%.1f speed=%.1f" % [v.x, v.y, v.length()])
	_transients = nodes.size()

func _mark_frames() -> void:
	_mark = _frame_times.size()

func _report_frames(label: String, window := 30) -> void:
	if _mark < 0: return
	var start := maxi(0, _mark)
	var recent := _frame_times.slice(start, mini(_frame_times.size(), start + window))
	var later := _frame_times.slice(mini(_frame_times.size(), start + window), mini(_frame_times.size(), start + window + 60))
	if recent.is_empty(): return
	var sorted := recent.duplicate(); sorted.sort()
	var lsort := later.duplicate(); lsort.sort()
	print("[smoke-frames] %s first%d max=%.1f p95=%.1f | next60 max=%.1f p95=%.1f" % [
		label, recent.size(), sorted.back(),
		sorted[int(sorted.size() * 0.95) - 1] if sorted.size() > 1 else sorted[0],
		lsort.back() if not lsort.is_empty() else 0.0,
		lsort[int(lsort.size() * 0.95) - 1] if lsort.size() > 2 else (lsort[0] if not lsort.is_empty() else 0.0)])

func _run() -> void:
	await get_tree().create_timer(3.0).timeout
	await _enter_camp_from_title()
	await get_tree().create_timer(1.5).timeout
	if not Utils.is_game_start:
		print("[smoke] FAIL boot-timeout"); get_tree().quit(1); return
	print("[smoke] stage=camp state=", LevelServer.state)

	# Ensure at least two weapons so the switch is real (scripted mode only;
	# the E2E driver keeps the default gun so projectile direction is known).
	if not e2e and PlayerData.player_weapon_list.size() < 2:
		for id in ["0", "1"]:
			if not PlayerData.player_weapon_list.has(int(id)):
				PlayerData.add_weapon(Utils.weapon_list[id].instantiate())
	var ids := PlayerData.player_weapon_list.keys()
	var other: int = ids[0] if Utils.player != null and Utils.player.gun != null and ids[0] != Utils.player.gun.weapon_id else (ids[1] if ids.size() > 1 else ids[0])

	# E2E keeps the default gun; a fresh profile restores no weapon at all,
	# which makes LevelServer.can_start() (and therefore depart) fail.
	if e2e and Utils.player.gun == null:
		PlayerData.add_weapon(Utils.weapon_list["0"].instantiate())
		PlayerData.changeWeapon(0, true)

	# Click-to-capture gesture (web): release then re-request gameplay mouse mode.
	Utils.set_gameplay_mouse_mode()
	await get_tree().create_timer(0.5).timeout

	var ok_depart: bool = LevelServer.town.depart(1, true)
	_mark_frames()
	print("[smoke] depart=", ok_depart)
	# Software-GL CI runners can spend minutes compiling the first combat
	# shaders; poll instead of sleeping a fixed window.
	await _wait_until(func(): return LevelServer.state == "COMBAT", 300000)
	# Round start spawns monsters asynchronously; give them a moment.
	await _wait_until(func(): return get_tree().get_nodes_in_group("monsters").size() > 0, 60000)
	_report_frames("first-combat")
	var monsters := get_tree().get_nodes_in_group("monsters").size()
	print("[smoke] stage=combat state=", LevelServer.state, " monsters=", monsters)
	var combat_ok := LevelServer.state == "COMBAT" and monsters > 0

	# E2E driver mode: the external Playwright script performs all real inputs
	# (pointer lock, aim sweeps, shots, pause/resume, WASD). Do not interfere.
	if e2e:
		print("[smoke] result=", "PASS" if ok_depart and combat_ok else "FAIL")
		return
	# Stutter probe mode: _stutter_run takes over from here.
	if "--stutter" in OS.get_cmdline_args() or "--stutter" in OS.get_cmdline_user_args():
		print("[smoke] result=", "PASS" if ok_depart and combat_ok else "FAIL")
		return

	var ok_switch: bool = PlayerData.changeWeapon(other, true)
	_mark_frames()
	await get_tree().create_timer(1.2).timeout
	_report_frames("first-switch")
	print("[smoke] switch=", ok_switch, " gun=", Utils.player.gun.weapon_id if Utils.player.gun != null else -1)

	Utils.set_gameplay_mouse_mode()
	await get_tree().create_timer(0.3).timeout
	var transient_before := get_tree().get_nodes_in_group("combat_transient").size()
	_mark_frames()
	Input.action_press("shoot")
	await get_tree().create_timer(0.6).timeout
	Input.action_release("shoot")
	_report_frames("first-shot")
	var transient_after := get_tree().get_nodes_in_group("combat_transient").size()
	print("[smoke] fire transient=", transient_before, "->", transient_after)

	# Second round: same actions again (cold vs warm comparison).
	var other2: int = ids[0] if other != ids[0] else ids[1]
	PlayerData.changeWeapon(other2, true)
	_mark_frames()
	await get_tree().create_timer(1.2).timeout
	_report_frames("second-switch")
	_mark_frames()
	Input.action_press("shoot")
	await get_tree().create_timer(0.6).timeout
	Input.action_release("shoot")
	_report_frames("second-shot")

	var passed := ok_depart and combat_ok and ok_switch
	# 10s steady-state frame-time sample while combat runs.
	var sample: Array[float] = []
	var t_end := Time.get_ticks_msec() + 10000
	while Time.get_ticks_msec() < t_end:
		sample.append(get_process_delta_time() * 1000.0)
		await get_tree().process_frame
	var s := sample.duplicate(); s.sort()
	var enemies := get_tree().get_nodes_in_group("monsters").size()
	print("[smoke-perf] n=%d p50=%.1f p95=%.1f p99=%.1f max=%.1f fps=%.1f enemies=%d" % [
		s.size(), s[int(s.size()*0.50)], s[int(s.size()*0.95)], s[int(s.size()*0.99)], s.back(),
		1000.0 / (s.reduce(func(a,b): return a+b) / s.size()), enemies])
	print("[smoke] done pass=", passed)
	print("[smoke] result=", "PASS" if passed else "FAIL")
	if not passed:
		get_tree().quit(1)
