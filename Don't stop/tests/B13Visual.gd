extends "res://tests/M8Runtime.gd"
## B13 visual acceptance. MUST run windowed (a headless run has no render target):
##   godot --path . --rendering-method gl_compatibility --quit-after 40000 res://tests/B13Visual.tscn
## Captures, into docs/iteration/evidence/b13/visual/:
##   * the upgrade shop filtered to each of the three qualities (quality prefix on cards)
##   * one unowned upgrade's 当前 → 购买后 preview and its owned state after purchase
##   * the talent shop per quality, a legendary mechanism talent's detail, a rank purchase
##   * the full unequip flow with REAL panel clicks: equipped → 卸下武器 → unarmed UI →
##     a real unarmed stage departure → real WASD movement → re-equip → real firing
## Every interactive step goes through the SAME control the player would press.

const OUT := "res://docs/iteration/evidence/b13/visual"

var view: SubViewport

func snap(name: String):
	await RenderingServer.frame_post_draw
	var picture: Image = view.get_texture().get_image()
	picture.resize(1366,768,Image.INTERPOLATE_NEAREST)
	var err: int = picture.save_png("%s/%s.png" % [OUT, name])
	print("B13_VISUAL captured ", name, " err=", err)

func press(panel, text_value: String) -> bool:
	# CampPanel routes detail-page buttons into action_bar, not detail.
	for box in [panel.detail, panel.action_bar]:
		for child in box.get_children():
			if child is Button and child.text == text_value:
				child.pressed.emit()
				return true
	return false

func _ready():
	Demo.test_mode = true
	if DisplayServer.get_name() == "headless":
		print("B13_VISUAL skipped: headless has no render target (run windowed)")
		await Demo.quit_game(); return
	DirAccess.make_dir_recursive_absolute(OUT)
	var sv = SubViewport.new(); view = sv; sv.size = Vector2i(410,230); sv.world_2d = get_viewport().world_2d
	sv.render_target_update_mode = SubViewport.UPDATE_ALWAYS; add_child(sv)
	sv.add_child(load("res://game/map/Main.tscn").instantiate()); Utils.gameStart(); await wait(0.3)
	PlayerData.gold = 100000; PlayerData.reward_point = 9999
	Utils.player.set_process(false); Utils.player.set_physics_process(false)
	Demo.try_purchase("weapon","0")
	Demo.try_purchase("weapon","4")
	# --- the upgrade shop: one capture per quality + a real purchase --------------------
	Demo.open_panel(); Demo.ui.switch_tab("attachment"); await wait(0.2)
	var panel = Demo.ui
	for q in [1,2,3]:
		panel.upgrade_quality_filter = q; panel.render(); await wait(0.1)
		await snap("upgrades-quality-%d" % q)
	panel.upgrade_quality_filter = 0; panel.selection = "118"; panel.render(); await wait(0.1)
	await snap("upgrade-detail-preview")   # 当前 → 购买后 on the current gun
	panel.purchase("attachment","118"); await wait(0.1)
	panel.selection = "118"; panel.render(); await wait(0.1)
	await snap("upgrade-owned-state")
	check("118" in Demo.owned_global_upgrades,"upgrade 118 purchased for the visual")
	# --- the talent shop: qualities, a legendary detail, a real rank purchase ------------
	panel.switch_tab("talent"); await wait(0.1)
	for q in [1,2,3]:
		panel.upgrade_quality_filter = q; panel.render(); await wait(0.1)
		await snap("talents-quality-%d" % q)
	panel.upgrade_quality_filter = 0; panel.selection = "T23"; panel.render(); await wait(0.1)
	await snap("talent-legendary-detail")
	panel.selection = "T01"; panel.render(); await wait(0.1)
	check(press(panel,"金币购买"),"talent gold purchase pressed")
	await wait(0.2)
	panel.selection = "T01"; panel.render(); await wait(0.1)
	await snap("talent-rank1-purchased")
	check(Demo.rank("T01") == 1,"T01 reached rank 1 through the panel")
	# --- the unequip flow with real panel actions -----------------------------------------
	panel.switch_tab("weapon"); panel.selection = "4"; panel.render(); await wait(0.1)
	configure(4,false)
	panel.selection = "4"; panel.render(); await wait(0.1)
	await snap("weapon-equipped-unequip-offered")
	check(press(panel,"卸下武器"),"卸下武器 pressed for real")
	await wait(0.2)
	check(Utils.player.gun == null,"the player is unarmed after the real press")
	await snap("weapon-unarmed-state")
	# --- unarmed stage departure, real movement, no firing, no errors ---------------------
	for menu in Demo.pause_stack.duplicate(): Demo.pop_pause(menu); menu.queue_free()
	await wait(0.1)
	check(LevelServer.town.depart(1,true),"unarmed departure accepted")
	LevelServer.timerStop()
	# The boot disabled the hero's processing for the shop captures; the stage needs it back.
	Utils.player.set_process(true)
	Utils.player.set_physics_process(true)
	await wait(0.3)
	var start_x: float = Utils.player.global_position.x
	Input.action_press("right")
	await wait(1.2)
	Input.action_release("right")
	print("B13_VISUAL move from %.1f to %.1f paused=%s dead=%s"%[start_x,Utils.player.global_position.x,str(get_tree().paused),str(Utils.player.is_dead)])
	check(Utils.player.global_position.x > start_x+20,"WASD movement works unarmed")
	await snap("combat-unarmed-moved")
	check(Utils.player.gun == null,"still unarmed inside the stage")
	var no_shot: int = Combat.damage_events
	await wait(0.5)
	check(Combat.damage_events == no_shot,"nothing fires without a weapon")
	LevelServer.return_to_camp(); await wait(0.4)
	# --- re-equip through the panel and fire for real -------------------------------------
	Demo.open_panel(); await wait(0.2)
	panel = Demo.ui
	panel.switch_tab("weapon"); panel.selection = "4"; panel.render(); await wait(0.1)
	check(press(panel,"已拥有 | 装备"),"re-equip pressed for real")
	await wait(0.3)
	check(Utils.player.gun != null and Utils.player.gun.weapon_id == 4,"re-equipped gun 4 through the panel")
	for menu in Demo.pause_stack.duplicate(): Demo.pop_pause(menu); menu.queue_free()
	await wait(0.1)
	check(LevelServer.town.depart(1,true),"armed departure accepted")
	LevelServer.timerStop()
	Utils.player.set_process(false)
	var target = enemy(Utils.player.global_position+Vector2(60,-8),100)
	target.set_physics_process(false)
	await wait(0.1)
	Utils.aim_override = get_viewport().get_canvas_transform()*(Utils.player.global_position+Vector2(60,-8))
	Utils.player.gun.bullets_count = Utils.player.gun.bullets_max_count
	var hits: int = Combat.damage_events
	for i in 6:
		Utils.player.gun.direction = Vector2.RIGHT
		Utils.player.gun._shoot()
		await wait(0.25)
	check(Combat.damage_events > hits,"re-equipped weapon really fires")
	await snap("combat-armed-firing")
	LevelServer.return_to_camp()
	print("B13_VISUAL_CHECKS ",checks," FAILURES ",failures)
	if failures: get_tree().quit(1)
	else: await Demo.quit_game()
