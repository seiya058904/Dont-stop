extends "res://tests/M8Runtime.gd"
func _ready():
	await boot(); configure(0)
	var npc = LevelServer.town.get_node("RewardNpc")
	Utils.player.global_position = npc.global_position+Vector2(20,0)
	await wait(0.2)
	check(npc.get_node("Button").visible,"player enters actual NPC interaction area")
	var key = InputEventKey.new(); key.physical_keycode = KEY_E; key.pressed = true
	Input.parse_input_event(key); play_view.push_input(key,true); await wait(0.1)
	key = InputEventKey.new(); key.physical_keycode = KEY_E; key.pressed = false
	Input.parse_input_event(key); play_view.push_input(key,true); await wait(0.1)
	print("NPC_DIAGNOSTIC camp=",is_instance_valid(Demo.ui)," pause=",Demo.pause_stack.size())
	var menus = get_tree().get_nodes_in_group("reward_choose")
	check(menus.size()==1 and not is_instance_valid(Demo.ui),"E opens one NPC reward menu instead of camp")
	if not menus.is_empty():
		var menu = menus[0]
		for i in 5:
			var gold = PlayerData.gold
			menu.get_node("NinePatchRect/Button2").pressed.emit()
			await get_tree().create_timer(0.05,true).timeout
			check(menu.list.get_child_count()==3 and PlayerData.gold==gold-10,"actual reroll three and debit once")
		var id = menu.list.get_child(0).id
		var points = PlayerData.reward_point
		menu.list.get_child(0).get_node("Button").pressed.emit()
		await get_tree().create_timer(0.1,true).timeout
		check(PlayerData.reward_point==points-1 and Demo.purchases.has(id),"actual NPC choice grants and charges once")
		menu.get_node("NinePatchRect/Button").pressed.emit()
		await wait(0.1)
		check(Demo.pause_stack.is_empty(),"NPC closes and unpauses")
		npc.get_node("Button").pressed.emit()
		await get_tree().create_timer(0.1,true).timeout
		check(get_tree().get_nodes_in_group("reward_choose").size()==1,"visible OPEN button opens rewards")
		dismiss(); await wait(0.1)
		Utils.player.global_position = npc.global_position+Vector2(180,0)
		await wait(0.2)
		key = InputEventKey.new(); key.physical_keycode = KEY_E; key.pressed = true
		play_view.push_input(key,true)
		await get_tree().create_timer(0.1,true).timeout
		check(is_instance_valid(Demo.ui) and get_tree().get_nodes_in_group("reward_choose").is_empty(),"E away from NPC still opens camp")
	print("M10_INTERACTION_CHECKS ",checks," FAILURES ",failures)
	dismiss(); await Demo.quit_game()
