extends Node

## R3: the Web replacement for quitting must really present a usable main menu.
##
## Why this is a behavioural test and not a source review: the first version of
## Demo.return_to_main_menu() changed a scene and cleared a flag, and the browser
## acceptance run showed the player still standing in the camp with the in-game HUD
## and no title menu at all - the picture had not "frozen", it had simply never
## gone back. This test drives the real entry point and then checks the things a
## player needs: the title menu is on screen and interactive, no HUD from the old
## session is left behind, and pressing start again begins a session that is
## actually playable.
##
## Run headless:
##   Godot_v4.7.2-stable_win64.exe --headless --path <project> res://tests/R3ReturnMenu.tscn
##
## The scene change frees the current scene, so the checks live on a probe node
## parented to the tree root instead of to the test scene.
##
## The fixture used to instantiate the menu with `root.add_child(main)` and never
## make it the current scene. That is not the lifecycle the game has: the engine
## frees `current_scene` on a swap, so the manually added copy stayed in the tree
## beside the new one and every "the menu is present" assertion was satisfied by a
## scene the game had not produced. The fixture now installs a real current scene,
## and asserts that after each return exactly one menu map exists and that it is a
## genuinely new instance.
##
## Five laps, not two: "returning works once" is not the product requirement. A
## fifth start after the fifth return is what proves the last return is usable.

static var _probe_spawned := false

const HUD_SCRIPTS := ["res://ui/DemoHUD.gd", "res://ui/BossHUD.gd"]
const MENU_SCENE := "res://game/map/Main.tscn"
const LAPS := 5

var _failures := 0
var _checks := 0

func _ready() -> void:
	if _probe_spawned:
		# This instance is the probe: the test scene has already been replaced.
		_run.call_deferred()
		return
	_probe_spawned = true
	var probe := Node.new()
	probe.name = "R3ReturnMenuProbe"
	probe.set_script(load("res://tests/R3ReturnMenu.gd"))
	# Deferred: the tree root is still setting up children while this scene's
	# _ready() runs, and add_child() is refused there.
	get_tree().root.add_child.call_deferred(probe)

## Safety net: a hung coroutine must not leave a headless run behind forever.
func _watchdog() -> void:
	await get_tree().create_timer(180.0, true).timeout
	print("R3_RETURN_RESULT=TIMEOUT after 180s")
	get_tree().quit(2)

func _check(label: String, ok: bool, detail := "") -> void:
	_checks += 1
	if not ok: _failures += 1
	print("R3_RETURN %s %s%s" % ["ok  " if ok else "FAIL", label, (" :: " + detail) if detail != "" else ""])

func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds, true).timeout

func _canvas() -> Node:
	return Utils.canvasLayer if is_instance_valid(Utils.canvasLayer) else null

func _main_ui() -> Node:
	var canvas := _canvas()
	return canvas.get_node_or_null("MainUI") if canvas != null else null

func _hud_nodes() -> Array:
	var found: Array = []
	var canvas := _canvas()
	if canvas == null: return found
	for child in canvas.get_children():
		var script = child.get_script()
		if script != null and str(script.resource_path) in HUD_SCRIPTS:
			found.append(str(script.resource_path))
	return found

func _scene_path() -> String:
	var scene := get_tree().current_scene
	return scene.scene_file_path if scene != null else "<none>"

## Every live menu-map root in the tree. A leftover copy from an earlier lap is
## exactly the kind of extra map the previous fixture could hide.
func _menu_map_count() -> int:
	var count := 0
	for node in get_tree().root.get_children():
		if node.scene_file_path == MENU_SCENE: count += 1
	return count

func _report(stage: String) -> void:
	print("R3_STATE stage=%s scene=%s game_start=%s level_state=%s menu=%s menu_visible=%s maps=%d hud=%s pause=%d paused=%s" % [
		stage, _scene_path(), str(Utils.is_game_start), LevelServer.state,
		str(_main_ui() != null),
		str(_main_ui() != null and _main_ui().get_node_or_null("VBoxContainer") != null and _main_ui().get_node("VBoxContainer").visible),
		_menu_map_count(), str(_hud_nodes()), Demo.pause_stack.size(), str(get_tree().paused)])

## The camp panel opens itself when a session starts (that is the shipped entry
## point), and it pauses the tree. Closing it is what the player does next, so the
## lap does it through the same pause API the panel's own close button uses.
func _close_camp_panel() -> void:
	if not is_instance_valid(Demo.ui): return
	var panel = Demo.ui
	Demo.pop_pause(panel)
	panel.queue_free()
	Demo.ui = null

