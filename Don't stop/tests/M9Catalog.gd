extends "res://tests/M8Runtime.gd"

func _ready():
	await boot()
	play_view.size = Vector2i(1366,768)
	Demo.open_panel(); Demo.ui.switch_tab("weapon"); await wait(0.1)
	var panel = Demo.ui
	check(panel.sort_mode==0,"shop defaults to ascending Tier")
	var ids = panel.detail_actions.keys()
	check(ids.size()==24,"all 24 weapons have actual shop entries")
	var last_tier = 0
	var last_price = 0
	var rows = []
	for id in ids:
		var tier = WeaponCatalog.tier(int(id))
		var price = Utils.weapon_money_list[id]
		check(tier>=last_tier and price>last_price,"actual sorted shop Tier and price "+id)
		check(price==WeaponCatalog.PRICES[id],"shop uses final catalog price "+id)
		last_tier = tier; last_price = price
		rows.append({"id":id,"tier":tier,"price":price})
	if DisplayServer.get_name()!="headless":
		# The menu pauses the scene. Force/read this frame directly; waiting for
		# another automatic draw in a minimized, paused window never completes.
		RenderingServer.force_draw(false)
		play_view.get_texture().get_image().save_png("res://docs/iteration/evidence/m8/m9-shop.png")
	print("M9_CATALOG ",JSON.stringify(rows))
	print("M9_CATALOG_CHECKS ",checks," FAILURES ",failures)
	dismiss(); await wait(0.1)
	if failures: get_tree().quit(1)
	else: await Demo.quit_game()
