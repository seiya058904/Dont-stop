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
##
## `--probe` (web loader maps ?probe=1) is a separate, strictly READ-ONLY
## observation channel for tests that must drive the REAL session. Unlike
## --smoke and --e2e it changes nothing: it stops no timer, frees no node,
## synthesises no input and writes no game state. See _start_probe().

var e2e := false
var probe := false
var _transients := 0

func _ready() -> void:
	var args := OS.get_cmdline_args()
	args.append_array(OS.get_cmdline_user_args())
	probe = "--probe" in args
	if not ("--smoke" in args) and not probe:
		# Stay instantiated (inert) so autoload cross-references stay valid, but
		# take the node out of idle processing: _process appends a frame sample
		# every frame and nothing reads it in a real launch, so leaving it on
		# would grow an Array for the whole session.
		set_process(false)
		return
	if probe:
		_start_probe()
	# A probe-only launch must not run the scripted smoke sequence, which would
	# fight the driver over rounds and panels.
	if not ("--smoke" in args):
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
	print("[smoke] save_state %s" % _save_state_line())
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
		# The pause panel is also the only route to the in-game leave entry, so the
		# driver needs the rectangle of its "设置" button to walk the real path with
		# real clicks instead of guessing a position.
		_report_button("camp-settings-button", Demo.ui, "设置")
		# Second read-only locator: the in-game entry that leaves the session. The
		# acceptance driver needs its rectangle to click it with a real mouse, since
		# the normal-entry phase runs without any diagnostic help.
		await _report_leave_entry()
		return

func _report_button(tag: String, root: Node, prefix: String) -> void:
	var button := _find_button(root, prefix)
	if button == null or button.size.x <= 10.0:
		print("[e2e] %s none" % tag)
		return
	var rect := Rect2(button.global_position, button.size)
	print("[e2e] %s text=\"%s\" x=%.1f y=%.1f w=%.1f h=%.1f cx=%.1f cy=%.1f" % [
		tag, button.text, rect.position.x, rect.position.y, rect.size.x, rect.size.y,
		rect.get_center().x, rect.get_center().y])

func _report_leave_entry() -> void:
	for menu in Demo.pause_stack.duplicate():
		Demo.pop_pause(menu)
		if is_instance_valid(menu): menu.queue_free()
	await get_tree().create_timer(0.3).timeout
	var settings_script := load("res://ui/DemoSettings.gd")
	print("[e2e] leave-entry diag script=%s children_before=%d" % [
		str(settings_script != null),
		Utils.canvasLayer.get_child_count() if is_instance_valid(Utils.canvasLayer) else -1])
	Demo.open_settings()
	await get_tree().create_timer(0.6).timeout
	# The panel the player reaches through the pause menu, i.e. the exact object the
	# driver must click on. It is looked up by script rather than through the pause
	# stack: the stack is emptied by the lines above, and an earlier version that
	# trusted the whole canvas layer reported the dormant MainUI/SettingUI copy
	# instead. Both mistakes produced a plausible-looking rectangle for a control
	# that is not the one on screen.
	var root: Node = null
	var canvas_ok := is_instance_valid(Utils.canvasLayer)
	var seen_children: Array = []
	if canvas_ok:
		for child in Utils.canvasLayer.get_children():
			seen_children.append("%s:%s" % [
				child.name, str(child.get_script().resource_path) if child.get_script() != null else "no-script"])
			if child.get_script() == settings_script: root = child
	print("[e2e] leave-entry diag canvas=%s pause=%d root=%s children=%s" % [
		str(canvas_ok), Demo.pause_stack.size(), str(root), str(seen_children.slice(0, 10))])
	if root == null:
		print("[e2e] leave-entry none (no settings panel on screen)")
		return
	print("[e2e] leave-entry panel=%s" % root.name)
	var inventory: Array = []
	_collect_button_texts(root, inventory)
	print("[e2e] leave-entry inventory=%s" % str(inventory.slice(0, 14)))
	# On Web the entry is labelled "返回主菜单" and only exists inside a running
	# session, so the driver has to know which state this rectangle describes.
	print("[e2e] leave-entry context is_game_start=%s web=%s" % [
		str(Utils.is_game_start), str(OS.has_feature("web"))])
	_report_button("settings-back-button", root, "返回")
	for prefix in ["返回主菜单", "结束游戏", "退出游戏", "退出"]:
		var button := _find_button(root, prefix)
		if button == null or button.size.x <= 10.0: continue
		var rect := Rect2(button.global_position, button.size)
		print("[e2e] leave-entry text=\"%s\" x=%.1f y=%.1f w=%.1f h=%.1f cx=%.1f cy=%.1f" % [
			button.text, rect.position.x, rect.position.y, rect.size.x, rect.size.y,
			rect.get_center().x, rect.get_center().y])
		return
	# Nothing found: say what IS on screen, so the next iteration does not have to
	# guess again.
	var seen: Array = []
	_collect_button_texts(root, seen)
	print("[e2e] leave-entry none buttons=%s" % str(seen.slice(0, 12)))

