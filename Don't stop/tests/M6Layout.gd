extends "res://tests/M4UI.gd"
func _ready():
	Demo.test_mode = true
	var viewport = SubViewport.new(); viewport.size = Vector2i(410,230)
	viewport.world_2d = get_viewport().world_2d; viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED; add_child(viewport)
	viewport.add_child(load("res://game/map/Main.tscn").instantiate()); Utils.gameStart(); PlayerData.gold = 100000; PlayerData.reward_point = 9999; await wait(0.3)
	for id in Utils.weapon_list: Demo.try_purchase("weapon",id)
	for id in Utils.am_dict: Demo.try_purchase("attachment",id)
	Demo.open_panel(); await frames(); var panel = Demo.ui
	var clipped = []
	for tab in ["weapon","attachment","talent","stage","equipment"]:
		panel.switch_tab(tab); await frames()
		var keys = panel.detail_actions.keys()
		if keys.is_empty(): keys = [""]
		for key in keys:
			if key != "": panel.detail_actions[key].call()
			await frames()
			var labels_fit = true
			for control in panel.find_children("*","Control",true,false):
				if not control.is_visible_in_tree(): continue
				if control is Label:
					labels_fit = labels_fit and (control.autowrap_mode != TextServer.AUTOWRAP_OFF or control.get_minimum_size().x <= control.size.x+1)
				elif control is Button and not control is OptionButton and not control is CheckButton:
					if control.get_minimum_size().x > control.size.x+1: clipped.append({"tab":tab,"id":key,"text":control.text,"minimum":control.get_minimum_size().x,"width":control.size.x})
			check(labels_fit,"detail labels wrap or fit "+tab+"/"+key)
	check(clipped.is_empty(),"buttons fit their allocated widths at logical 410x230")
	var file = FileAccess.open("res://docs/iteration/evidence/m7/regression-artifacts/layout.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"viewport":"410x230 logical; production stretch to desktop","clipped":clipped,"checks":checks,"failures":failures},"\t")); file.close()
	panel.queue_free(); await frames()
	print("M6 LAYOUT SUMMARY checks=",checks," failures=",failures)
	if failures: get_tree().quit(1)
	else: await Demo.quit_game()
