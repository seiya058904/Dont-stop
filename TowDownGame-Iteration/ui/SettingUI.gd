extends ColorRect

@onready var volume_slider = $VBoxContainer/VBoxContainer/Control2/volume
@onready var shake_slider = $VBoxContainer/VBoxContainer/Control/shake
@onready var language_ui = $VBoxContainer/VBoxContainer/language
# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var language = ConfigUtils.getConfig("setting","language")
	var shake = ConfigUtils.getConfig("setting","shake")
	var volume = ConfigUtils.getConfig("setting","volume")
	if volume != null:
		volume_slider.set_value_no_signal(volume)
	if shake != null:
		shake_slider.set_value_no_signal(shake)
	if language != null:
		language_ui.select(language)
		_on_language_item_selected(language)


#语言旋转
func _on_language_item_selected(index: int) -> void:
	if index == 0:
		TranslationServer.set_locale("en")
		$Button.text = "Exit Game"
	else:
		TranslationServer.set_locale("zh_CN")
		$Button.text = "结束游戏"
	ConfigUtils.setConfig("setting","language",index)

func _on_shake_value_changed(value: float) -> void:
	Utils.shake = clampf(value/100.0,0,1)
	ConfigUtils.setConfig("demo","shake",Utils.shake)

func _on_volume_value_changed(value: float) -> void:
	Demo.set_volume("Master",value)
	ConfigUtils.setConfig("demo_audio","Master",value)

func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("ui_cancel"): return
	if visible and Demo.top_pause(self):
		get_viewport().set_input_as_handled()
		Demo.pop_pause(self)
		queue_free()
	elif not visible and Utils.is_game_start and Demo.pause_stack.is_empty():
		get_viewport().set_input_as_handled()
		Demo.open_settings()

func _on_button_pressed() -> void:
	Demo.quit_game()
