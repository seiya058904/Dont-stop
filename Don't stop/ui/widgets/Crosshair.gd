@tool
extends TextureRect

var rotation_speed = PI

func _ready() -> void:
	set_process(false)
	if Engine.is_editor_hint(): return
	# No aiming indicator belongs on the title menu (the OS pointer is the only
	# cursor there). It appears when the run starts and while the world is live,
	# and is hidden again whenever a pause panel hands control back to the
	# pointer - see Utils/Demo.pause_stack.
	visible = Utils.is_game_start
	Utils.onGameStart.connect(self.onGameStart)

func onGameStart():
	visible = true
	set_process(true)
	Utils.set_gameplay_mouse_mode()

func _process(delta: float) -> void:
	rotation += rotation_speed * delta
	global_position = Utils.get_aim_viewport_position() - size / 2
