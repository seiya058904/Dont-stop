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
var _tour_simulated := 0.0
var _tour_last_telegraph_sample := -1.0

func _physics_process(delta: float) -> void:
	# Enabled only by stage-tour: observe short attacks even when a renderer
	# executes several physics ticks between two visible frames.
	if LevelServer.state != "COMBAT": return
	_tour_simulated += delta
	# Keep the detailed channel at the same 50 ms cadence as the tour driver.
	# Emitting a full scene-tree report on every physics tick can starve the
	# software-rendered CI runner before the required simulated window elapses.
	if _tour_simulated - _tour_last_telegraph_sample < 0.05: return
	_tour_last_telegraph_sample = _tour_simulated
	var zones = get_tree().get_nodes_in_group("hostile_zone")
	if not zones.is_empty():
		print("[telegraph] count=%d rows=%s" % [zones.size(), _probe_zone_state()])

func _ready() -> void:
	set_physics_process(false)
	var args := OS.get_cmdline_args()
	args.append_array(OS.get_cmdline_user_args())
	probe = "--probe" in args
	var stress := "--stress" in args
	if not ("--smoke" in args) and not probe and not stress and not ("--stage-tour" in args) and not ("--perf" in args):
		# Stay instantiated (inert) so autoload cross-references stay valid, but
		# take the node out of idle processing: _process appends a frame sample
		# every frame and nothing reads it in a real launch, so leaving it on
		# would grow an Array for the whole session.
		set_process(false)
		return
	if probe:
		_start_probe()
	# `--stress` is the B11.1 dense-attack driver (game/diag/B11Stress.gd). It owns the session the
	# same way `--stage-tour` and `--perf` do, so it is dispatched here and returns. It deliberately
	# does NOT arm `--probe`: the probe reports on a 0.25 s cadence and walks subtrees, and this
	# driver exists to measure single-frame spikes - an observer that costs a frame occasionally
	# would show up in exactly the number being reported. It samples what it needs itself.
	if stress:
		print("[stress] driver=game/diag/B11Stress.gd")
		var rig := Node.new()
		rig.name = "B11Stress"
		var normal_b18 = false
		for arg in args:
			if arg.begins_with("--b18-normal="):
				normal_b18 = true
		rig.set_script(load("res://game/diag/B18Play.gd" if normal_b18 else ("res://game/diag/B18Run.gd" if "--b18" in args else "res://game/diag/B11Stress.gd")))
		add_child(rig)
		return
	# `--stage-tour` is its OWN driver: it walks stages 31/35/39/40 in one session and prints one
	# evidence line per stage. It deliberately runs with the probe channel armed and WITHOUT the smoke
	# driver, so it has to be recognised before the "no --smoke, nothing to do" return below - a
	# launch of `--stage-tour --probe` previously armed the channel, printed performance lines for
	# five minutes and never started the walk.
	if "--stage-tour" in args:
		set_physics_process(true)
		print("[stage-tour] mode=on")
		_stage_tour_run.call_deferred()
		return
	# `--perf` is the browser half of tests/B11Perf.gd: the sustained-load measurement of a REAL stage,
	# which only a browser can take. It owns the session, so it is dispatched here with the other
	# drivers - it used to fall through every branch above and measure the title screen instead.
	if "--perf" in args:
		print("[smoke-perf] mode=on")
		_perf_run.call_deferred()
		return
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
	if "--b17-visual" in args:
		Demo.test_mode = true
		add_child(load("res://game/diag/B17Visual.gd").new())
		return
	if "--b16-ui" in args:
		Demo.test_mode = true
		_b16_native_ui.call_deferred()
		return
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
## The state line's shape, in one place. B11 replaced the inline literal with this constant and an
## explicit `fields` Array so the specifier count and the argument count are both readable in one
## screen; see `_probe_report()`.
const PROBE_FORMAT := "[probe] sess=%d frames=%d proj=%d start=%s sm=%s pause=%s panels=%d ingame=%s gun=%d bullets=%d/%d mm=%d player=%s aimvp=%s crh=%s hp=%.1f aimworld=%s projv=(%.1f, %.1f) projang=%.1f projshots=%d fr=%s fps=%d stage=%d camp=%s hellc=%s next=%d sel=%d pt=%d fog=%s scroll=%d"

var _probe_frames := 0
var _probe_proj := 0
## B11 performance observation. Read-only: frame deltas of this node's own idle callback and the
## engine's own node counts. Nothing here creates, frees, moves or pauses anything.
var _probe_frame_ms: Array = []
var _probe_created := 0
var _probe_removed := 0
var _probe_nodes_prev := 0
var _probe_perf_clock := 0.0
var _probe_perf_last := Time.get_ticks_usec()
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
	get_tree().node_removed.connect(_probe_on_node_removed)
	_probe_nodes_prev = get_tree().get_node_count()
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
		_probe_perf_report()

