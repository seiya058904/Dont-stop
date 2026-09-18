extends "res://tests/M3Weapons.gd"
func detail_text(panel):
	var result = ""
	for child in panel.detail.get_children():
		if child is Label: result += child.text+"\n"
	return result
func frames():
	for i in 4: await get_tree().process_frame
func _ready():
	Demo.test_mode = true
	var main = load("res://game/map/Main.tscn").instantiate()
	add_child(main)
	Utils.gameStart(); PlayerData.gold = 100000; PlayerData.reward_point = 9999
	await wait(0.2)
	for id in Utils.weapon_list: Demo.try_purchase("weapon",id)
	Demo.open_panel()
	await frames()
	var panel = Demo.ui
	check(panel.detail_actions.size() == 24,"all 24 guns accessible in camp listing")
	panel.search_box.text = "W17"
	panel.search_text = "W17"; panel.render()
	check(panel.detail_actions.keys() == ["117"],"plan ID search maps stable runtime ID")
	panel.search_text = ""; panel.category = "爆炸"; panel.render()
	check(panel.detail_actions.size() == 4,"weapon explosive category real tag filter")
	panel.category = "全部"; panel.selection = "117"; panel.render()
	check(WeaponCatalog.rarity(117) in detail_text(panel),"detail exposes quality name")
	panel.switch_tab("attachment")
	panel.selected_gun = 120; panel.compatible_only = true; panel.render()
	check(panel.detail_actions.has("123") and panel.detail_actions.has("122"),"attachment compatibility filter")
	panel.compatible_only = false; panel.category = "Tactical"; panel.render()
	check(panel.detail_actions.has("123") and panel.detail_actions.has("122"),"attachment slot classification")
	panel.category = "全部"; panel.selection = "123"; panel.render()
	panel.listing_scroll.scroll_vertical = 30
	await frames()
	var scroll = panel.listing_scroll.scroll_vertical
	panel.purchase("attachment","123")
	await frames()
	check(panel.tab == "attachment" and panel.selection == "123" and panel.listing_scroll.scroll_vertical == scroll,"purchase preserves selection tab scroll")
	check("实例 #" in detail_text(panel) and "未装备" in detail_text(panel),"new instance detail immediately shown")
	var am = PlayerData.player_am_list[panel.purchased_instance]
	PlayerData.player_weapon_list[120].addAttachMent(am)
	await frames()
	check("已装备到" in detail_text(panel),"equip detail synced")
	panel.switch_tab("talent")
	check(panel.detail_actions.size() == 24,"all 24 talents visible")
	panel.purchase("talent","T16")
	Demo.blast_cooldown = 0.3
	panel.show_talent("T16")
	check("0.3秒" in detail_text(panel),"display actual kill blast cooldown")
	panel.show_reset()
	await frames()
	var dialog = panel.get_children().filter(func(n): return n is ConfirmationDialog)[0]
	check("100金币" in dialog.dialog_text and "历史缺失付款凭据" in dialog.dialog_text,"reset preview precise payment and unknown warning")
	dialog.canceled.emit()
	await frames()
	check(Demo.rank("T16") == 1,"cancel reset retains level")
	var before = Utils.player.gun.weapon_id
	var wheel = InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_DOWN; wheel.pressed = true
	get_viewport().push_input(wheel)
	await frames()
	check(Utils.player.gun.weapon_id == before,"menu scroll cannot switch gun")
	panel.queue_free()
	await frames()
	check(Demo.pause_stack.is_empty() and not get_tree().paused,"menu cleanly closes")
	print("M4 UI SUMMARY checks=",checks," failures=",failures)
	if failures: get_tree().quit.call_deferred(1)
	else: await Demo.quit_game() # Exercise the existing production audio shutdown, not an abrupt test exit.
