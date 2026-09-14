extends "res://tests/M8Runtime.gd"

func _ready():
	await boot()
	play_view.size = Vector2i(960,540)
	Utils.player.set_process(false); Utils.player.set_physics_process(false)
	Utils.player.global_position = origin
	var camera = Camera2D.new(); play_view.add_child(camera); camera.global_position = origin+Vector2(80,0); camera.zoom = Vector2(2,2); camera.make_current()
	for key in Utils.weapon_list:
		var id = int(key)
		configure(id,false)
		LevelServer.state = "COMBAT"
		var gun = Utils.player.gun
		gun.global_position = origin
		gun.rotation = 0
		var distance = 60 if id in [115,116,121,122] else 160
		var target = enemy(origin+Vector2(distance,8),100000)
		target.knockback_def = 100000
		var barrier = wall(origin+Vector2(130,0),Vector2(4,80)) if id==117 else null
		if barrier:
			var wall_face = Polygon2D.new(); wall_face.color = Color("849da2")
			wall_face.polygon = PackedVector2Array([Vector2(-2,-40),Vector2(2,-40),Vector2(2,40),Vector2(-2,40)])
			barrier.add_child(wall_face)
		var motion = InputEventMouseMotion.new(); motion.position = play_view.get_canvas_transform()*(origin+Vector2(distance,0)); play_view.push_input(motion,true)
		gun.direction = Vector2.RIGHT
		if id==113: gun.charge_time = gun.effective.warmup
		await wait(0.08)
		gun._shoot()
		if id==6: gun.set_physics_process(true)
		await wait(0.08 if id in [111,112,113,115,116] else (0.65 if id==121 else 0.25))
		if id==117:
			for step in 60:
				var shots = get_tree().get_nodes_in_group("combat_transient").filter(func(n): return n is Bullet and n.get("remaining_bounces") != null)
				if shots.any(func(n): return n.remaining_bounces<gun.effective.bounces): break
				await get_tree().physics_frame
			await wait(0.05)
		RenderingServer.force_draw(false)
		await RenderingServer.frame_post_draw
		play_view.get_texture().get_image().save_png("res://docs/iteration/evidence/m8/m9-weapon-"+str(id)+".png")
		print("M9_WEAPON_VISUAL ",id)
		gun.cancel_actions()
		if barrier: barrier.queue_free()
		await clean()
	await Demo.quit_game()