## One line per second with the numbers a frame-rate complaint has to be judged on. The frame
## statistics come from this node's own idle callback measured in microseconds, so they are the real
## cost of a frame on the machine under test and not a guess from a screenshot.
##
## Its prefix is `[perf]`, deliberately NOT `[probe]`. The probe channel's contract is "the state line
## and the locator reports", and the acceptance and menu gates detect it by matching any `[probe] `
## line and taking the last one. Publishing this line under that prefix made those gates parse a
## performance report as state (`sm=null`, `gun=NaN`) and fail in a cascade that had nothing to do
## with the product - see `_probe_zone_state()` for the same reasoning.
func _probe_perf_report() -> void:
	var now := Time.get_ticks_usec()
	_probe_perf_clock += float(now-_probe_perf_last)/1000.0
	_probe_perf_last = now
	if _probe_perf_clock < 1000.0: return
	_probe_perf_clock = 0.0
	var samples := _probe_frame_ms.duplicate()
	_probe_frame_ms.clear()
	if samples.is_empty(): return
	samples.sort()
	var total := 0.0
	for value in samples: total += value
	var nodes := get_tree().get_node_count()
	var created_delta := _probe_created
	var removed_delta := _probe_removed
	_probe_created = 0
	_probe_removed = 0
	var particles := 0
	for node in get_tree().get_nodes_in_group("monsters"):
		if is_instance_valid(node) and node.has_node("body/AnimatedSprite2D"): particles += 1
	print("[perf] avg=%.2f p50=%.2f p95=%.2f p99=%.2f max=%.2f fps=%d frames=%d enemies=%d projectiles=%d telegraphs=%d hazards=%d vfx=%d particles=%d nodes=%d created=%d removed=%d nodes_delta=%d stage=%d" % [
		total/samples.size(), samples[int(samples.size()*0.50)], samples[int(samples.size()*0.95)],
		samples[int(samples.size()*0.99)], samples.back(), Engine.get_frames_per_second(),
		samples.size(),
		get_tree().get_nodes_in_group("monsters").filter(func(node): return not node.is_die).size(),
		get_tree().get_nodes_in_group("enemy_projectiles").size(),
		get_tree().get_nodes_in_group("hostile_zone").size(),
		get_tree().get_nodes_in_group(StageHazard.GROUP).size(),
		get_tree().get_nodes_in_group("combat_transient").size(),
		particles, nodes, created_delta, removed_delta, nodes-_probe_nodes_prev,
		LevelServer.level])
	_probe_nodes_prev = nodes
	var zones := get_tree().get_nodes_in_group("hostile_zone")
	print("[telegraph] count=%d rows=%s" % [zones.size(), _probe_zone_state()])

## The lock state of every live footprint, so "the laser froze and then fired at the lane it froze"
## is read off a real session rather than inferred from the pictures. `t` is seconds until the
## footprint may damage; `frozen` is the actor's own lock flag.
## Prefix `[telegraph]`, NOT `[probe]`, for the reason given above `_probe_perf_report()`. The name
## is also the honest one: this is the telegraph channel, not the general probe channel.
##
## Fields are `name=value` pairs joined by `;` and rows are joined by `|`. Neither separator can occur
## inside a value: there is no text in this payload, only numbers and short identifiers. An earlier
## version wrote the direction as `dir=%.2f,%.2f`, which made the comma-load-bearing and silently broke
## any reader that split on it - including this project's own browser gate, which then reported "no lane
## was ever observed" while the game was measuring hundreds of frames of frozen lanes.
func _probe_zone_state() -> String:
	var rows := []
	for node in get_tree().get_nodes_in_group("hostile_zone"):
		var owner_ref = node.owner_ref
		var actor = owner_ref.get_ref() if owner_ref else null
		var frozen := -1
		if actor != null and actor.has_method("aim_state"):
			frozen = 1 if bool(actor.aim_state().frozen) else 0
		rows.append("id=%d;mode=%s;style=%s;active=%s;t=%.2f;w=%.2f;len=%.1f;dx=%.3f;dy=%.3f;frozen=%d;sweep=%.2f;turned=%d" % [
			node.get_instance_id(), node.mode, node.style, str(node.activated),
			node.warning-node.elapsed, node.warning, node.length,
			node.direction.x, node.direction.y, frozen, node.sweep,
			1 if node.sweep != 0.0 else 0])
	return "|".join(rows)

## Counts projectiles as the engine adds them. game/bullets/ also holds the
## ejected shells; those are excluded so the counter means "a projectile was
## created" rather than "a casing was ejected".
func _probe_on_node_added(node: Node) -> void:
	_probe_created += 1
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
func _probe_on_node_removed(_node: Node) -> void:
	_probe_removed += 1

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

var _probe_last_save_diagnostic := ""

