@tool
extends TextureRect

var rotation_speed = PI

func _ready() -> void:
	set_process(false)
	if not Engine.is_editor_hint(): Utils.onGameStart.connect(self.onGameStart)

func onGameStart():
	set_process(true)
	Utils.set_gameplay_mouse_mode()

func _process(delta: float) -> void:
	rotation += rotation_speed * delta
	global_position = Utils.get_aim_viewport_position() - size / 2