func _collect_button_texts(node: Node, out: Array) -> void:
	if node is Button and (node as Button).text != "":
		# Visibility is part of the inventory: a dormant button and a live one used
		# to be indistinguishable here, which is how the wrong rectangle got picked.
		var button := node as Button
		out.append("%s[%s,%.0fx%.0f]" % [
			button.text, "shown" if button.is_visible_in_tree() else "hidden",
			button.size.x, button.size.y])
	for child in node.get_children():
		_collect_button_texts(child, out)

## Only buttons the player can actually see are reported. The canvas layer also
## holds dormant UI (MainUI/SettingUI ships with visible = false and no code path
## shows it), and its "Exit Game" button is laid out at 304,199 -> 407,227, i.e.
## exactly the rectangle the acceptance driver used to click. It found that hidden
## button instead of the live in-game panel and would have clicked empty space.
func _find_button(node: Node, prefix: String) -> Button:
	if node is Button and (node as Button).is_visible_in_tree() and (node as Button).text.begins_with(prefix):
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

## ---------------------------------------------------------------------------
## Read-only observation channel (?probe=1 -> --probe).
##
## Two measurements drove this. First, the Web export uses the nothreads
## template, so the game loop owns the browser main thread and every
## page.screenshot()/evaluate() has to wait for a slot on it: the identical
## screenshot measured ~32 ms on an idle developer machine and ~30 s per call on
## a GitHub runner, and that gap is where the pixel-driven menu test's 84
## minutes went. Second, a pixel diff cannot say WHY a frame changed, so "a
## panel is open" and "the magazine is empty" had to be inferred from pixels
## instead of read.
##
## Everything below observes. The projectile counter counts nodes the engine
## itself added; the frame counter is this node's own idle callback, which is
## why its process_mode is PAUSABLE.
var _probe_frames := 0
var _probe_proj := 0
var _probe_sess := 0
var _probe_player_id := 0
var _probe_rect_ids: Dictionary = {}
## Projectiles the engine added but whose velocity is not readable yet. Bullet.fire()
## assigns velocity one frame after the node enters the tree, so a node read on the
## add frame would be reported as a zero-velocity "direction". Read-only: these
## nodes are only observed, never created, moved, freed or re-parented here.
var _probe_pending: Array = []
var _probe_proj_v := Vector2.ZERO
var _probe_proj_aim := 999.0
var _probe_proj_shots := 0

func _start_probe() -> void:
	# PAUSABLE rather than the inherited default, so _probe_frames is a liveness
	# signal that provably stops while a panel holds the tree paused.
	process_mode = Node.PROCESS_MODE_PAUSABLE
	set_process(true)
	get_tree().node_added.connect(_probe_on_node_added)
	print("[probe] mode=on")
	# Read-only, once: the acceptance driver reloads the page at the end and
	# asserts the save is still readable, which is the durability half of the
	# return contract. Nothing is written.
	print("[probe] save_state %s" % _save_state_line())
	_probe_stream.call_deferred()

## Reads the save file without touching it. Shared with the smoke header so the
## two channels cannot drift apart in format.
func _save_state_line() -> String:
	if not FileAccess.file_exists("user://camp-v1.json"): return "none"
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("user://camp-v1.json"))
	if data is Dictionary:
		return "gold=\"%s\" equipped=\"%s\"" % [str(data.get("gold")), str(data.get("equipped"))]
	return "none"

func _probe_stream() -> void:
	# create_timer() defaults to process_always, so the report keeps flowing
	# while the tree is paused - which is exactly when the driver needs it.
	while true:
		await get_tree().create_timer(0.25).timeout
		_probe_report()
		_probe_report_rects()