func _probe_report() -> void:
	var web_fs = null
	if OS.has_feature("web"):
		# Read-only bridge diagnostic: distinguish the engine's file view from
		# the mounted browser FS. Never synchronize or repair the save here.
		web_fs = JavaScriptBridge.eval("""(function (path) {
			if (typeof GodotFS === 'undefined' || typeof FS === 'undefined') return null;
			try { return JSON.stringify({ syncing: GodotFS._syncing, mounts: GodotFS._mount_points,
				mount: FS.lookupPath(path).node.mount.mountpoint,
				files: FS.readdir(path).filter(name => name !== '.' && name !== '..').map(name => {
					const stat = FS.stat(path + '/' + name);
					return { name, mode: stat.mode, size: stat.size, mtime: String(stat.mtime) };
				}) }); } catch (error) { return JSON.stringify({ error: String(error) }); }
		})(%s)""" % JSON.stringify(ProjectSettings.globalize_path(Demo.save_path).get_base_dir()))
	var save_diagnostic := JSON.stringify({"path":Demo.save_path,"exists":FileAccess.file_exists(Demo.save_path),
		"absolute_path":ProjectSettings.globalize_path(Demo.save_path),
		"persistent":OS.is_userfs_persistent(),"result":Demo.save_result,"web_fs":web_fs})
	if save_diagnostic != _probe_last_save_diagnostic:
		_probe_last_save_diagnostic = save_diagnostic
		print("[probe] save_diagnostic ",save_diagnostic)
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
	# The argument list is an explicit Array with one entry per specifier, in the same order. The
	# previous version interleaved long comments between the arguments, which is exactly the shape
	# an edit can unbalance - and did: `hp` lost its value, `%` raised, and the line below printed its
	# own format string instead of a state report. Every reader of this channel then saw "no line".
	var fields: Array = [
		_probe_sess, _probe_frames, _probe_proj,
		str(Utils.is_game_start), LevelServer.state,
		str(not Demo.pause_stack.is_empty()), Demo.pause_stack.size(),
		# The session graph itself, reported so a driver can prove the outgoing session was released
		# rather than merely hidden behind a menu.
		str(player_id != 0),
		gun_id, bullets, bullets_max, Input.mouse_mode,
		player_pos, Utils.get_aim_viewport_position(), _e2e_crosshair_centre(), hp,
		# aimworld: the aim point in WORLD space. A driver needs it to accumulate the swept angle of a
		# continuous 360 degree aim sweep; viewport-space aim alone saturates at the screen edges.
		Utils.get_aim_world_position(),
		# projv / projang: the last projectile the engine created that has a velocity, and the aim
		# angle when it was observed. Sticky by design; the one-shot `[probe] proj-shot` line is what
		# pairs a vector with a specific shot.
		_probe_proj_v.x, _probe_proj_v.y, _probe_proj_aim, _probe_proj_shots,
		# fr: whether the fire button has been released, read (not written) so a driver can prove a
		# pause-menu close did not leave the trigger stuck.
		str(Demo.fire_released),
		# fps: the real frame rate of THIS machine, so a run can report why a state change took as
		# long as it did instead of guessing.
		Engine.get_frames_per_second(),
		# stage/camp/hellc/next/sel: the product's own progression state, read so a driver can PROVE a
		# direct stage departure did not move the campaign pointer or fake a completion.
		# fog is ArenaVisibility.fog_active(): the Hell darkness really being applied, as opposed to
		# merely being requested by the stage number.
		LevelServer.level, str(Demo.campaign_complete), str(Demo.hell_complete),
		Demo.next_stage, Demo.selected_stage,
		# pt: kept in the line's shape for the drivers that already parse it. The playtest marker it
		# used to report no longer exists, so it is a constant 0 - appending was deliberate, so no
		# existing prefix or regex reader had to change when the product concept was removed.
		0,
		str(ArenaVisibility.fog_active()),
		# scroll: how far the open camp panel's listing is scrolled, or -1 when no camp panel is up.
		camp_scroll(),
	]
	print(PROBE_FORMAT % fields)


## The camp stage/weapon listing's scroll offset, read off the live panel. -1 when no camp panel
## is on screen, so a driver can tell "no list" from "list at the top".
func camp_scroll() -> int:
	for menu in Demo.pause_stack:
		if not is_instance_valid(menu): continue
		var script: Variant = menu.get_script()
		if script == null: continue
		if not (script as Script).resource_path.ends_with("ui/CampPanel.gd"): continue
		var scroll = (menu as Node).get("listing_scroll")
		if scroll != null and is_instance_valid(scroll): return int(scroll.scroll_vertical)
	return -1

