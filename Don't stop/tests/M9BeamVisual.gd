extends "res://tests/M8Runtime.gd"

func _ready():
	await boot(); configure(6)
	play_view.size = Vector2i(1366,768)
	Utils.player.set_process(false); Utils.player.set_physics_process(false)
	Utils.player.global_position = origin
	var camera = Camera2D.new(); play_view.add_child(camera)
	camera.global_position = origin+Vector2(480,0); camera.make_current()
	var gun = Utils.player.gun
	gun.global_position = origin
	gun.global_rotation = 0
	gun.direction = Vector2.RIGHT
	gun.set_process(false); gun.set_physics_process(true)
	var floor_node = Node2D.new(); play_view.add_child(floor_node)
	var floor_shape = Polygon2D.new(); floor_shape.polygon = PackedVector2Array([origin+Vector2(-200,-380),origin+Vector2(1200,-380),origin+Vector2(1200,380),origin+Vector2(-200,380)]); floor_shape.color = Color("253038"); floor_shape.z_index = -10; floor_node.add_child(floor_shape)
	for distance in [100,250,500,750,950,1050]:
		var label = Label.new(); label.text = str(distance)+" px"; label.global_position = origin+Vector2(distance,-65); label.add_theme_font_size_override("font_size",16); floor_node.add_child(label)
	for blocked in [false,true]:
		LevelServer.state = "COMBAT"
		var target = enemy(gun.cast.global_position+Vector2(949,9),100000)
		var barrier = wall(origin+Vector2(600,0),Vector2(4,200)) if blocked else null
		var wall_visual = Polygon2D.new()
		if not blocked: wall_visual.free()
		if blocked:
			wall_visual.polygon = PackedVector2Array([origin+Vector2(598,-100),origin+Vector2(602,-100),origin+Vector2(602,100),origin+Vector2(598,100)])
			wall_visual.color = Color("849da2"); floor_node.add_child(wall_visual)
		await wait(0.1)
		gun.openFire()
		await wait(0.23)
		RenderingServer.force_draw(false)
		await RenderingServer.frame_post_draw
		DirAccess.make_dir_recursive_absolute("res://docs/iteration/evidence/m8")
		var picture = play_view.get_texture().get_image()
		picture.save_png("res://docs/iteration/evidence/m8/m9-boomboi-"+("wall" if blocked else "open")+".png")
		print("M9_BEAM_VISUAL ",blocked," actual_hit=",target.HP<100000)
		gun.cancel_actions()
		if barrier: barrier.queue_free(); wall_visual.queue_free()
		await clean()
	await Demo.quit_game()
