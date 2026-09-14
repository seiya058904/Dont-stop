extends Node
var checks = 0
var failures = 0
var town
func check(ok,name):
	checks += 1
	if not ok: failures += 1
	print(("PASS " if ok else "FAIL ")+name)
func frames(count = 3):
	for frame in count: await get_tree().process_frame
func close_menus():
	for menu in Demo.pause_stack.duplicate():
		Demo.pop_pause(menu); menu.queue_free()
func detail_text(panel):
	var result = ""
	for child in panel.detail.get_children():
		if child is Label: result += child.text+"\n"
	return result
func _ready():
	process_mode = Node.PROCESS_MODE_ALWAYS
	Demo.test_mode = true
	add_child(load("res://game/map/Main.tscn").instantiate())
	Utils.gameStart(); PlayerData.gold = 100000; PlayerData.reward_point = 9999
	await frames(8)
	check(main_ui().level_label.text.ends_with("1"),"R06 fresh profile HUD shows level one before first upgrade")
	town = LevelServer.town
	var position_before = Utils.player.global_position
	check(not town.depart(1,false) and Utils.player.global_position == position_before,"R05 no gun rejects without teleport")
	for id in Utils.weapon_list: Demo.try_purchase("weapon",id)
	Demo.try_purchase("attachment","110")
	for restarted in [false,true]:
		for after_trial in [false,true]:
			Demo.next_stage = 1
			town.depart(1,false)
			LevelServer.victory()
			close_menus(); await frames()
			if after_trial:
				town.depart(4,true); LevelServer.victory(); close_menus(); await frames()
			if restarted:
				Demo.save_path = "res://evidence/r1-save/flow.json"
				Demo.test_mode = false; Demo.save_camp(); Demo.test_mode = true
				check(Demo.load_camp(),"R05 persisted camp restored")
			var before_epoch = LevelServer.epoch
			town._on_portal_move_in(town.portal_lv1)
			town._on_portal_move_in(town.portal_lv1)
			town._on_portal_2_move_out()
			check(LevelServer.level == 2 and not Demo.trial and LevelServer.epoch == before_epoch+1,"R05 old portal normal progress reload="+str(restarted)+" aftertrial="+str(after_trial))
			LevelServer.return_to_camp(); await frames()
			town.depart(4,false)
			check(LevelServer.level == 2 and not Demo.trial,"R05 menu normal ignores stale trial stage")
			LevelServer.return_to_camp(); await frames()
	position_before = Utils.player.global_position
	check(not town.depart(999,true) and Utils.player.global_position == position_before,"R05 invalid encounter has no teleport")
	Utils.player.is_dead = true
	check(not town.depart(1,false),"R05 dead player cannot depart")
	Utils.player.is_dead = false
	Utils.player.changeWeapon(0)
	var gun = Utils.player.gun
	gun.bullets_count -= 2; gun.reload_ammo()
	var generation = gun.action_generation
	var reload_left = gun.change_timer.time_left
	check(PlayerData.changeWeapon(0) and gun.action_generation == generation and gun.is_reloading and gun.change_timer.time_left == reload_left,"R06 same gun equip has no action side effect")
	check(PlayerData.changeWeapon(4),"switch request starts next gun")
	check(not PlayerData.changeWeapon(6),"switch repeat input debounced")
	await get_tree().create_timer(0.14,true).timeout
	check(PlayerData.changeWeapon(6) and not gun.is_reloading,"switch unlocked before .15s and cancels old reload")
	Demo.open_panel(); await frames()
	var panel = Demo.ui
	panel.tab = "weapon"; panel.selection = "114"; panel.render(); await frames()
	panel.listing_scroll.scroll_vertical = 80; await frames()
	var scroll = panel.listing_scroll.scroll_vertical
	await get_tree().create_timer(0.14,true).timeout
	PlayerData.changeWeapon(114,true); await frames(5)
	check(panel.tab == "weapon" and panel.selection == "114" and panel.listing_scroll.scroll_vertical == scroll,"R06 selection tab scroll preserved on equip")
	check(panel.action_bar.get_child(0).text == "当前装备" and panel.action_bar.get_child(0).disabled,"R06 equipped detail refreshes")
	panel.tab = "legacy"; panel.selection = "5"; panel.render()
	panel.purchase("legacy","5"); await frames()
	check("1 / 99" in detail_text(panel),"R06 original reward rank immediately refreshes")
	panel.tab = "talent"; panel.selection = "T01"; panel.render()
	panel.purchase("talent","T01"); await frames()
	check("1 / 3" in detail_text(panel),"R06 talent rank immediately refreshes")
	check("下一等级：累计伤害 +16%" in detail_text(panel),"R06 next talent rank displays its cumulative effective value")
	panel.tab = "attachment"; panel.selection = "110"; panel.render()
	panel.purchase("attachment","110"); await frames()
	check(panel.tab == "attachment" and panel.selection == "110" and panel.purchased_instance == Demo.next_instance-1,"M4 purchase preserves shop tab and locates new instance")
	var am = PlayerData.player_am_list[Demo.next_instance-1]
	gun = PlayerData.player_weapon_list[0]
	var details_scroll = panel.detail.get_parent()
	details_scroll.scroll_vertical = 30; await frames()
	var detail_offset = details_scroll.scroll_vertical
	gun.addAttachMent(am); await frames()
	check(details_scroll.scroll_vertical == detail_offset,"R06 attachment detail scroll preserved on install")
	check("已装备到" in detail_text(panel),"R06 attachment install detail synchronized")
	gun.removeAttachMent(am); await frames()
	check("未装备" in detail_text(panel),"R06 attachment removal detail synchronized")
	var before_gun = Utils.player.gun
	var event = InputEventMouseButton.new(); event.button_index = MOUSE_BUTTON_WHEEL_DOWN; event.pressed = true
	Input.parse_input_event(event); await frames()
	check(Utils.player.gun == before_gun,"menu wheel never changes held weapon")
	panel.queue_free(); await frames()
	town.practice(1); await frames()
	check(get_tree().get_nodes_in_group("monsters").filter(func(m): return m.training).size() == 1,"practice single target")
	town.practice(3); await frames()
	check(get_tree().get_nodes_in_group("monsters").filter(func(m): return m.training).size() == 3,"practice three targets replaces prior targets")
	var before = [PlayerData.gold,PlayerData.player_exp,Demo.kill_stacks,Combat.kill_events]
	for target in get_tree().get_nodes_in_group("monsters"): Combat.hit(target,{"damage":2000})
	check(before == [PlayerData.gold,PlayerData.player_exp,Demo.kill_stacks,Combat.kill_events],"practice grants no money XP kills or stacks")
	town.depart(1,true); await frames()
	check(get_tree().get_nodes_in_group("monsters").filter(func(m): return m.training).is_empty(),"practice targets cleared before formal encounter")
	LevelServer.return_to_camp(); await frames()
	var game_ui = main_ui()
	var fresh = {"schema_version":2,"gold":9999,"points":9999,"ammo":100,"level":1,"exp":0,"hp":5,"hp_max":5,"weapons":[],"attachments":[],"talents":{},"legacy":[],"legacy_state":{},"next_instance":1,"next_stage":1,"selected_stage":1,"equipped":""}
	var file = FileAccess.open(Demo.save_path,FileAccess.WRITE); file.store_string(JSON.stringify(fresh)); file.close()
	Demo.load_camp(); await frames(5)
	check(game_ui.weapon_lsit_node.get_child_count() == 0 and game_ui.rw_grid.get_child_count() == 0,"R06 full snapshot replacement clears old HUD ownership")
	print("R1 FLOW checks=",checks," failures=",failures)
	await Demo.quit_game()

func main_ui():
	for node in get_tree().root.find_children("*","Control",true,false):
		if node.get_script() == load("res://ui/GameUI.gd"): return node
	return null
