extends "res://tests/M3Weapons.gd"
func _ready():
	Demo.test_mode = true
	var view = SubViewport.new(); view.size = Vector2i(410,230); view.world_2d = get_viewport().world_2d; view.render_target_update_mode = SubViewport.UPDATE_ALWAYS; add_child(view)
	view.add_child(load("res://game/map/Main.tscn").instantiate()); Utils.gameStart(); await wait(0.3)
	PlayerData.gold = 100000
	Utils.player.set_process(false); Utils.player.set_physics_process(false)
	for id in [3,7,118,116,124]: Demo.try_purchase("weapon",str(id))
	LevelServer.town.depart(6,true); LevelServer.timerStop()
	for camera in get_tree().get_nodes_in_group("camera"):
		camera.enabled = false
	var capture_camera = Camera2D.new(); view.add_child(capture_camera); capture_camera.global_position = Utils.player.global_position; capture_camera.make_current()
	await wait(1.0)
	for id in [3,7,118,116,124]:
		var gun = PlayerData.player_weapon_list[id]; Utils.player.changeWeapon(id); gun.set_process(false); gun.cancel_actions()
		LevelServer.state = "COMBAT"
		var point = LevelServer.town.spawn_near(Utils.player.global_position,50,80)
		for attempt in 30:
			if Combat.clear_line(Utils.player.global_position,point): break
			point = LevelServer.town.spawn_near(Utils.player.global_position,50,80)
		var target = enemy(point,10000)
		var warning = load("res://game/monster/HostileZone.gd").new(); warning.damage=0; warning.warning=5; warning.radius=30; warning.position=point; add_child(warning)
		await wait(0.3)
		var motion=InputEventMouseMotion.new(); motion.position=view.get_canvas_transform()*(point-Vector2(0,8)); view.push_input(motion,true)
		gun.look_at(point-Vector2(0,8)); gun.direction=gun.gun_tip.global_position.direction_to(point-Vector2(0,8)); gun._shoot(); await wait(0.025); await RenderingServer.frame_post_draw
		print("CAPTURE player=",Utils.player.global_position," camera=",capture_camera.global_position," target=",point)
		var picture=view.get_texture().get_image(); picture.resize(1366,768,Image.INTERPOLATE_NEAREST); picture.save_png("res://docs/iteration/evidence/m7/visual-verified-tier-"+str(WeaponCatalog.tier(id))+".png")
		print("VISUAL tier=",WeaponCatalog.tier(id)," draw_calls=",Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
		gun.cancel_actions(); await clean()
	await Demo.quit_game()
