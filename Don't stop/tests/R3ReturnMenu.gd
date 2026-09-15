extends Node

## R3: the Web replacement for quitting must really present a usable main menu.
##
## Why this is a behavioural test and not a source review: the first version of
## Demo.return_to_main_menu() changed a scene and cleared a flag, and the browser
## acceptance run showed the player still standing in the camp with the in-game HUD
## and no title menu at all - the picture had not "frozen", it had simply never
## gone back. This test drives the real entry point and then checks the things a
## player needs: the title menu is on screen and interactive, no HUD from the old
## session is left behind, and pressing start again begins a fresh session. It runs
## twice, because the whole point is that leaving and returning is repeatable.
##
## Run headless:
##   Godot_v4.7.2-stable_win64.exe --headless --path <project> res://tests/R3ReturnMenu.tscn
##
## The scene change frees the current scene, so the checks live on a probe node
## parented to the tree root instead of to the test scene.

static var _probe_spawned := false

const HUD_SCRIPTS := ["res://ui/DemoHUD.gd", "res://ui/BossHUD.gd"]
const MENU_SCENE := "res://game/map/Main.tscn"

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
	await get_tree().create_timer(90.0, true).timeout
	print("R3_RETURN_RESULT=TIMEOUT after 90s")
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

func _report(stage: String) -> void:
	print("R3_STATE stage=%s scene=%s game_start=%s level_state=%s menu=%s menu_visible=%s hud=%s pause=%d paused=%s" % [
		stage, _scene_path(), str(Utils.is_game_start), LevelServer.state,
		str(_main_ui() != null),
		str(_main_ui() != null and _main_ui().get_node_or_null("VBoxContainer") != null and _main_ui().get_node("VBoxContainer").visible),
		str(_hud_nodes()), Demo.pause_stack.size(), str(get_tree().paused)])

## One full "start a session, then leave" lap. Returns the camp panel instance.
func _lap(index: int) -> void:
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

	# A real session through the game's own entry point.
	start.pressed.emit()
	await _wait(0.6)
	_check("L%d_SESSION_STARTED" % index, Utils.is_game_start and is_instance_valid(Demo.ui),
		"game_start=%s camp_panel=%s" % [str(Utils.is_game_start), str(is_instance_valid(Demo.ui))])
	_check("L%d_HUD_PRESENT_IN_SESSION" % index, _hud_nodes().size() > 0, str(_hud_nodes()))
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

func _run() -> void:
	# Safety net: never leave a hung headless run behind, whatever the engine does.
	_watchdog()
	# The main menu scene, exactly as Boot hands it over.
	var main = load(MENU_SCENE).instantiate()
	get_tree().root.add_child(main)
	await _wait(0.6)
	_report("initial")
	_check("INITIAL_MENU_PRESENT", _main_ui() != null)
	_check("INITIAL_MENU_VISIBLE",
		_main_ui() != null and _main_ui().get_node_or_null("VBoxContainer") != null
			and _main_ui().get_node("VBoxContainer").visible)
	_check("INITIAL_NO_HUD", _hud_nodes().is_empty(), str(_hud_nodes()))

	await _lap(1)
	await _lap(2)

	print("R3_RETURN_SUMMARY checks=%d failures=%d" % [_checks, _failures])
	if _failures > 0:
		print("R3_RETURN_RESULT=FAIL")
		get_tree().quit(1)
	else:
		print("R3_RETURN_RESULT=PASS")
		get_tree().quit(0)
