extends "res://tests/M8Runtime.gd"
## Presentation-only regression: model reuse, truthful empty/selected states and pixel scaling.

func _ready():
	await boot()
	configure(0,false)
	Demo.open_panel()
	await wait(0.1)
	var panel = Demo.ui
	var before = EffectiveStats.calculate(Utils.player.gun).duplicate(true)
	var models: Dictionary = panel.weapon_models.duplicate()
	check(models.size() == 24,"all registered weapons have an owned display model")
	panel.search_text = "Uzi"
	panel.selection = "9"
	panel.render()
	check(panel.detail_actions.size() == 1,"search filters the actual catalog")
	check(panel.weapon_header.visible and panel.weapon_heading.text == "Uzi","filtered selection has the correct preview")
	for child in panel.listing.get_children():
		if child is Button and child.has_meta("weapon_id"):
			check(child.button_pressed,"selected weapon row is visibly pressed")
	var texture = panel.weapon_preview.texture
	panel.render()
	check(panel.weapon_preview.texture == texture,"selection reuses its pixel preview texture")
	for id in models:
		check(panel.weapon_models[id] == models[id],"search does not rebuild display model "+id)
	panel.message.text = "保留交易结果"
	panel.search_text = "__no_matching_weapon__"
	panel.render()
	check(panel.detail_actions.is_empty(),"empty search has no stale actions")
	check(not panel.weapon_header.visible and panel.weapon_preview.texture == null,"empty search cannot display the previous weapon")
	check(panel.action_bar.get_child_count() == 0,"empty search cannot purchase the previous weapon")
	check(panel.message.text == "保留交易结果","filtering preserves transaction feedback")
	panel.search_text = "124"
	panel.render()
	panel.selection = "124"
	panel.detail_actions["124"].call()
	check(panel.weapon_header.visible,"selecting a result after an empty selection restores the preview header")
	panel.search_text = ""
	panel.selection = "124"
	panel.render()
	var source: Image = models["124"].image.get_image()
	var used: Rect2i = source.get_used_rect()
	var preview: Texture2D = panel.weapon_preview.texture
	check(preview.get_width() <= 96 and preview.get_height() <= 32,"preview fits its reserved display area")
	check(preview.get_width() % used.size.x == 0 and preview.get_height() % used.size.y == 0,"preview scales source pixels by an integer")
	check("传说" in panel.weapon_badge.text and "金币" in panel.weapon_badge.text,"legendary preview keeps rarity and price")
	check(str(before) == str(EffectiveStats.calculate(Utils.player.gun)),"presentation never changes equipped effective stats")
	print("CAMP_PRESENTATION_CHECKS ",checks," FAILURES ",failures)
	dismiss()
	await wait(0.1)
	if failures: get_tree().quit(1)
	else: await Demo.quit_game()