## Counts projectiles as the engine adds them. game/bullets/ also holds the
## ejected shells; those are excluded so the counter means "a projectile was
## created" rather than "a casing was ejected".
func _probe_on_node_added(node: Node) -> void:
	var script: Variant = node.get_script()
	if script == null: return
	var path: String = (script as Script).resource_path
	if path.contains("game/bullets/") and not path.contains("BulletShell"):
		_probe_proj += 1
		# The ordinal is stamped on the node the engine added. Read at observation
		# time instead, the number would report the COUNT of that moment: with a
		# burst weapon several projectiles are added before the first one is
		# observed, so every event of the burst would claim the newest ordinal and a
		# driver could not pair an event with the round it actually describes.
		# Metadata only - it is never read by gameplay.
		node.set_meta("probe_ord", _probe_proj)
		_probe_pending.append(node)

## Read-only: report the flight vector of a projectile the engine itself created,
## once the engine has actually given it one. This is the observation a driver
## cannot make from pixels: a projectile's direction IS the product's answer to
## "where did the shot go", and it is read here instead of being inferred from the
## change of a magazine region on screen.
##
## `aim` is the aim provider's angle towards the gun tip on the frame the
## projectile is reported, so a driver can prove the projectile left along the
## unified aim rather than merely "somewhere". Nothing in here creates, moves or
## frees a projectile, and nothing writes bullets_count.
func _probe_track_projectiles() -> void:
	if _probe_pending.is_empty(): return
	var gun_ready := Utils.player != null and is_instance_valid(Utils.player) \
			and Utils.player.gun != null and is_instance_valid(Utils.player.gun)
	var still: Array = []
	for node in _probe_pending:
		if not is_instance_valid(node): continue
		if node.velocity.length() > 0.1:
			_probe_proj_v = node.velocity
			if gun_ready:
				_probe_proj_aim = rad_to_deg((Utils.get_aim_world_position() - Utils.player.gun.gun_tip.global_position).angle())
			else:
				_probe_proj_aim = 999.0
			_probe_proj_shots += 1
			# One-shot event line, deliberately separate from the 4 Hz state line:
			# the state line carries a sticky "last seen" velocity, which cannot
			# say WHICH shot it belongs to. `n` is the engine's own projectile
			# ordinal, so a driver can pair the event with the count it read.
			print("[probe] proj-shot n=%d vx=%.1f vy=%.1f speed=%.1f aim=%.1f" % [
				node.get_meta("probe_ord", _probe_proj), _probe_proj_v.x, _probe_proj_v.y,
				_probe_proj_v.length(), _probe_proj_aim])
		else:
			still.append(node)
	_probe_pending = still

func _probe_report() -> void:
	var player_id := 0
	var gun_id := -1
	var bullets := -1
	var bullets_max := -1
	var player_pos := Vector2.ZERO
	var hp := 0.0
	if Utils.player != null and is_instance_valid(Utils.player):
		player_id = Utils.player.get_instance_id()
		player_pos = Utils.player.global_position
		hp = PlayerData.player_hp
		if Utils.player.gun != null and is_instance_valid(Utils.player.gun):
			gun_id = Utils.player.gun.weapon_id
			bullets = Utils.player.gun.bullets_count
			bullets_max = Utils.player.gun.bullets_max_count
	# A new Player instance is what "a new session" means: Demo swaps the whole
	# map in and out, so the generation is read off the engine rather than tracked
	# by the driver.
	if player_id != _probe_player_id:
		_probe_player_id = player_id
		if player_id != 0:
			_probe_sess += 1
	print("[probe] sess=%d frames=%d proj=%d start=%s sm=%s pause=%s panels=%d ingame=%s gun=%d bullets=%d/%d mm=%d player=%s aimvp=%s crh=%s hp=%.1f aimworld=%s projv=(%.1f, %.1f) projang=%.1f projshots=%d fr=%s fps=%d" % [
		_probe_sess, _probe_frames, _probe_proj,
		str(Utils.is_game_start), LevelServer.state,
		str(not Demo.pause_stack.is_empty()), Demo.pause_stack.size(),
		# The session graph itself, reported so a driver can prove the outgoing
		# session was released rather than merely hidden behind a menu.
		str(player_id != 0),
		gun_id, bullets, bullets_max, Input.mouse_mode,
		player_pos, Utils.get_aim_viewport_position(), _e2e_crosshair_centre(), hp,
		# --- fields appended for the aim gate. All are observations; appending
		# them (rather than inserting) keeps every existing prefix/regex reader
		# working unchanged.
		# aimworld: the aim point in WORLD space. A driver needs it to accumulate
		# the swept angle of a continuous 360 degree aim sweep; viewport-space aim
		# alone saturates at the edges of the screen.
		Utils.get_aim_world_position(),
		# projv / projang: the last projectile the engine created that has a
		# velocity, and the aim angle at the moment it was observed. Sticky by
		# design - the one-shot `[probe] proj-shot` line is what pairs a vector
		# with a specific shot.
		_probe_proj_v.x, _probe_proj_v.y, _probe_proj_aim, _probe_proj_shots,
		# fr: whether the fire button has been released. Read (not written) so a
		# driver can prove a pause-menu close did not leave the trigger stuck.
		str(Demo.fire_released),
		# fps: the real frame rate of THIS machine, so a run can report why a
		# state change took as long as it did instead of guessing.
		Engine.get_frames_per_second()])

