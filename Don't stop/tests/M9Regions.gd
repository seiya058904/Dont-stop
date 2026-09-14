extends "res://tests/M8Runtime.gd"

func _ready():
	await boot(); configure(124)
	play_view.size = Vector2i(960,720)
	Utils.player.set_process(false); Utils.player.set_physics_process(false)
	var camera = Camera2D.new(); play_view.add_child(camera); camera.make_current()
	for stage in [1,6,11,16,21,26]:
		LevelServer.return_to_camp(); dismiss(); await wait(0.2)
		check(LevelServer.town.depart(stage,true),"region depart "+str(stage))
		LevelServer.timerStop()
		await clean()
		var arena = LevelServer.town.arena
		camera.global_position = arena.global_position if is_instance_valid(arena) else Utils.player.global_position
		if is_instance_valid(arena):
			for rect in arena.obstacles:
				var query = PhysicsPointQueryParameters2D.new()
				query.position = arena.to_global(rect.get_center()); query.collision_mask = 2147483648
				check(not arena.get_world_2d().direct_space_state.intersect_point(query).is_empty(),"visible wall has solid collider")
		for i in 3:
			var zone = load("res://game/monster/HostileZone.gd").new()
			zone.mode = ["circle","cone","line"][i]; zone.position = camera.global_position+Vector2(-140+i*140,70); zone.radius = 45; zone.length = 85; zone.warning = 3; zone.damage = 0; play_view.add_child(zone)
		await wait(1.4)
		RenderingServer.force_draw(false)
		await RenderingServer.frame_post_draw
		var picture = play_view.get_texture().get_image()
		picture.save_png("res://docs/iteration/evidence/m8/m9-region-"+str(stage)+".png")
		print("M9_REGION ",stage)
	LevelServer.return_to_camp(); dismiss(); await wait(0.3)
	print("M9_REGIONS checks=",checks," failures=",failures)
	if failures: get_tree().quit(1)
	else: await Demo.quit_game()
