extends Control
var heading: String
var explanation: String
var action_text: String
var action: Callable
func _enter_tree():
	process_mode=Node.PROCESS_MODE_ALWAYS; Demo.push_pause(self)
func _exit_tree(): Demo.pop_pause(self)
func _ready():
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var shade=ColorRect.new(); shade.color=Color(0.03,0.04,0.09,0.95)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); add_child(shade)
	var box=VBoxContainer.new(); box.position=Vector2(50,30); box.size=Vector2(310,180); add_child(box)
	var theme_res=Theme.new(); theme_res.default_font=load("res://fonts/fusion-pixel.otf"); theme_res.default_font_size=9; box.theme=theme_res
	var title=Label.new(); title.text=heading; title.add_theme_font_size_override("font_size",12); box.add_child(title)
	var body=Label.new(); body.text=explanation; body.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART; body.size_flags_vertical=Control.SIZE_EXPAND_FILL; box.add_child(body)
	var start=Button.new(); start.text=action_text; start.pressed.connect(action); box.add_child(start)
	if Demo.lesson_state=="explanation":
		var cancel=Button.new(); cancel.text="暂不训练"; cancel.pressed.connect(func(): Demo.lesson_state=""; queue_free()); box.add_child(cancel)
func _unhandled_input(event):
	if event.is_action_pressed("ui_cancel") and Demo.top_pause(self):
		get_viewport().set_input_as_handled()
		if Demo.lesson_state=="explanation": Demo.lesson_state=""; queue_free()