## Read-only locators. The driver has to click the product's own controls with a
##
## PREFIX CONTRACT, and it is load bearing: `tools/web-aim-e2e.js` and
## `tools/web-menu-return-e2e.js` detect this channel by matching ANY `[probe] ` line and taking the
## LAST one, because on the base build every line here was either the 4 Hz state line or a one-off
## rectangle. Anything added to this channel at a HIGHER rate than the state line therefore hijacks
## them. B11 learned that the hard way: a `[probe] perf` line did exactly this and reddened two gates
## with `sm=null`. So the state line, the rectangles and the one-shot `proj-shot` stay on `[probe] `,
## and every high-rate report uses its own prefix: `[perf]`, `[telegraph]`, `[stage]`, `[locator]`.
## real mouse, so it needs their rectangles - and it needs them for the panel
## that is actually on screen. Reporting them from the live panels replaces the
## throwaway calibration page load (a whole extra engine boot) and removes the
## guesswork that made an earlier version fall back to a hard-coded layout.
func _probe_report_rects() -> void:
	_probe_rect_diag()
	var canvas = Utils.canvasLayer
	if not is_instance_valid(canvas):
		return
	for hud in _find_scripts(canvas,"ui/GameUI.gd"):
		for item in hud.weapon_lsit_node.get_children():
			if item.has_meta("slot_id"): _probe_emit_rect("hud-slot-%d" % item.get_meta("slot_id"),item)
	# The title screen is a plain Control added straight to the control canvas layer, NOT a pause
	# panel, so it is reported from a short walk here rather than from the pause stack below.
	for title in _find_scripts(canvas,"ui/MainUI.gd"):
		# The title screen's buttons are authored with TRANSLATION KEYS as their text
		# (ui/ControlUI.tscn: text = "MAIN_UI_START"), not with the Chinese they render as.
		# Matching the rendered text found nothing at all, which is why the first two browser
		# runs could not click the menu and stopped at the title screen.
		_probe_report_rect("menu-start-button", title, "MAIN_UI_START")
		_probe_report_rect("menu-mods-button", title, "MAIN_UI_MOD")
		_probe_report_rect("menu-settings-button", title, "MAIN_UI_SETTING")
	for menu in Demo.pause_stack:
		var panel: Node = menu
		if not is_instance_valid(panel): continue
		var script: Variant = panel.get_script()
		if script == null: continue
		var path: String = (script as Script).resource_path
		if path.ends_with("ui/CampPanel.gd"):
			_probe_report_rect("camp-close-button", panel, "返回")
			_probe_report_rect("camp-settings-button", panel, "设置")
			# The stage tab itself, and the departure button a stage entry opens in the detail pane:
			# reaching a stage from the camp takes two real clicks and both have to be aimed at the
			# control the product actually put on screen.
			_probe_report_rect("camp-stage-tab", panel, "出发")
			_probe_report_rect("camp-depart-button", panel, "开始此遭遇")
			# B11: ONE stage list, 1-40, every entry a real enabled control. A driver reaches any of
			# these with two real clicks and no selector switch in between, so the probe reports the
			# far ends of the range plus the Hell stages a reviewer must be able to enter on a fresh
			# save. Absence of a rectangle is the product saying the entry is missing or disabled.
			# EVERY stage row the list built, not a hand-picked few: a row that is merely outside the
			# scroll viewport must be reported as existing-but-not-clickable, or a driver cannot tell it
			# apart from a stage the product does not offer at all.
			for stage in _find_stage_ids(panel):
				_probe_report_stage(panel, stage)
			# The weapon tab, the first weapon row, and the detail pane's own action. A driver arming a
			# fresh Web profile needs all three, and the third click is the real "购买"/"装备" control
			# the product builds.
			_probe_report_rect("camp-weapon-tab", panel, "武器")
			for page in [["talent","天赋"],["attachment","武器强化"],["magazine","弹匣补给"]]:
				_probe_report_rect("camp-"+page[0]+"-tab",panel,page[1])
			for item in panel.listing.get_children():
				if item.has_meta("entry_key"): _probe_emit_rect("camp-entry-"+str(item.get_meta("entry_key")),item)
			for index in panel.action_bar.get_child_count():
				var action = panel.action_bar.get_child(index)
				if action is Button: _probe_emit_rect("camp-action-"+str(index),action)
			var camp_state = JSON.stringify({"tab":panel.tab,"selection":panel.selection,"rank":Demo.rank(panel.selection),"detail":panel.detail_scroll.size.y,"actions":panel.action_bar.size.y,"status":panel.action_status.text,"order":panel.detail_actions.keys()})
			if camp_state != _last_camp_state:
				_last_camp_state = camp_state
				print("[camp] ",camp_state)
			_probe_report_weapon(panel,0)
			_probe_report_search(panel)
			_probe_loadout_controls(panel)
			var carry_state = JSON.stringify({"slots":PlayerData.weapon_slots,"equipped":Utils.player.gun.weapon_id if Utils.player.gun else -1,"owned":PlayerData.player_weapon_list.keys(),"gold":PlayerData.gold,"message":panel.message.text,"saved":Demo.save_result.success,"selection":panel.selection,"heading":panel.weapon_heading.text,"detail_height":panel.detail_scroll.size.y,"detail_scroll":panel.detail_scroll.scroll_vertical})
			if carry_state != _last_carry_state:
				_last_carry_state = carry_state
				print("[loadout] ",carry_state)
		elif path.ends_with("ui/DemoSettings.gd"):
			_probe_report_rect("settings-back-button", panel, "返回")
			_probe_report_rect("leave-entry", panel, "返回主菜单")
		elif path.ends_with("ui/widgets/Scoreboard.gd"):
			# The results panel a finished round shows. It owns the pause stack, so a driver that wants
			# to play a second round has to close it with the product's own button.
			_probe_report_rect("scoreboard-ok", panel, "OK")
		elif path.ends_with("ui/widgets/DeathBoard.gd"):
			# The death panel's second button is the "give up and go back to camp" one; its text is the
			# translation KEY, which is what this locator matches, so it is locale-proof.
			_probe_report_rect("deathboard-cancel", panel, "CANCEL")

