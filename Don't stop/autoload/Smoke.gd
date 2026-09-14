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
		# Stay instantiated (inert) so autoload cross-references stay valid, but
		# take the node out of idle processing: _process appends a frame sample
		# every frame and nothing reads it in a real launch, so leaving it on
		# would grow an Array for the whole session.
		set_process(false)
		return
	e2e = "--e2e" in args
	if e2e:
		# Track projectile spawns even while the tree is paused (round restarts).
		process_mode = Node.PROCESS_MODE_ALWAYS
		get_tree().node_added.connect(func(node: Node) -> void:
			if node is CharacterBody2D and "velocity" in node and node.get_script() != null:
				var path: String = (node.get_script() as Script).resource_path
				if path.contains("bullets/") or path.contains("other/"):
					_pending_proj.append(node))
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
	var tour := "--tour" in args
	_run.call_deferred()
	if e2e:
		_e2e_stream.call_deferred()
		_e2e_camp_probe.call_deferred()
	if stutter:
		_stutter_run.call_deferred()
	if tour:
		_tour_run.call_deferred()

## Locator for the acceptance driver.
##
## Phase A of tools/web-aim-e2e.js runs against the REAL entry point with no test
## flags, so it cannot ask the engine anything. It therefore needs to know where
## the camp panel's own "返回 [Esc]" button is on screen, in order to close the
## panel with a genuine mouse click instead of pressing Esc. This prints that
## rectangle (design/viewport coordinates) once, from a separate diagnostic page
## load, and performs no action itself.
func _e2e_camp_probe() -> void:
	var deadline := Time.get_ticks_msec() + 120000
	while Time.get_ticks_msec() < deadline:
		await get_tree().create_timer(0.05).timeout
		if not is_instance_valid(Demo.ui): continue
		# The panel is built in _ready() and laid out by the container pass that
		# follows it, so reading global_position immediately returns the default
		# (0,0)-ish slot. Let the layout settle, then read.
		for i in 3:
			await get_tree().process_frame
		var button := _find_button(Demo.ui, "返回")
		if button == null or button.size.x <= 10.0: continue
		var rect := Rect2(button.global_position, button.size)
		print("[e2e] camp-close-button text=\"%s\" x=%.1f y=%.1f w=%.1f h=%.1f cx=%.1f cy=%.1f" % [
			button.text, rect.position.x, rect.position.y, rect.size.x, rect.size.y,
			rect.get_center().x, rect.get_center().y])
		return

func _find_button(node: Node, prefix: String) -> Button:
	if node is Button and (node as Button).text.begins_with(prefix):
		return node
	for child in node.get_children():
		var found := _find_button(child, prefix)
		if found != null: return found
	return null

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
	# Freeze the round into a deterministic sandbox, only AFTER a real combat
	# round was observed. The countdown is the only way a normal round ends and
	# victory raises the reward scoreboard, which pauses the tree and drops
	# Pointer Lock mid-assertion; live monsters additionally shove the test
	# character around during the WASD and aim sweeps.
	LevelServer.timerStop()
	for monster in get_tree().get_nodes_in_group("monsters"):
		monster.queue_free()
	for transient in get_tree().get_nodes_in_group("combat_transient"):
		transient.queue_free()
	await get_tree().process_frame
	print("[e2e] round-frozen state=%s softcursor=%d" % [LevelServer.state, _e2e_software_cursor_count()])
	print("[e2e] ready")
	print("[e2e] loop-armed")
	var deadline := Time.get_ticks_msec() + 1800000
	var tick := 0
	while Time.get_ticks_msec() < deadline:
		if Time.get_ticks_msec() > deadline - 1000:
			print("[e2e] stream-expired")
		await get_tree().create_timer(0.25).timeout
		tick += 1
		var gunrot := 999.0
		var guntiprot := 999.0
		var gunid := -1
		var bullets := -1
		if Utils.player != null and Utils.player.gun != null:
			# GLOBAL rotation: the gun hangs under body/GunRoot and the hero flips
			# body.scale.x to face left, so the local rotation is mirrored.
			gunrot = rad_to_deg(Utils.player.gun.global_rotation)
			guntiprot = rad_to_deg(Utils.player.gun.gun_tip.global_rotation)
			gunid = Utils.player.gun.weapon_id
			bullets = Utils.player.gun.bullets_count
		var bullets_max: int = Utils.player.gun.bullets_max_count if Utils.player != null and Utils.player.gun != null else -1
		print("[e2e] state=%s mousemode=%d vp=%s aimvp=%s aimworld=%s crh=%s gunrot=%.1f guntiprot=%.1f gunid=%d playerpos=%s hp=%.1f paused=%s panels=%d fr=%s bullets=%d/%d" % [
			LevelServer.state, Input.mouse_mode,
			get_viewport().get_visible_rect().size,
			Utils.get_aim_viewport_position(), Utils.get_aim_world_position(),
			_e2e_crosshair_centre(),
			gunrot, guntiprot, gunid,
			Utils.player.global_position if Utils.player != null else Vector2.ZERO,
			PlayerData.player_hp if Utils.player != null else 0.0,
			str(not Demo.pause_stack.is_empty()),
			Demo.pause_stack.size(),
			str(Demo.fire_released),
			bullets, bullets_max])

