extends Node
func _ready():
	var view = SubViewport.new()
	view.size = Vector2i(410,230)
	view.world_2d = get_viewport().world_2d
	view.render_target_update_mode = SubViewport.UPDATE_DISABLED if DisplayServer.get_name() == "headless" else SubViewport.UPDATE_ALWAYS
	add_child(view)
	view.add_child(load("res://game/map/Main.tscn").instantiate())
	TranslationServer.set_locale("en" if "en" in OS.get_cmdline_user_args() else "zh_CN")
	for frame in 3: await get_tree().process_frame
	var button = Utils.canvasLayer.get_node("MainUI/VBoxContainer/quit")
	print("MAIN EXIT LABEL ",button.text," TRANSLATED ",tr(button.text))
	if not button.is_visible_in_tree() or not Rect2(0,0,410,230).encloses(button.get_global_rect()):
		print("FAIL main-menu exit is not visible"); get_tree().quit(1); return
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		var picture = view.get_texture().get_image(); picture.resize(1366,768,Image.INTERPOLATE_NEAREST)
		picture.save_png("res://evidence/main-exit.png")
	for pressed in [true,false]:
		var event = InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.position = button.get_global_rect().get_center()
		event.pressed = pressed
		view.push_input(event,true)
	print("MAIN EXIT CLICK DISPATCHED")
	await get_tree().create_timer(2,true).timeout
	print("FAIL main-menu exit click left process running")
	get_tree().quit(1)
