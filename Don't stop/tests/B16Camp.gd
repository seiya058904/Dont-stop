extends "res://tests/M8Runtime.gd"

func _ready():
	await boot()
	Demo.open_panel()
	await wait(0.2)
	var panel = Demo.ui
	panel.switch_tab("talent")
	var ids = panel.detail_actions.keys()
	check(ids.size() == 24,"all 24 talents present")
	var sorted = ids.duplicate()
	sorted.sort_custom(func(a,b):
		if DemoConfig.talent_quality(a) != DemoConfig.talent_quality(b): return DemoConfig.talent_quality(a) < DemoConfig.talent_quality(b)
		return a < b)
	check(ids == sorted,"talents ordered by quality then stable ID")
	for rank in [0,1,3]:
		Demo.talents["T04"] = rank
		panel.selection = "T04"
		panel.render()
		await wait(0.2)
		print("B16 RECT rank=",rank," detail=",panel.detail_scroll.get_global_rect()," actions=",panel.action_bar.get_global_rect()," minimum=",panel.action_bar.get_combined_minimum_size())
		check(panel.detail_scroll.size.y >= 66,"T04 readable height rank "+str(rank))
		for child in panel.action_bar.get_children():
			if child is Button: check(child.size.y <= 24,"compact payment button rank "+str(rank))
		if rank == 3: check(panel.action_bar.get_child_count() == 0,"max rank has no redundant payment buttons")
		if DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
			play_view.get_texture().get_image().save_png("res://evidence/visual-upgrade-20260919/b16-t04-rank%d-subviewport.png" % rank)
	for page in ["weapon","attachment","magazine","talent","stage"]:
		panel.switch_tab(page)
		await wait(0.2)
		check(panel.detail_scroll.size.y >= 66,"readable detail on "+page)
	print("B16 CAMP checks=",checks," failures=",failures)
	dismiss()
	await wait(0.1)
	get_tree().quit(1 if failures else 0)
