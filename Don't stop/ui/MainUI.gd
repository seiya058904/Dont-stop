extends Control

@onready var setting_ui = $SettingUI

const pre = preload("res://ui/ModeSelect.tscn")

func _ready() -> void:
	_apply_web_rendering_fallback()
	Utils.onGameStart.connect(self.onGameStart)
	$VBoxContainer/start.mouse_entered.connect(_on_start_hovered)
	# A web page is left by closing its tab; a button pretending to end the program
	# would only freeze the last frame. Native builds keep their quit entry and the
	# existing save-failure confirmation.
	if OS.has_feature("web"):
		$VBoxContainer/quit.visible = false
		await _warm_web_first_use()
	Utils.startup_mark("menu-initialized")
	_mark_menu_presented()

## The Web Compatibility renderer has no useful post-process glow fallback on
## software-rendered browsers: the title menu's first glow pass can block the
## frame that should deliver the first button hover. Keep the authored map,
## sprites, lights and combat materials intact; only skip this optional
## compositor effect on Web so input remains responsive on low-end browsers.
func _apply_web_rendering_fallback() -> void:
	if not OS.has_feature("web"):
		return
	var scene := get_tree().current_scene
	if scene == null:
		return
	var world := scene.get_node_or_null("WorldEnvironment") as WorldEnvironment
	if world != null and world.environment != null:
		world.environment.glow_enabled = false
	# Keep the authored dynamic lighting visible on Web. Disabling the whole
	# light pass made the map visibly darker; only its expensive shadow pass
	# is skipped for the browser compatibility path.
	for node in scene.find_children("*", "PointLight2D", true, false):
		var light := node as PointLight2D
		if light != null:
			light.shadow_enabled = false

func _warm_web_first_use() -> void:
	# The settings tree is already part of the menu scene; one covered frame
	# compiles its controls before the first real click.
	setting_ui.show()
	await RenderingServer.frame_post_draw
	setting_ui.hide()
	# CampPanel is intentionally created on demand in normal play. Build and
	# draw one disposable copy while the Web loader still covers the canvas so
	# the first real Start click does not pay its UI shader/layout cost.
	var warm_panel := Control.new()
	warm_panel.set_script(load("res://ui/CampPanel.gd"))
	Utils.canvasLayer.add_child(warm_panel)
	Demo.pop_pause(warm_panel)
	await RenderingServer.frame_post_draw
	warm_panel.queue_free()
	await get_tree().process_frame

func _mark_menu_presented() -> void:
	await RenderingServer.frame_post_draw
	Utils.startup_mark("menu-scene-ready")
	if not OS.has_feature("web") and not get_tree().root.has_meta("boot_overlay_active"):
		Utils.startup_mark("menu-first-visible")
	# The web shell waits for this before it drops its loading overlay.
	Utils.notify_web_boot_menu_ready()

func _on_start_pressed() -> void:
	print("[leave] menu start button pressed (game_start=%s)" % str(Utils.is_game_start))
	# One press = one session. A second press (double click, keyboard repeat) must
	# not emit onGameStart again, re-create the HUD or re-open the camp panel.
	if Utils.is_game_start: return
	Utils.startup_mark("menu-start-pressed")
	Utils.gameStart()
	Demo.open_panel()
	Utils.startup_mark("menu-start-returned")
	_mark_after_frame("first-start-feedback")

## Diagnostic: a menu that is drawn and refuses input looks identical to a working
## one in a screenshot, so the round's acceptance driver needs the game to say
## whether a click reached the menu at all.
func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		Utils.startup_mark_once("menu-input-received")
		print("[leave] menu received a mouse press at %s (unhandled=%s)" % [
			str(event.position), str(not get_viewport().is_input_handled())])

func _on_start_hovered() -> void:
	await RenderingServer.frame_post_draw
	Utils.startup_mark_once("menu-first-hover")

func onModeChoose(mode):
	if mode == 0:
		Utils.gameStart()
	else:
		SceneManager.change_scene("res://game/map/SnowWorld/SnowWorld.tscn",
		{ "pattern": "scribbles", "pattern_leave": "squares" }
		)

func onGameStart():
	$VBoxContainer.visible = false
	get_tree().create_tween().tween_property($TextureRect,"modulate:a",0,0.5)

func _on_setting_pressed() -> void:
	Utils.startup_mark("settings-pressed")
	Demo.open_settings()
	Utils.startup_mark("settings-open-returned")
	_mark_after_frame("settings-feedback")

func _mark_after_frame(stage: String) -> void:
	await RenderingServer.frame_post_draw
	Utils.startup_mark(stage)

func _on_quit_pressed() -> void:
	Demo.quit_game()

func _on_mod_pressed() -> void:
	#Utils.showToast("WAIT_MORE")
	pass