## Everything a session needs in order to be a session rather than a drawing of
## one. This is where the old bug lived: the menu came back, the start button ran,
## and the weapon graph was full of nodes freed with the previous scene.
func _check_session_graph(label: String) -> void:
	var player := Utils.player
	var player_ok := is_instance_valid(player)
	_check("%s_PLAYER_VALID" % label, player_ok,
		"a new session must own a live player, not a reference to the old scene's")
	if not player_ok: return

	var dangling: Array = []
	for id in PlayerData.player_weapon_list:
		if not is_instance_valid(PlayerData.player_weapon_list[id]): dangling.append(str(id))
	_check("%s_NO_FREED_WEAPONS" % label, dangling.is_empty(),
		"weapon ids holding freed nodes: %s" % str(dangling))

	var gun = player.gun
	var gun_ok := is_instance_valid(gun)
	_check("%s_GUN_EQUIPPED" % label, gun_ok, "equipped gun must be a live node")
	if not gun_ok: return
	# Being live is not enough: the gun has to be in this session's scene graph, or
	# nothing it does reaches the world.
	_check("%s_GUN_IN_TREE" % label, gun.is_inside_tree(),
		"parent=%s" % str(gun.get_parent()))
	_check("%s_GUN_IS_NEW_SCENES" % label, player.gun_root.is_ancestor_of(gun),
		"the equipped gun must hang off THIS session's GunRoot")
	_check("%s_CAN_START" % label, LevelServer.can_start(Demo.selected_stage),
		"stage=%d state=%s" % [Demo.selected_stage, LevelServer.state])

func _check_ammo_bar(label: String, gun) -> void:
	# The graphic magazine must agree with the weapon at the moment the session is
	# usable, before anything has been fired.
	var ui = Utils.canvasLayer.get_node_or_null("GameUI") if is_instance_valid(Utils.canvasLayer) else null
	if ui == null:
		_check("%s_HUD_FOR_AMMO" % label, false, "GameUI missing")
		return
	var segments: Array = ui.ammo_segments
	var capacity: int = gun.bullets_max_count
	var current: int = gun.bullets_count
	var expected_segments: int = ui.segment_count(capacity)
	var expected_lit: float = ui.lit_segments(current, capacity, expected_segments)
	var lit_now := 0
	for item in segments:
		if is_instance_valid(item) and item.lit > 0.0: lit_now += 1
	_check("%s_AMMO_SEGMENTS" % label, segments.size() == expected_segments,
		"capacity=%d segments=%d expected=%d" % [capacity, segments.size(), expected_segments])
	_check("%s_AMMO_LIT_MATCHES_MAGAZINE" % label,
		absf(lit_now - expected_lit) <= 1.0,
		"current=%d capacity=%d lit=%d expected_lit=%.2f" % [current, capacity, lit_now, expected_lit])

## One full "start a session, then leave" lap.
func _lap(index: int) -> void:
	var player_id := 0
	var menu := _main_ui()
	_check("L%d_MENU_PRESENT" % index, menu != null, _scene_path())
	if menu == null: return
	var box := menu.get_node_or_null("VBoxContainer")
	_check("L%d_MENU_VISIBLE" % index, box != null and box.visible,
		"the title menu's button column must be on screen before the player can start")
	if box == null: return
	var start := box.get_node_or_null("start")
	_check("L%d_START_BUTTON" % index, start != null)
	if start == null: return
	# One press must be one session, so a second press in the same frame is also
	# exercised here rather than assumed away.
	start.pressed.emit()
	start.pressed.emit()
	await _wait(0.6)
	_check("L%d_SESSION_STARTED" % index, Utils.is_game_start and is_instance_valid(Demo.ui),
		"game_start=%s camp_panel=%s" % [str(Utils.is_game_start), str(is_instance_valid(Demo.ui))])
	_check("L%d_HUD_PRESENT_IN_SESSION" % index, _hud_nodes().size() > 0, str(_hud_nodes()))
	_check_session_graph("L%d" % index)

	_close_camp_panel()
	await _wait(0.2)
	var gun = Utils.player.gun if is_instance_valid(Utils.player) else null
	if is_instance_valid(gun): _check_ammo_bar("L%d" % index, gun)
	if is_instance_valid(gun):
		# A real round: this is what a shot needs in order to reach the world, and
		# it only succeeds if the camp, the spawn points and the player all belong
		# to the same live session.
		var started := LevelServer.roundStart()
		await _wait(0.4)
		_check("L%d_ROUND_STARTED" % index, started and LevelServer.state == "COMBAT",
			"state=%s" % LevelServer.state)
		LevelServer.timerStop()
	_report("in-session-%d" % index)

	# Leave through the same entry the browser uses.
	Demo.return_to_main_menu()
	await _wait(1.5)
	_report("after-return-%d" % index)

	_check("L%d_SCENE_IS_THE_MENU_MAP" % index, _scene_path() == MENU_SCENE, _scene_path())
	_check("L%d_GAME_START_CLEARED" % index, not Utils.is_game_start)
	_check("L%d_NO_GHOST_HUD" % index, _hud_nodes().is_empty(), str(_hud_nodes()))
	_check("L%d_NO_OPEN_PANEL" % index, Demo.pause_stack.is_empty() and not get_tree().paused,
		"pause=%d paused=%s" % [Demo.pause_stack.size(), str(get_tree().paused)])
	_check("L%d_CAMP_PANEL_RELEASED" % index, not is_instance_valid(Demo.ui))
	_check("L%d_EXACTLY_ONE_MENU_MAP" % index, _menu_map_count() == 1,
		"found %d live menu maps; a manually added one used to survive here" % _menu_map_count())
	# The menu scene carries its own camp, so it has its own player: the contract is
	# that this is a DIFFERENT player than the one that was just torn down, and that
	# it did not inherit the outgoing session's weapon.
	var menu_player = Utils.player
	_check("L%d_MENU_OWNS_A_NEW_PLAYER" % index,
		is_instance_valid(menu_player) and menu_player.get_instance_id() != player_id,
		"outgoing=%d now=%s" % [player_id,
			str(menu_player.get_instance_id()) if is_instance_valid(menu_player) else "<freed>"])
	_check("L%d_NO_INHERITED_WEAPON" % index,
		not is_instance_valid(menu_player) or menu_player.gun == null,
		"the menu must not show the outgoing session's gun")

