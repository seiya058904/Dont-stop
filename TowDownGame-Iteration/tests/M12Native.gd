extends Node
# A real 1366x768 root window, distinct from the small offscreen regression viewport.
func wait(seconds: float): await get_tree().create_timer(seconds,true).timeout
func snap(name: String):
	await wait(0.15); RenderingServer.force_draw(false)
	var image=get_viewport().get_texture().get_image()
	image.save_png("res://docs/iteration/evidence/m12/native-"+name+".png")
	print("NATIVE_CAPTURE ",name," ",image.get_size())
func _ready():
	Demo.test_mode=true
	assert(get_window().size==Vector2i(1366,768))
	add_child(load("res://game/map/Main.tscn").instantiate())
	Utils.gameStart(); await wait(0.4)
	var installed=load("res://tests/M11Builds.gd").install("B")
	assert(installed.failures.is_empty())
	Demo.open_stats(); await snap("build")
	var panel=Demo.pause_stack.back()
	var icon=panel.owned_icons.values()[0]; icon.show_build_tooltip(); await snap("tooltip")
	panel.queue_free(); await wait(0.1)
	Demo.open_panel(); await wait(0.1)
	Demo.ui.tier_filter=5; Demo.ui.tier_box.select(5); Demo.ui.selection="124"; Demo.ui.render()
	Demo.ui.detail_actions["124"].call(); await snap("shop")
	var candidates=Demo.ui.detail_actions.keys().filter(func(id): return int(id)!=Utils.player.gun.weapon_id)
	assert(not candidates.is_empty())
	Demo.ui.selection=candidates[0]; Demo.ui.detail_actions[candidates[0]].call(); await snap("shop-comparison")
	Demo.root_lesson(); await snap("lesson-explanation")
	Demo.start_root_lesson()
	await wait(0.4); await snap("lesson-objective")
	var deadline=Time.get_ticks_msec()+10000
	while Demo.lesson_state!="hit" and Demo.lesson_state!="complete" and Time.get_ticks_msec()<deadline: await wait(0.02)
	await snap("lesson-hit")
	while Demo.lesson_state!="complete" and Time.get_ticks_msec()<deadline: await wait(0.02)
	assert(Demo.lesson_state=="complete")
	await snap("lesson-complete")
	Demo.finish_root_lesson(); await wait(0.4)
	assert(LevelServer.state=="CAMP")
	print("PASS native root window walkthrough and return camp")
	await Demo.quit_game()
