extends "res://tests/M4UI.gd"
func _ready():
	Demo.test_mode = true
	var viewport = SubViewport.new(); viewport.size = Vector2i(410,230); viewport.world_2d = get_viewport().world_2d
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS if "capture" in OS.get_cmdline_user_args() else SubViewport.UPDATE_DISABLED
	add_child(viewport); viewport.add_child(load("res://game/map/Main.tscn").instantiate()); Utils.gameStart(); await wait(0.3)
	PlayerData.gold = 100000
	Demo.open_panel(); await frames(); var panel = Demo.ui
	check(panel.tab_buttons.size() == 6 and panel.tab_buttons.has("magazine"),"obvious primary magazine navigation")
	var rect = Rect2(Vector2.ZERO,Vector2(410,230))
	for id in Utils.weapon_list:
		panel.selection = id; panel.render(); await frames()
		check(panel.detail_actions.has(id),"select weapon "+id)
		check(rect.encloses(panel.action_bar.get_global_rect()),"fixed action in 1366x768 logical viewport "+id)
		check(panel.action_bar.get_child_count() == 1,"single persistent primary action "+id)
		var action = panel.action_bar.get_child(0)
		check(action.is_visible_in_tree() and action.size.x >= action.get_minimum_size().x,"purchase button fully visible "+id)
		if not PlayerData.player_weapon_list.has(int(id)):
			var before = PlayerData.gold; action.pressed.emit(); await frames()
			check(PlayerData.player_weapon_list.has(int(id)) and before-PlayerData.gold == Utils.weapon_money_list[id],"actual shop purchase "+id)
		panel.search_text = "impossible-search"; panel.render(); await frames()
		check(panel.selection == id,"filter retains selected identity "+id)
		panel.search_text = ""; panel.render(); await frames()
		check(panel.selection == id and panel.detail_actions.has(id),"filter clearing restores selection "+id)
	panel.switch_tab("magazine"); await frames(); var before = PlayerData.reserve_magazines
	panel.selection = "mag10"; panel.render(); await frames(); panel.action_bar.get_child(0).pressed.emit(); await frames()
	check(PlayerData.reserve_magazines == before+10,"magazine top-level purchase adds ten")
	if "capture" in OS.get_cmdline_user_args():
		for tab in ["weapon","magazine","attachment"]:
			panel.switch_tab(tab); await frames(); await RenderingServer.frame_post_draw
			var picture = viewport.get_texture().get_image(); picture.resize(1366,768,Image.INTERPOLATE_NEAREST); picture.save_png("res://docs/iteration/evidence/m7/shop-"+tab+".png")
	print("M7 SHOP SUMMARY checks=",checks," failures=",failures)
	panel.queue_free(); await frames()
	if failures: get_tree().quit(1)
	else: await Demo.quit_game()
