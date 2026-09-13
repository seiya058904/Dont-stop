extends "res://tests/M8Runtime.gd"
func snap(label: String):
	RenderingServer.force_draw(false)
	var picture = play_view.get_texture().get_image()
	if play_view.size.x==410: picture.resize(1366,768,Image.INTERPOLATE_NEAREST)
	picture.save_png("res://docs/iteration/evidence/m10/"+label+".png")
func _ready():
	await boot(); configure(124,true)
	Demo.open_panel(); Demo.ui.switch_tab("weapon")
	for id in ["0","6","111","124"]:
		Demo.ui.detail_actions[id].call(); await get_tree().create_timer(0.1,true).timeout
		snap("shop-"+id)
	Demo.ui.switch_tab("attachment"); await get_tree().create_timer(0.1,true).timeout; snap("upgrade-prices")
	dismiss(); await wait(0.2)
	for id in range(0,24):
		for stack in 2: RewardServer.addReward(RewardServer.reward_list[str(id)].instantiate())
	await wait(0.2); snap("reward-hud")
	for reward in Utils.player.reward_root.get_children():
		var ui = Utils.canvasLayer.find_children(str(reward.id),"TextureRect",true,false).filter(func(n): return n.get_script()==load("res://ui/widgets/RewardTopItem.gd"))
		check(not ui.is_empty(),"persistent reward HUD "+str(reward.id))
		if not ui.is_empty(): check(ui[0].get_node("Label").text==str(reward.count),"HUD stack "+str(reward.id))
	RewardServer.reward_shop_list = ["12","17","23"]
	var choose = load("res://ui/widgets/RewardChoose.tscn").instantiate(); Utils.canvasLayer.add_child(choose)
	await get_tree().create_timer(0.3,true).timeout; choose.onMouseIn(choose.list.get_child(0).ins.reward_info)
	await get_tree().create_timer(0.1,true).timeout
	check(not choose.info_label.text.is_empty(),"new reward detail is visible before capture")
	snap("reward-choices"); choose.queue_free(); await wait(0.2)
	LevelServer.town.depart(10,true); LevelServer.timerStop()
	await wait(0.2)
	var rewards = Utils.canvasLayer.get_node("GameUI/RwGridContainer")
	var boss_huds = Utils.canvasLayer.get_children().filter(func(n): return n.get_script()==load("res://ui/BossHUD.gd"))
	check(not boss_huds[0].get_global_rect().intersects(rewards.get_global_rect()),"Boss HUD does not cover 22 rewards")
	snap("boss-hud-with-rewards")
	LevelServer.return_to_camp(); await wait(0.2); dismiss(); await wait(0.1)
	play_view.size = Vector2i(960,720)
	var camera = Camera2D.new(); play_view.add_child(camera); camera.make_current()
	for stage in [10,20,30]:
		LevelServer.town.depart(stage,true); LevelServer.timerStop()
		var boss = instance_from_id(LevelServer.boss_instance)
		boss.set_physics_process(false); boss.phase_two = true; boss.ultimate_cooldown = 0
		Utils.player.set_physics_process(false)
		boss.global_position = Utils.player.global_position+Vector2(60,0)
		camera.global_position = Utils.player.global_position
		check(Demo.pause_stack.is_empty() and not is_instance_valid(Demo.ui),"ultimate capture has no camp overlay "+str(stage))
		boss.choose_attack(); await wait(0.6); snap("ultimate-warning-"+str(stage))
		await wait(1.1); snap("ultimate-active-"+str(stage))
		LevelServer.return_to_camp(); await wait(0.3); dismiss(); await wait(0.1)
	print("M10_VISUAL_CHECKS ",checks," FAILURES ",failures)
	await Demo.quit_game()