## Once per second, say what the locator channel can see. Without this, a driver that receives no
## rectangle cannot tell "the function never ran" from "the control was not found", and that ambiguity
## cost two browser runs before it was instrumented.
var _probe_rect_diag_at := -1000
var _last_carry_state := ""
var _last_camp_state := ""

func _probe_loadout_controls(node: Node) -> void:
	if node is Button:
		if node.has_meta("slot_id"):
			_probe_emit_rect("loadout-%s-%d" % [node.get_meta("action_id"),node.get_meta("slot_id")],node)
		elif node.get_meta("action_id","") == "clear_loadout": _probe_emit_rect("loadout-clear",node)
		elif node.get_meta("action_id","") == "purchase_weapon": _probe_emit_rect("camp-weapon-action",node)
		elif node.get_meta("action_id","") == "equip_owned": _probe_emit_rect("camp-weapon-owned-action",node)
		if node.has_meta("weapon_id"): _probe_emit_rect("camp-weapon-%d" % node.get_meta("weapon_id"),node)
	for child in node.get_children(): _probe_loadout_controls(child)
var _probe_rect_diag_logged := false
func _probe_rect_diag() -> void:
	var now := Time.get_ticks_msec()
	var first := not _probe_rect_diag_logged
	if not first and now < _probe_rect_diag_at+1000: return
	_probe_rect_diag_at = now
	_probe_rect_diag_logged = true
	var canvas = Utils.canvasLayer
	var children := []
	if is_instance_valid(canvas):
		for child in canvas.get_children():
			var script: Variant = child.get_script()
			children.append("%s[%s]" % [child.name,str((script as Script).resource_path.get_file()) if script != null else "none"])
	print("[locator] canvas=%s children=%s stack=%d titles=%d" % [
		str(is_instance_valid(canvas)), str(children.slice(0,14)), Demo.pause_stack.size(),
		_find_scripts(canvas,"ui/MainUI.gd").size() if is_instance_valid(canvas) else -1])

## Every node under `root` whose script is `suffix`. Used for the title screen, which has no
## reference kept anywhere in the game: finding it by script is what makes the locator independent of
## how the scene happens to be nested.
func _find_scripts(root: Node, suffix: String) -> Array:
	var found := []
	var script: Variant = root.get_script()
	if script != null and (script as Script).resource_path.ends_with(suffix): found.append(root)
	for child in root.get_children():
		found.append_array(_find_scripts(child,suffix))
	return found

func _probe_report_rect(tag: String, root: Node, prefix: String) -> void:
	_probe_emit_rect(tag, _find_button(root, prefix))

## The camp listing's search field. It is a LineEdit, not a Button, so it is located by the placeholder
## the product gives it, and it is reported with the same `on_screen` contract as every other control.
func _probe_report_search(root: Node) -> void:
	_probe_emit_rect("camp-search-box", _find_line_edit(root))

func _find_line_edit(node: Node) -> LineEdit:
	if node is LineEdit and (node as LineEdit).is_visible_in_tree(): return node
	for child in node.get_children():
		var found := _find_line_edit(child)
		if found != null: return found
	return null

## The camp's weapon ROW for `weapon_id`, plus the detail pane's action button. Same contract as a
## stage row: a missing report means the product does not offer it, and `on_screen=false` means the
## listing has not been scrolled to it yet.
func _probe_report_weapon(root: Node, weapon_id: int) -> void:
	var row := _find_weapon_row(root,weapon_id)
	if row != null: _probe_emit_rect("camp-weapon-%d" % weapon_id,row)
	# The detail pane offers exactly one of these, depending on whether the weapon is already owned.
	_probe_emit_rect("camp-weapon-action", _find_button(root,"购买"))
	_probe_emit_rect("camp-weapon-owned-action", _find_button(root,"已拥有"))

func _find_weapon_row(node: Node, weapon_id: int) -> Button:
	if node is Button and int((node as Button).get_meta("weapon_id",-1)) == weapon_id: return node
	for child in node.get_children():
		var found := _find_weapon_row(child,weapon_id)
		if found != null: return found
	return null

