extends Control

@onready var setting_ui = $SettingUI

const pre = preload("res://ui/ModeSelect.tscn")

func _ready() -> void:
	Utils.onGameStart.connect(self.onGameStart)
	# The web shell (web/loader.html) waits for this before it drops its loading
	# overlay, so what it reveals is the real, already-drawn title menu.
	Utils.notify_web_boot_menu_ready()

func _on_start_pressed() -> void:
	# One press = one session. A second press (double click, keyboard repeat) must
	# not emit onGameStart again, re-create the HUD or re-open the camp panel.
	if Utils.is_game_start: return
	Utils.gameStart()
	Demo.open_panel()

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
