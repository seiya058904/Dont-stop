extends Control

@onready var setting_ui = $SettingUI

const pre = preload("res://ui/ModeSelect.tscn")

func _ready() -> void:
	Utils.onGameStart.connect(self.onGameStart)
	# A web page is left by closing its tab; a button pretending to end the program
	# would only freeze the last frame. Native builds keep their quit entry and the
	# existing save-failure confirmation.
	if OS.has_feature("web"):
		$VBoxContainer/quit.visible = false
	# The web shell (web/loader.html) waits for this before it drops its loading
	# overlay, so what it reveals is the real, already-drawn title menu.
	Utils.notify_web_boot_menu_ready()

func _on_start_pressed() -> void:
	print("[leave] menu start button pressed (game_start=%s)" % str(Utils.is_game_start))
	# One press = one session. A second press (double click, keyboard repeat) must
	# not emit onGameStart again, re-create the HUD or re-open the camp panel.
	if Utils.is_game_start: return
	Utils.gameStart()
	Demo.open_panel()

## Diagnostic: a menu that is drawn and refuses input looks identical to a working
## one in a screenshot, so the round's acceptance driver needs the game to say
## whether a click reached the menu at all.
func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		print("[leave] menu received a mouse press at %s (unhandled=%s)" % [
			str(event.position), str(not get_viewport().is_input_handled())])

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
	Demo.open_settings()

func _on_quit_pressed() -> void:
	Demo.quit_game()

func _on_mod_pressed() -> void:
	#Utils.showToast("WAIT_MORE")
	pass