## Every stage id the open panel is currently listing, in the order the list holds them.
func _find_stage_ids(node: Node, out: Array = []) -> Array:
	if node is Button and (node as Button).has_meta("stage_id"):
		var id := int((node as Button).get_meta("stage_id"))
		if not out.has(id): out.append(id)
	for child in node.get_children(): _find_stage_ids(child,out)
	return out

func _probe_emit_rect(tag: String, button: Control) -> void:
	if button == null or button.size.x <= 10.0: return
	if not button.is_visible_in_tree(): return
	# ON SCREEN, not merely visible-in-tree. `is_visible_in_tree()` is true for a control that is
	# scrolled far outside its ScrollContainer, and the B10 Hell playtest entry was reported at
	# y=1042 in a 230-unit panel - so a driver that clicked the reported centre clicked nothing at
	# all, while the report confidently said the control was there. A control has to be really
	# inside the scroll viewport to be clickable.
	var rect := Rect2(button.global_position, button.size)
	var on_screen := _probe_on_screen(button)
	# Re-report whenever the control MOVES, and not only when the instance changes.
	#
	# The original rule ("once per instance") was there to stop a driver clicking a position
	# remembered from a rebuilt panel - but a control that is still on screen and has scrolled
	# keeps the same instance, so its OLD position would stay the only one ever published, and a
	# driver scrolling a long list could never learn where the control went. Publishing the latest
	# position on every move is what makes scrolling work, and it is strictly safer than the old
	# rule: the map always holds the newest rectangle, never a stale one.
	var id := button.get_instance_id()
	var stamp := "%d@%d,%d@%s" % [id, roundi(rect.position.x), roundi(rect.position.y), str(on_screen)]
	if str(_probe_rect_ids.get(tag, "")) == stamp: return
	_probe_rect_ids[tag] = stamp
	# The instance id is part of the payload on purpose: a driver that has to press
	# Esc twice (open, then close) needs to know the panel it sees is the one it
	# just opened and not the previous cycle's, because a panel that owns the pause
	# stack but has not finished building swallows the closing key.
	# `on_screen` is published rather than implied. A control that is scrolled outside its viewport
	# still HAS a rectangle, and the difference between "not built yet" and "not scrolled to" is the
	# difference between a defect and a driver that has not turned the wheel far enough.
	# Field ORDER is a contract here, not a style choice. `tools/web-aim-e2e.js` and
	# `tools/web-menu-return-e2e.js` parse this line with a positional regex that reads
	# `id=`, `text="..."`, `x=`, `y=`, `w=`, `h=`, `cx=`, `cy=` in that order, and B11 broke both gates
	# by inserting `on_screen=` in the middle of it: the regex stopped matching, no rectangle was ever
	# stored, and the driver could not click anything. New fields go on the END.
	print("[probe] rect %s id=%d text=\"%s\" x=%.1f y=%.1f w=%.1f h=%.1f cx=%.1f cy=%.1f on_screen=%s" % [
		tag, id, _control_label(button).replace("\n"," "), rect.position.x, rect.position.y,
		rect.size.x, rect.size.y, rect.get_center().x, rect.get_center().y, str(on_screen)])

## The visible label of a published control. `text` exists on Button and LineEdit and NOT on Control,
## and reading it off a Control raised inside the print above - which silently produced no line at all.
func _control_label(control: Control) -> String:
	if control is Button: return (control as Button).text
	if control is LineEdit: return (control as LineEdit).text
	return ""

## Is this control inside every scroll viewport it lives in, and is its centre inside the screen?
## Walks the ancestors so a control nested in a panel inside a ScrollContainer is checked against
## the scroll rect that actually clips it.
func _probe_on_screen(button: Control) -> bool:
	var centre := button.get_global_rect().get_center()
	var screen := get_viewport().get_visible_rect()
	if screen.size.x > 0.0 and not screen.has_point(centre): return false
	var node: Node = button.get_parent()
	while node != null:
		if node is ScrollContainer:
			var view := (node as ScrollContainer).get_global_rect()
			if view.size.x > 0.0 and not view.has_point(centre): return false
		node = node.get_parent()
	return true

## Locate a STAGE entry by the stage id the camp stores on its own button, reporting it under a
## per-stage tag. Text cannot be used here: the label carries the stage's authored name and a future
## edit could change it. The button's ENABLED state is published with the rectangle, so a driver can
## prove the product really offers the stage instead of inferring it from a click having worked. B11
## removed the disabled class of entry entirely, so a disabled one here is a defect and is reported as
## such rather than silently skipped.
##
## The row is scrolled into view BY THE PRODUCT before it is reported. `_probe_emit_rect()` refuses a
## control that is not really inside its scroll viewport - which is correct, a driver must not be
## handed a rectangle it cannot click - so a forty-row list needs the list itself to move. Asking the
## ScrollContainer is deterministic; turning the wheel and hoping was not.
func _probe_report_stage(root: Node, stage: int) -> void:
	var button := _find_stage_button(root, stage)
	if button == null:
		print("[stage] %d missing" % stage)
		return
	print("[stage] %d enabled=%s text=\"%s\"" % [stage, str(not button.disabled), button.text])
	_probe_emit_rect("stage-%d" % stage, button)