## Read-only locators. The driver has to click the product's own controls with a
## real mouse, so it needs their rectangles - and it needs them for the panel
## that is actually on screen. Reporting them from the live panels replaces the
## throwaway calibration page load (a whole extra engine boot) and removes the
## guesswork that made an earlier version fall back to a hard-coded layout.
func _probe_report_rects() -> void:
	for menu in Demo.pause_stack:
		var panel: Node = menu
		if not is_instance_valid(panel): continue
		var script: Variant = panel.get_script()
		if script == null: continue
		var path: String = (script as Script).resource_path
		if path.ends_with("ui/CampPanel.gd"):
			_probe_report_rect("camp-close-button", panel, "返回")
			_probe_report_rect("camp-settings-button", panel, "设置")
		elif path.ends_with("ui/DemoSettings.gd"):
			_probe_report_rect("settings-back-button", panel, "返回")
			_probe_report_rect("leave-entry", panel, "返回主菜单")

func _probe_report_rect(tag: String, root: Node, prefix: String) -> void:
	var button := _find_button(root, prefix)
	if button == null or button.size.x <= 10.0: return
	if not button.is_visible_in_tree(): return
	# Once per instance: a re-reported rectangle would let the driver click a
	# stale position after the panel was rebuilt.
	var id := button.get_instance_id()
	if _probe_rect_ids.get(tag, 0) == id: return
	_probe_rect_ids[tag] = id
	var rect := Rect2(button.global_position, button.size)
	# The instance id is part of the payload on purpose: a driver that has to press
	# Esc twice (open, then close) needs to know the panel it sees is the one it
	# just opened and not the previous cycle's, because a panel that owns the pause
	# stack but has not finished building swallows the closing key.
	print("[probe] rect %s id=%d text=\"%s\" x=%.1f y=%.1f w=%.1f h=%.1f cx=%.1f cy=%.1f" % [
		tag, id, button.text, rect.position.x, rect.position.y, rect.size.x, rect.size.y,
		rect.get_center().x, rect.get_center().y])

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
	if probe:
		# A pause-aware idle-frame counter: the liveness signal the driver needs,
		# and one that provably stops while a panel holds the tree paused.
		#
		# The paused check is explicit and not left to PROCESS_MODE_PAUSABLE,
		# because the channel can now be armed TOGETHER with the e2e harness
		# (?probe=1&smoke=1), and that harness forces this node to
		# PROCESS_MODE_ALWAYS so it can watch round restarts. Left to the process
		# mode alone, the counter would keep ticking inside a pause menu in that
		# combination and "frames advanced" would stop meaning "the session ran".
		if not get_tree().paused:
			_probe_frames += 1
		# Per frame, not on the 4 Hz report: a projectile can be freed between two
		# reports (it hits a wall), and then its velocity would never be observed.
		_probe_track_projectiles()
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
		# Persist it: the acceptance driver uses one browser profile across its
		# phases, so the normal-entry phase that follows can fire a real shot
		# without this diagnostic phase having taken part in that assertion.
		Demo.save_camp()

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
