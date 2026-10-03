extends "res://tests/M8Runtime.gd"

func _ready():
	await boot()
	dismiss()
	configure(0)
	var ui = Utils.canvasLayer.get_node("GameUI")
	var controls = Utils.canvasLayer
	var flash = controls.hit_flash
	var original_flash_setting: bool = Combat.reduced_flash
	check(controls.world_effects.layer < controls.layer,"hit distortion is drawn below the combat HUD")
	check(controls.world_effects.layer < LevelServer.town.get_node("CanvasLayer").layer,"stage and timer are above hit postprocessing")
	check(controls.layer > LevelServer.town.get_node("CanvasLayer").layer,"camp and recovery dialogs cover map readouts")
	check(ui.hp_trail.size.y <= ui.hp_bar.size.y,"damage trail stays within the HP track")
	check(ui.reload_bar.size.y <= 3,"reload feedback remains a fine track")
	Combat.reduced_flash = false
	PlayerData.player_hp = 3.875
	check(is_equal_approx(ui.hp_bar.value,3.875),"fractional HP reaches the HUD without Range snapping")
	check(ui.hp_text.text == "3.88 / 5","HUD exposes current and maximum HP")
	check(ui.hp_trail.value > ui.hp_bar.value,"damage trail preserves the recent loss while real HP updates immediately")
	await wait(0.6)
	check(is_equal_approx(ui.hp_trail.value,3.875),"damage trail settles to real HP")
	PlayerData.player_hp = 2.0
	PlayerData.player_hp = 3.0
	check(ui.hp_trail.value == 3.0,"healing cancels a pending damage trail immediately")
	PlayerData.player_hp = 0.001
	check(ui.hp_text.text == "0.01 / 5","positive fractional HP never displays zero")
	PlayerData.player_hp = 5.0
	Combat.reduced_flash = true
	PlayerData.player_hp = 4.0
	check(ui.hp_trail.value == 4.0,"reduced flash uses immediate HP feedback")
	Combat.reduced_flash = false

	var gun = Utils.player.gun
	gun.bullets_count -= 1
	gun.reload_ammo()
	ui._update_weapon_readout()
	check(ui.reload_bar.visible and ui.current_weapon_label.text.contains("装填"),"actual reload is visible with a time readout")
	await wait(0.18)
	ui._update_weapon_readout()
	check(ui.reload_bar.value > 0 and ui.reload_bar.value < 1,"reload track advances from the weapon timer")
	var remaining: float = gun.change_timer.time_left
	get_tree().paused = true
	await wait(0.2)
	check(is_equal_approx(remaining,gun.change_timer.time_left),"pausing freezes the source reload timer")
	get_tree().paused = false
	gun.cancel_actions()
	ui._update_weapon_readout()
	check(not ui.reload_bar.visible and not ui.current_weapon_label.text.contains("装填"),"cancelled reload cannot leave stale progress")
	gun.bullets_count = 0
	PlayerData.reserve_magazines = 0
	ui._update_weapon_readout()
	check(ui.current_weapon_label.text.contains("弹药耗尽"),"empty gun with no reserves explains why reload is unavailable")
	PlayerData.reserve_magazines = 5
	gun.reload_ammo()
	Demo.try_purchase("weapon","1")
	Utils.player.changeWeapon(1)
	ui._update_weapon_readout()
	check(not ui.reload_bar.visible,"switching guns retires the old reload readout")

	controls.hit()
	var previous_tween: Tween = controls.hit_tween
	await wait(0.1)
	controls.hit()
	check(not previous_tween.is_valid(),"another hit replaces the previous flash tween")
	await wait(0.12)
	check(flash.visible,"the older flash cannot hide a newer hit")
	await wait(0.15)
	check(not flash.visible,"the final hit flash retires")
	var authored = load("res://ui/ControlUI.tscn").instantiate()
	check(flash.material != authored.get_node("Sprite2D").material,"hit material is isolated from other scene instances")
	authored.free()
	Combat.reduced_flash = true
	controls.hit()
	check(not flash.visible,"reduced flash suppresses screen distortion")
	Combat.reduced_flash = original_flash_setting

	check(LevelServer.town.depart(1,false),"dash cleanup is tested across a real combat departure")
	await wait(0.05)
	LevelServer.timerStop()
	Utils.player.showDash()
	await get_tree().process_frame
	check(not get_tree().get_nodes_in_group("combat_transient").is_empty(),"dash ghosts participate in combat cleanup")
	LevelServer.return_to_camp()
	dismiss()
	await wait(0.05)
	check(get_tree().get_nodes_in_group("combat_transient").is_empty(),"returning to camp removes dash ghosts immediately")

	var rng_gun = Utils.weapon_list["6"].instantiate()
	add_child(rng_gun)
	seed(206104)
	var expected_rng: Array = []
	for i in 6: expected_rng.append(randi())
	seed(206104)
	var prepared = Warmup.build_w6_canvas(rng_gun)
	add_child(prepared)
	var observed_rng: Array = []
	for i in 6: observed_rng.append(randi())
	check(observed_rng == expected_rng,"W6 preparation consumes no gameplay RNG")
	check(prepared.find_children("*","CPUParticles2D",true,false).is_empty() and prepared.find_children("*","MultiMeshInstance2D",true,false).size() == 2,"W6 preparation uses inert renderer draws without particle constructors")
	prepared.queue_free()
	rng_gun.queue_free()
	for id in RewardServer.reward_list:
		var reward = RewardServer.reward_list[id].instantiate()
		if reward.only_start: reward.free()
		else: RewardServer.addReward(reward)
	await wait(0.1)
	check(ui.rw_grid.columns == ui.rw_grid.get_child_count() and ui.rw_grid.size.y <= 12,"full reward build stays in one bounded strip")
	check(ui.rw_grid.get_global_rect().size.x <= 281 and ui.rw_grid.position.y >= 185,"full reward build leaves top and central threats clear")
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--capture-readability="):
			var output = arg.trim_prefix("--capture-readability=")
			DirAccess.make_dir_recursive_absolute(output)
			LevelServer.town.depart(40,true)
			await wait(0.25)
			LevelServer.timerStop()
			check(is_instance_valid(LevelServer.get_boss()),"readability capture contains a real stage-40 boss")
			get_tree().paused = true
			await RenderingServer.frame_post_draw
			play_view.get_texture().get_image().save_png(output+"/full-boss.png")
			controls.hit()
			controls.hit_tween.pause()
			flash.material.set_shader_parameter("fade",0.01)
			check(flash.visible,"readability capture uses the production hit shader at its peak")
			await RenderingServer.frame_post_draw
			play_view.get_texture().get_image().save_png(output+"/full-boss-hit.png")
			get_tree().paused = false
	print("COMBAT_READABILITY checks=",checks," failures=",failures)
	if failures: get_tree().quit(1)
	else: await Demo.quit_game()