func _find_stage_button(node: Node, stage: int) -> Button:
	if node is Button and (node as Button).is_visible_in_tree() \
			and int((node as Button).get_meta("stage_id", 0)) == stage:
		return node
	for child in node.get_children():
		var found := _find_stage_button(child, stage)
		if found != null: return found
	return null

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

## B11 Web sustained-load measurement. Departs the requested stage, plays it for the requested number
## of seconds, and lets the read-only probe channel publish the per-second performance line. It owns the
## session, so the scripted smoke sequence never runs alongside it.
func _perf_run() -> void:
	await get_tree().create_timer(3.0).timeout
	Demo.test_mode = true
	var stage := _perf_arg("--perf-stage=",39)
	var seconds := _perf_arg("--perf-seconds=",60)
	await _enter_camp_from_title()
	await _wait_until(func(): return Utils.is_game_start, 180000)
	await _wait_until(func(): return LevelServer.state == "CAMP", 120000)
	await _wait_until(func(): return Demo.pause_stack.is_empty(), 60000)
	# A Web launch restores `equipped` from the save but not the live `Utils.player.gun`, so the rig
	# arms itself exactly as a player would have to. Same in the BEFORE and the AFTER build.
	if Utils.player != null and Utils.player.gun == null:
		PlayerData.add_weapon(Utils.weapon_list["0"].instantiate())
		PlayerData.changeWeapon(0,true)
	# Survivability a player who reached Hell would have, so the run measures the STAGE and cannot end
	# early on a level-1 health bar.
	PlayerData.player_hp_max = 100000.0
	PlayerData.player_hp = 100000.0
	Utils.set_gameplay_mouse_mode()
	await get_tree().create_timer(0.6).timeout
	var departed: bool = LevelServer.town.depart(stage,true)
	print("[smoke-perf] depart=%s stage=%d seconds=%d" % [str(departed),stage,seconds])
	await _wait_until(func(): return LevelServer.state == "COMBAT", 120000)
	var until := Time.get_ticks_msec()+seconds*1000
	while Time.get_ticks_msec() < until:
		PlayerData.player_hp = PlayerData.player_hp_max
		# Real movement and real fire: a stage only builds up the way the report describes if the
		# player is actually in it.
		var step := ((Time.get_ticks_msec()/700)%4)
		for pair in [["left",0],["right",1],["up",2],["down",3]]:
			if step == int(pair[1]): Input.action_press(pair[0])
			else: Input.action_release(pair[0])
		Input.action_press("shoot")
		await get_tree().process_frame
	for action in ["left","right","up","down","shoot"]: Input.action_release(action)
	print("[smoke-perf] complete stage=%d state=%s" % [stage,LevelServer.state])
	LevelServer.return_to_camp()
	await get_tree().create_timer(1.0).timeout
	get_tree().quit(0)

func _perf_arg(prefix: String, fallback: int) -> int:
	for arg in OS.get_cmdline_args() + OS.get_cmdline_user_args():
		if arg.begins_with(prefix): return int(arg.substr(prefix.length()))
	return fallback

## B11: walk the Hell stages in one session and say, per stage, what the product actually did.
## Each line is an observation a gate can assert on: state, level, whether Hell darkness is applied,
## how many real enemies arrived, and whether the player's own weapon is live.
const STAGE_TOUR := [31,35,39,40]

