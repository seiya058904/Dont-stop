extends "res://tests/M8Runtime.gd"

func _ready():
	await boot(); dismiss()
	var observer = Camera2D.new(); play_view.add_child(observer)
	var output = "res://evidence/visual-upgrade-20260919/b15-visual"
	for arg in OS.get_cmdline_user_args():
		if arg=="--final": output+="-final"
	DirAccess.make_dir_recursive_absolute(output)
	for id in [112,116,113,120,118,121,122,114]:
		await clean(); configure(id)
		LevelServer.timer.stop(); LevelServer.state = "COMBAT"
		var gun = Utils.player.gun
		Utils.player.set_physics_process(false); Utils.player.set_process(false)
		origin = Utils.player.global_position+Vector2(0,-8)
		observer.global_position = origin+Vector2(65,0); observer.make_current()
		gun.look_at(origin+Vector2(200,0)); gun.direction = Vector2.RIGHT
		for i in 12:
			var target = enemy(origin+Vector2(45+(i%4)*28,-30+(i/4)*26),25)
			target.set_physics_process(true)
		await wait(0.15)
		for frame in 18:
			if id==116: gun.handle_thermal(true,0.06)
			elif frame in [0,6,12]:
				if id==113: gun.charge_time=gun.effective.warmup
				gun._shoot()
			await wait(0.06)
			RenderingServer.force_draw(false)
			await RenderingServer.frame_post_draw
			play_view.get_texture().get_image().save_png(output+"/%d-%02d.png" % [id,frame])
		gun.cancel_actions()
		print("B15_VISUAL captured ",id)
	await clean(); get_tree().quit()
