extends Control

func _ready():
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var shade = ColorRect.new()
	shade.color = Color(0.03,0.07,0.1,0.98)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(shade)
	var box = VBoxContainer.new()
	var scroll = ScrollContainer.new()
	scroll.position = Vector2(85,15)
	scroll.size = Vector2(240,172)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var t = Theme.new()
	t.default_font = load("res://fonts/fusion-pixel.otf")
	t.default_font_size = 8
	box.theme = t
	scroll.add_child(box)
	var heading = Label.new()
	heading.text = "设置 · 调整后立即保存"
	box.add_child(heading)
	for bus in ["Master","Music","SFX","UI"]:
		var text = Label.new()
		text.text = {"Master":"总音量","Music":"音乐","SFX":"战斗音效","UI":"界面音效"}[bus]
		box.add_child(text)
		var slider = HSlider.new()
		slider.max_value = 100
		slider.value = float(ConfigUtils.getConfig("demo_audio",bus)) if ConfigUtils.getConfig("demo_audio",bus) != null else 80
		slider.value_changed.connect(func(value):
			Demo.set_volume(bus,value)
			ConfigUtils.setConfig("demo_audio",bus,value))
		box.add_child(slider)
	var shake = HSlider.new()
	shake.max_value = 1
	shake.step = 0.05
	shake.value = Utils.shake
	var shake_label = Label.new()
	shake_label.text = "震屏强度（0关闭）"
	box.add_child(shake_label)
	box.add_child(shake)
	shake.value_changed.connect(func(value): Utils.shake = value; ConfigUtils.setConfig("demo","shake",value))
	var flash = CheckButton.new()
	flash.text = "降低闪光"
	flash.button_pressed = Combat.reduced_flash
	flash.toggled.connect(func(value): Combat.reduced_flash = value; ConfigUtils.setConfig("demo","reduced_flash",value))
	box.add_child(flash)
	var screen = Button.new()
	screen.text = "切换窗口 / 全屏"
	screen.pressed.connect(func(): DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED if DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN else DisplayServer.WINDOW_MODE_FULLSCREEN))
	box.add_child(screen)
	var back = Button.new()
	back.text = "返回上一层 [Esc]"
	back.pressed.connect(close)
	back.position = Vector2(85,192)
	back.size = Vector2(116,31)
	back.theme = t
	add_child(back)
	var exit = Button.new()
	exit.text = "退出游戏"
	exit.position = Vector2(209,192)
	exit.size = Vector2(116,31)
	exit.theme = t
	exit.pressed.connect(Demo.quit_game)
	add_child(exit)

func close():
	Demo.pop_pause(self)
	queue_free()

func _unhandled_input(event):
	if event.is_action_pressed("ui_cancel") and Demo.top_pause(self):
		get_viewport().set_input_as_handled()
		close()