func _stage_tour_run() -> void:
	await get_tree().create_timer(4.0).timeout
	await _enter_camp_from_title()
	await _wait_until(func(): return Utils.is_game_start, 180000)
	await _wait_until(func(): return LevelServer.state == "CAMP", 120000)
	# A live weapon, so a real round can be played rather than only observed.
	if Utils.player != null and (Utils.player.gun == null or PlayerData.player_weapon_list.is_empty()):
		var gun = Utils.weapon_list["0"].instantiate()
		PlayerData.add_weapon(gun)
		PlayerData.changeWeapon(0,true)
		print("[stage-tour] armed gun=%s" % str(Utils.player.gun != null))
	# Give the profile the survivability a player who reached Hell would have, so the tour measures the
	# STAGE and not a level-1 health bar.
	PlayerData.player_hp_max = 100000; PlayerData.player_hp = 100000
	for stage in STAGE_TOUR:
		LevelServer.return_to_camp()
		await _wait_until(func(): return LevelServer.state == "CAMP", 60000)
		await get_tree().create_timer(0.6).timeout
		Utils.set_gameplay_mouse_mode()
		var departed: bool = LevelServer.town.depart(stage,true)
		await _wait_until(func(): return LevelServer.state == "COMBAT", 60000)
		# Nine simulated seconds, bounded by 75 wall seconds. A slow software
		# renderer must not silently turn this into a one-second combat sample.
		_tour_simulated = 0.0
		_tour_last_telegraph_sample = -1.0
		var until := Time.get_ticks_msec()+75000
		var monsters := 0
		var fog := false
		var locked_lanes := 0
		var moving := 0
		while _tour_simulated < 9.0 and Time.get_ticks_msec() < until:
			PlayerData.player_hp = PlayerData.player_hp_max
			var step := int(_tour_simulated/0.7)%4
			for pair in [["left",0],["right",1],["up",2],["down",3]]:
				if step == int(pair[1]): Input.action_press(pair[0])
				else: Input.action_release(pair[0])
			Input.action_press("shoot")
			if Utils.player != null and is_instance_valid(Utils.player):
				moving += 1 if Utils.player.velocity.length() > 1.0 else 0
			for node in get_tree().get_nodes_in_group("hostile_zone"):
				var ref = node.owner_ref
				if ref and ref.get_ref() != null and ref.get_ref().has_method("aim_state"):
					if bool(ref.get_ref().aim_state().frozen): locked_lanes += 1
			monsters = maxi(monsters,get_tree().get_nodes_in_group("monsters").filter(
				func(node): return not node.is_die).size())
			fog = fog or ArenaVisibility.fog_active()
			await get_tree().create_timer(0.05).timeout
		for action in ["left","right","up","down","shoot"]: Input.action_release(action)
		print("[stage-tour] stage=%d departed=%s state=%s level=%d fog=%s monsters_peak=%d moving_frames=%d locked_lane_frames=%d next=%d campaign=%s hell=%s simulated=%.3f" % [
			stage, str(departed), LevelServer.state, LevelServer.level, str(fog), monsters, moving,
			locked_lanes, Demo.next_stage, str(Demo.campaign_complete), str(Demo.hell_complete), _tour_simulated])
		await get_tree().create_timer(0.5).timeout
	LevelServer.return_to_camp()
	await get_tree().create_timer(1.0).timeout
	print("[stage-tour] complete")
	await Demo.quit_game()

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
	if probe and not get_tree().paused:
		_probe_frame_ms.append(get_process_delta_time() * 1000.0)
		if _probe_frame_ms.size() > 600: _probe_frame_ms.pop_front()
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
	# Scripted native smoke must neither restore nor write the player's real save.
	# E2E explicitly retains its isolated-browser-profile seeding contract.
	if not e2e and not OS.has_feature("web"):
		Demo.test_mode = true
		print("[smoke] isolated=true save_writes=false")
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

	var ok_switch: bool = PlayerData.changeWeapon(other)
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
	PlayerData.changeWeapon(other2)
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
		# Use the native exit cleanup too: direct quit leaves the custom cursor
		# texture alive after RenderingServer teardown and makes the smoke fail.
		if passed: await Demo.finish_quit()
		else:
			Input.set_custom_mouse_cursor(null)
			get_tree().quit(1)

# Explicit native export acceptance driver; never restores or writes the real save.
func _b16_native_ui():
	await get_tree().create_timer(3.0).timeout
	await _enter_camp_from_title()
	await _wait_until(func(): return LevelServer.state == "CAMP",60000)
	_tour_close_panels()
	await get_tree().process_frame
	Demo.try_purchase("weapon","0")
	Demo.open_panel()
	var output = "user://b16-native-ui"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--b16-output="): output = arg.substr(13)
	DirAccess.make_dir_recursive_absolute(output)
	for resolution in [Vector2i(1280,720),Vector2i(1366,768),Vector2i(1536,864),Vector2i(1920,1080)]:
		get_window().borderless = true
		get_window().position = Vector2i.ZERO
		get_window().size = resolution
		for page in ["weapon","attachment","magazine","talent","stage"]:
			Demo.ui.switch_tab(page)
			if page == "talent": Demo.ui.selection = "T04"; Demo.ui.render()
			await get_tree().create_timer(0.3).timeout
			await RenderingServer.frame_post_draw
			var image = get_viewport().get_texture().get_image()
			image.save_png(output+"/%s-%d.png" % [page,resolution.x])
			print("B16_NATIVE_UI ",page," window=",resolution," image=",image.get_size()," detail=",Demo.ui.detail_scroll.size," actions=",Demo.ui.action_bar.size)
			await get_tree().create_timer(2.5).timeout
		Demo.ui.switch_tab("talent"); Demo.ui.selection = "T04"
		while Demo.rank("T04") < 3: Demo.try_purchase("talent","T04","points")
		Demo.ui.render()
		await get_tree().create_timer(0.3).timeout
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(output+"/talent-max-%d.png" % resolution.x)
	_tour_close_panels()
	await Demo.quit_game()
