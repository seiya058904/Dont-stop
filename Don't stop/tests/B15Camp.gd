extends "res://tests/M8Runtime.gd"

func slot_button(panel, slot):
	return panel.find_children("*","Button",true,false).filter(func(b): return b.get_meta("action_id","") == "select_slot" and b.get_meta("slot_id",-1) == slot)[0]

func _ready():
	await boot()
	for id in [0,112,116,113,120,121,124]: Demo.try_purchase("weapon",str(id))
	Demo.open_panel()
	await wait(0.2)
	var panel = Demo.ui
	for resolution in [Vector2i(1280,720),Vector2i(1366,768)]:
		get_window().size = resolution
		await wait(0.2)
		print("CAMP_RECT window=",resolution," detail=",panel.detail_scroll.size," header=",panel.weapon_header.size)
		check(panel.detail_scroll.size.y >= 66,"six body lines at "+str(resolution))
		if DisplayServer.get_name() != "headless":
			var image = play_view.get_texture().get_image()
			image.save_png("res://evidence/visual-upgrade-20260919/b15-camp-%s-%s.png" % [OS.get_cmdline_user_args()[0],resolution.x])
	panel.search_text = "Uzi"
	panel.render()
	PlayerData.switch_deadline = Time.get_ticks_msec()+10000
	slot_button(panel,1).pressed.emit()
	await wait(0.1)
	check(panel.selection == "112" and panel.weapon_heading.text == "跃迁电弧枪","filtered slot opens arc detail even when equip is refused")
	check(panel.search_text == "Uzi","slot preserves filter")
	check(panel.detail_scroll.scroll_vertical == 0,"new slot starts at top")
	panel.replacement_weapon = 124
	panel.switch_tab("talent")
	check(panel.replacement_weapon == -1,"tab cancels replacement")
	print("B15 CAMP checks=",checks," failures=",failures)
	dismiss()
	await wait(0.1)
	get_tree().quit(1 if failures else 0)
