extends Node

## Automated browser/CI smoke run. Inert unless launched with the `--smoke`
## argument (web loader maps ?smoke=1 to engine args). Drives camp -> combat,
## a weapon switch and a real shot, printing machine-readable markers that the
## Playwright smoke script asserts on. Touches no save file.

func _ready() -> void:
	var args := OS.get_cmdline_args()
	args.append_array(OS.get_cmdline_user_args())
	if not ("--smoke" in args):
		queue_free()
		return
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
	_run.call_deferred()

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

func _process(_delta: float) -> void:
	_frame_times.append(get_process_delta_time() * 1000.0)

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

	# Ensure at least two weapons so the switch is real.
	if PlayerData.player_weapon_list.size() < 2:
		for id in ["0", "1"]:
			if not PlayerData.player_weapon_list.has(int(id)):
				PlayerData.add_weapon(Utils.weapon_list[id].instantiate())
	var ids := PlayerData.player_weapon_list.keys()
	var other: int = ids[0] if Utils.player != null and Utils.player.gun != null and ids[0] != Utils.player.gun.weapon_id else (ids[1] if ids.size() > 1 else ids[0])

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
