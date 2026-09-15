extends Control
var recovery = false
var quitting = false
var note: Label

func _ready():
	process_mode = Node.PROCESS_MODE_ALWAYS
	Demo.push_pause(self)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var shade = ColorRect.new()
	shade.color = Color(0.02,0.04,0.08,0.96)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(shade)
	var box = VBoxContainer.new()
	box.position = Vector2(35,25)
	box.size = Vector2(340,180)
	var font = load("res://fonts/fusion-pixel.otf")
	box.add_theme_font_override("font",font)
	add_child(box)
	note = Label.new()
	note.add_theme_font_override("font",font)
	note.add_theme_font_size_override("font_size",9)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.text = Demo.save_result.reason
	box.add_child(note)
	if recovery:
		add_button(box,"导出坏档原文",func(): note.text = Demo.export_bad_save())
		add_button(box,"重试读取原存档",func():
			if Demo.load_camp(): queue_free()
			else: note.text = "仍无法读取；请导出原文后检查")
		add_button(box,"明确建立新体验档（先备份原文）",func():
			if Demo.create_new_save(): queue_free()
			else: note.text = "新档建立失败，未接管原文件")
	else:
		add_button(box,"重试保存（不重复购买）",func():
			var result = Demo.save_camp()
			note.text = result.reason
			if result.success:
				# Platform-aware: this must not reach finish_quit() on Web, where
				# there is no process to end and get_tree().quit() would leave the
				# browser frozen on the last frame.
				if quitting: Demo.leave_after_save()
				else: queue_free())
	# Web "quit" returns to a live main menu, so the labels say 返回 there instead
	# of promising to end a program that a browser tab cannot end.
	var leave_word := "返回" if OS.has_feature("web") else "退出"
	add_button(box,("取消" + leave_word) if quitting else "临时试玩 / 返回",queue_free)
	if quitting: add_button(box,("放弃本次未保存变化并" + leave_word),Demo.leave_after_save)

func add_button(box, text, action):
	var button = Button.new()
	button.text = text
	button.add_theme_font_override("font",load("res://fonts/fusion-pixel.otf"))
	button.add_theme_font_size_override("font_size",9)
	button.pressed.connect(action)
	box.add_child(button)

func _exit_tree():
	Demo.pop_pause(self)