## The product crosshair is the only cursor the player may see during Pointer
## Lock. Report where it actually sits so the driver can prove it agrees with
## the aim provider instead of trusting a comment.
func _e2e_crosshair_centre() -> Vector2:
	if not is_instance_valid(Utils.canvasLayer): return Vector2.INF
	var crosshair = Utils.canvasLayer.get_node_or_null("TextureRect")
	if crosshair == null: return Vector2.INF
	return crosshair.global_position + crosshair.size / 2.0

## Count scene-tree sprites still faking an OS pointer with the desktop cursor
## texture. v1.0.1 drew one on Web; the driver asserts this is zero.
func _e2e_software_cursor_count() -> int:
	var found := 0
	for node in get_tree().root.find_children("*", "Sprite2D", true, false):
		var texture = node.get("texture")
		if texture != null and (texture as Texture2D).resource_path == "res://Sprites/1 cursor.png":
			found += 1
	return found

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

## `--tour`: walk the product screens so an external driver can capture Web
## visual evidence and attribute frame time per screen. Test-only (--smoke --tour).
## Each step prints a marker and then dwells long enough for a screenshot.
func _tour_mark(name: String) -> void:
	print("[tour] screen=%s" % name)

func _tour_dwell(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout

func _tour_close_panels() -> void:
	for menu in Demo.pause_stack.duplicate():
		menu.queue_free()
		Demo.pop_pause(menu)

## Test-only: give the tour the same "everything purchased" state a long-term
## player would have, so the owned/activated label variants get captured too.
## Touches no save file (Demo.test_mode is set by the smoke driver).
func _tour_grant_everything() -> void:
	if LevelServer.state != "CAMP":
		LevelServer.state = "CAMP"
	PlayerData.gold = 999999
	PlayerData.reward_point = 9999
	for id in Utils.am_dict:
		Demo.try_purchase("attachment", id)
	for id in Utils.weapon_list:
		Demo.try_purchase("weapon", id)
	for id in DemoConfig.TALENTS:
		var guard := 0
		while Demo.rank(id) < DemoConfig.TALENTS[id].max and guard < 12:
			Demo.try_purchase("talent", id, "points")
			guard += 1

func _tour_run() -> void:
	_tour_mark("title")
	await _tour_dwell(4.0)
	await _enter_camp_from_title()
	await _wait_until(func(): return LevelServer.state == "CAMP", 180000)
	await _wait_until(func(): return Demo.pause_stack.is_empty(), 60000)
	await _tour_dwell(1.5)
	_tour_mark("camp")
	await _tour_dwell(3.0)

	# Camp panel: CJK text, numbers, icon and tooltip scaling.
	Demo.open_panel()
	await _wait_until(func(): return is_instance_valid(Demo.ui) and Demo.ui.is_node_ready(), 60000)
	await _tour_dwell(1.5)
	_tour_mark("shop")
	await _tour_dwell(3.0)
	Demo.ui.switch_tab("attachment")
	await _tour_dwell(1.2)
	_tour_mark("upgrades")
	await _tour_dwell(3.0)
	Demo.ui.switch_tab("talent")
	await _tour_dwell(1.2)
	_tour_mark("talents")
	await _tour_dwell(3.0)

	# Owned pass. Half of these labels have an owned/activated variant that a
	# fresh profile never renders ("activated" markers, equipped markers,
	# purchased prices), and those variants are exactly where the missing-glyph
	# boxes used to show up. Buy everything first, then re-shoot the same tabs.
	_tour_grant_everything()
	await _tour_dwell(1.2)
	Demo.ui.switch_tab("weapon")
	await _tour_dwell(1.2)
	_tour_mark("shop-owned")
	await _tour_dwell(3.0)
	Demo.ui.switch_tab("attachment")
	await _tour_dwell(1.2)
	_tour_mark("upgrades-owned")
	await _tour_dwell(3.0)
	Demo.ui.switch_tab("talent")
	await _tour_dwell(1.2)
	_tour_mark("talents-owned")
	await _tour_dwell(3.0)
	_tour_close_panels()
	await _tour_dwell(0.8)

	Demo.open_stats()
	await _tour_dwell(2.0)
	_tour_mark("stats")
	await _tour_dwell(3.0)
	_tour_close_panels()
	await _tour_dwell(0.8)

	# Training dummies (camp practice targets).
	if is_instance_valid(LevelServer.town):
		LevelServer.town.practice(3)
	await _tour_dwell(2.0)
	_tour_mark("training")
	await _tour_dwell(3.0)
	if is_instance_valid(LevelServer.town):
		LevelServer.town.clear_practice()
	await _tour_dwell(0.8)

	# Normal combat, then a burst that produces muzzle VFX and damage numbers.
	Utils.set_gameplay_mouse_mode()
	LevelServer.town.depart(1, true)
	await _wait_until(func(): return LevelServer.state == "COMBAT", 180000)
	await _wait_until(func(): return get_tree().get_nodes_in_group("monsters").size() > 0, 60000)
	await _tour_dwell(2.5)
	_tour_mark("combat")
	await _tour_dwell(3.0)
	Input.action_press("shoot")
	await _tour_dwell(1.0)
	_tour_mark("shooting")
	await _tour_dwell(3.0)
	Input.action_release("shoot")
	await _tour_dwell(0.8)

	Demo.open_panel()
	await _tour_dwell(2.0)
	_tour_mark("pause")
	await _tour_dwell(3.0)
	_tour_close_panels()
	await _tour_dwell(1.0)

	# Boss encounter (stage 10 = B01).
	LevelServer.return_to_camp()
	await _wait_until(func(): return LevelServer.state == "CAMP", 60000)
	await _tour_dwell(1.2)
	Utils.set_gameplay_mouse_mode()
	LevelServer.town.depart(10, true)
	await _wait_until(func(): return LevelServer.state == "COMBAT", 180000)
	await _tour_dwell(3.0)
	Input.action_press("shoot")
	await _tour_dwell(1.5)
	Input.action_release("shoot")
	await _tour_dwell(1.5)
	_tour_mark("boss")
	await _tour_dwell(4.0)
	_tour_mark("done")
	print("[tour] complete")
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

## Frame sampling is armed only for the duration of one measurement window.
## Keeping a session-long array made the probe itself an allocator (and skewed
## the very frame times it was reporting), so sampling is bounded to one
## window + the comparison window that follows it.
var _frame_times: Array[float] = []
var _sampling := false

var _pending_proj: Array = []
var _last_mode := -1
func _process(_delta: float) -> void:
	if _sampling:
		_frame_times.append(get_process_delta_time() * 1000.0)
	if e2e:
		_track_transients()
		if Input.mouse_mode != _last_mode:
			_last_mode = Input.mouse_mode
			print("[e2e] mode-change mousemode=%d paused=%s t=%.1f" % [
				_last_mode, str(not Demo.pause_stack.is_empty()),
				Time.get_ticks_msec() / 1000.0])

func _track_transients() -> void:
	# Bullet.fire() assigns velocity one frame after the node enters the tree, so
	# report on the first frame the projectile is actually moving. A projectile
	# that never moves is reported as stalled instead of being fed to the driver
	# as a zero-velocity "direction".
	var still: Array = []
	for node in _pending_proj:
		if not is_instance_valid(node): continue
		if node.velocity.length() > 0.1:
			# `aim` is the provider's aim angle towards the gun tip on the frame
			# the projectile is reported, so the driver can prove the projectile
			# really left along the unified aim instead of merely "somewhere".
			var aim := 999.0
			if Utils.player != null and Utils.player.gun != null:
				aim = rad_to_deg((Utils.get_aim_world_position() - Utils.player.gun.gun_tip.global_position).angle())
			print("[e2e] proj vx=%.1f vy=%.1f speed=%.1f aim=%.1f" % [
				node.velocity.x, node.velocity.y, node.velocity.length(), aim])
		elif node.get_meta("e2e_waited", 0) < 40:
			node.set_meta("e2e_waited", node.get_meta("e2e_waited", 0) + 1)
			still.append(node)
		else:
			print("[e2e] proj-stalled")
	_pending_proj = still

func _mark_frames() -> void:
	_frame_times.clear()
	_sampling = true

func _report_frames(label: String, window := 30) -> void:
	_sampling = false
	if _frame_times.is_empty(): return
	var recent := _frame_times.slice(0, mini(_frame_times.size(), window))
	var later := _frame_times.slice(mini(_frame_times.size(), window), mini(_frame_times.size(), window + 60))
	if recent.is_empty(): return
	var sorted := recent.duplicate(); sorted.sort()
	var lsort := later.duplicate(); lsort.sort()
	print("[smoke-frames] %s first%d max=%.1f p95=%.1f | next60 max=%.1f p95=%.1f" % [
		label, recent.size(), sorted.back(),
		sorted[int(sorted.size() * 0.95) - 1] if sorted.size() > 1 else sorted[0],
		lsort.back() if not lsort.is_empty() else 0.0,
		lsort[int(lsort.size() * 0.95) - 1] if lsort.size() > 2 else (lsort[0] if not lsort.is_empty() else 0.0)])

func _run() -> void:
	# The visual tour drives the product screens itself; the scripted smoke
	# sequence would fight it over rounds and panels.
	if "--tour" in OS.get_cmdline_args() or "--tour" in OS.get_cmdline_user_args():
		return
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
	# A standalone run would otherwise sit at the title screen forever after a
	# PASS, which makes the exported binary useless to any caller. In a browser the
	# driver owns the page lifecycle (it keeps interacting with the live page after
	# the markers), so the Web build must stay running.
	if not OS.has_feature("web"):
		get_tree().quit(0 if passed else 1)
