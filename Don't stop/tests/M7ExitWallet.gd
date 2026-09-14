extends Node
var mode = "camp"
func check(ok, message):
	print(("PASS " if ok else "FAIL ")+message)
	if not ok: get_tree().quit(1)
	return ok
func _ready():
	process_mode = Node.PROCESS_MODE_ALWAYS
	if not OS.get_cmdline_user_args().is_empty(): mode = OS.get_cmdline_user_args()[0]
	DirAccess.make_dir_recursive_absolute("res://evidence/m7-exit")
	Demo.save_path = "res://evidence/m7-exit/"+str(Time.get_ticks_usec())+".json"
	var view = SubViewport.new(); view.size = Vector2i(410,230); view.world_2d = get_viewport().world_2d
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS if DisplayServer.get_name() != "headless" else SubViewport.UPDATE_DISABLED
	add_child(view); view.add_child(load("res://game/map/Main.tscn").instantiate())
	if mode != "menu": Utils.gameStart()
	await get_tree().create_timer(0.2,true).timeout
	if mode == "combat":
		Demo.try_purchase("weapon","0")
		Utils.player.changeWeapon(0)
		if not check(LevelServer.town.depart(1,true),"start real combat before opening settings"): return
	Demo.open_settings()
	await get_tree().process_frame
	var settings = Demo.pause_stack.back()
	var exits = settings.find_children("*","Button",true,false).filter(func(b): return b.text == "退出游戏")
	if not check(exits.size() == 1,"current settings exposes exit"): return
	print("EXIT RECT ",exits[0].get_global_rect())
	if not check(Rect2(0,0,410,230).encloses(exits[0].get_global_rect()),"exit visible without scrolling"): return
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		var picture = view.get_texture().get_image(); picture.resize(1366,768,Image.INTERPOLATE_NEAREST)
		picture.save_png("res://evidence/m7-exit/settings.png")
	if mode not in ["menu","combat"]:
		if not check(PlayerData.gold == 9999 and PlayerData.reward_point == 9999,"playtest starts with both wallets 9999"): return
	if mode == "restore":
		PlayerData.gold = 7; PlayerData.reward_point = 8
		if not check(Demo.save_camp().success,"low-balance test save written"): return
		# Exercise the same startup path after loading a legitimate existing camp.
		Demo._start()
		if not check(PlayerData.gold == 9999 and PlayerData.reward_point == 9999,"startup restores and tops up existing wallets"): return
		PlayerData.gold -= 10
		if not check(Demo.save_camp().success and Demo.load_camp() and PlayerData.gold == 9989,"ordinary load preserves spending"): return
	if mode == "window":
		get_tree().root.close_requested.emit()
	else:
		var point = exits[0].get_global_rect().get_center()
		for pressed in [true,false]:
			var event = InputEventMouseButton.new(); event.button_index = MOUSE_BUTTON_LEFT; event.position = point; event.pressed = pressed
			view.push_input(event,true)
	await get_tree().create_timer(0.05,true).timeout
	if mode == "combat":
		if not check(is_instance_valid(Demo.save_dialog) and Demo.save_dialog.quitting,"combat exit offers unsaved-progress choices"): return
		var discard = Demo.save_dialog.find_children("*","Button",true,false).filter(func(b): return b.text == "放弃本次未保存变化并退出")
		if not check(discard.size()==1,"combat discard exit available"): return
		discard[0].pressed.emit()
	print("EXIT REQUESTED ",mode)
	await get_tree().create_timer(3,true).timeout
	print("FAIL process stayed alive after exit request")
	get_tree().quit(1)