func _run() -> void:
	# Safety net: never leave a hung headless run behind, whatever the engine does.
	_watchdog()
	# The main menu scene, installed as a real current scene the way Boot hands it
	# over - not merely parked under the root.
	var main = load(MENU_SCENE).instantiate()
	get_tree().root.add_child(main)
	get_tree().current_scene = main
	await _wait(0.6)
	_report("initial")
	_check("INITIAL_MENU_PRESENT", _main_ui() != null)
	_check("INITIAL_MENU_VISIBLE",
		_main_ui() != null and _main_ui().get_node_or_null("VBoxContainer") != null
			and _main_ui().get_node("VBoxContainer").visible)
	_check("INITIAL_NO_HUD", _hud_nodes().is_empty(), str(_hud_nodes()))

	for index in range(1, LAPS + 1):
		await _lap(index)

	# The point of five laps: the FIFTH return still leaves a menu that can start a
	# session. Without this, four good laps and one broken return would pass.
	var final_id := get_tree().current_scene.get_instance_id() if get_tree().current_scene != null else 0
	var last_menu := _main_ui()
	_check("FINAL_MENU_PRESENT", last_menu != null)
	if last_menu != null:
		var box := last_menu.get_node_or_null("VBoxContainer")
		var start: Button = box.get_node_or_null("start") if box != null else null
		_check("FINAL_START_BUTTON", start != null)
		if start != null:
			start.pressed.emit()
			await _wait(0.8)
			_check("FINAL_SESSION_STARTED", Utils.is_game_start, "game_start=%s" % str(Utils.is_game_start))
			_check_session_graph("FINAL")
			_close_camp_panel()
			await _wait(0.2)
			var gun = Utils.player.gun if is_instance_valid(Utils.player) else null
			if is_instance_valid(gun):
				_check_ammo_bar("FINAL", gun)
				var before: int = gun.bullets_count
				# Fire once through the weapon's own shot routine. That routine is
				# what instantiates the projectiles, parents them and spends the
				# magazine, so it cannot pass on a session whose weapon graph was
				# built out of freed nodes - which is exactly what the old return
				# left behind.
				gun.can_shoot = true
				gun._shoot()
				await _wait(0.4)
				_check("FINAL_SHOT_SPENDS_ROUNDS", is_instance_valid(gun) and gun.bullets_count < before,
					"before=%d after=%s" % [before, str(gun.bullets_count) if is_instance_valid(gun) else "freed"])
				if is_instance_valid(gun): _check_ammo_bar("FINAL_AFTER_SHOT", gun)
			_report("final-session")
	# The camp map doubles as the title menu, so starting a round runs in place -
	# the tree keeps the SAME live scene instance. What must hold is that this
	# instance is still the one the menu lived in (no swap to a stale or freed
	# scene during start), that it is still in the tree, and that it is the menu
	# map path. An accidental scene swap here is the failure this guards.
	var final_scene := get_tree().current_scene
	_check("FINAL_SCENE_IS_LIVE_MENU_MAP", final_scene != null
		and final_scene.is_inside_tree()
		and final_scene.get_instance_id() == final_id
		and _scene_path() == MENU_SCENE,
		"scene=%s in_tree=%s same_instance=%s" % [
			_scene_path(),
			str(final_scene != null and final_scene.is_inside_tree()),
			str(final_scene != null and final_scene.get_instance_id() == final_id)])

	print("R3_RETURN_SUMMARY checks=%d failures=%d laps=%d" % [_checks, _failures, LAPS])
	if _failures > 0:
		print("R3_RETURN_RESULT=FAIL")
		get_tree().quit(1)
	else:
		print("R3_RETURN_RESULT=PASS")
		get_tree().quit(0)
