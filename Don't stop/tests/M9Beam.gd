extends "res://tests/M3Weapons.gd"

func _ready():
	Demo.test_mode = true
	seed(909)
	var main = load("res://game/map/Main.tscn").instantiate()
	add_child(main)
	Utils.gameStart()
	await wait(0.3)
	PlayerData.gold = 100000
	Utils.player.set_process(false)
	Utils.player.set_physics_process(false)
	Utils.player.global_position = origin-Vector2(100,0)
	LevelServer.state = "CAMP"
	Demo.try_purchase("weapon", "6")
	var gun = PlayerData.player_weapon_list[6]
	var camera = Camera2D.new(); add_child(camera); camera.make_current()
	var rows = []
	for distance in [100,250,500,750,950,1050]:
		for blocked in [false,true]:
			aim(gun)
			gun.global_position = origin
			gun.global_rotation = 0
			gun.recoil = 0
			gun.set_physics_process(true)
			LevelServer.state = "COMBAT"
			var start = gun.cast.global_position
			var target = enemy(start+Vector2(distance-1,9),100000)
			var barrier = wall(start+Vector2(600,0),Vector2(4,200)) if blocked else null
			await wait(0.08)
			gun._shoot()
			await wait(0.15)
			var ray_end = gun.cast.get_collision_point() if gun.cast.is_colliding() else gun.cast.to_global(gun.cast.target_position)
			var line_end = gun.line_2d.to_global(gun.line_2d.points[1])
			var row = {"distance":distance,"wall":blocked,"actual_hit":target.HP<100000,"ray_end":str(ray_end),"line_end":str(line_end),"endpoint_error":ray_end.distance_to(line_end),"particle_length_local":gun.particles_box.process_material.emission_box_extents.x*2,"end_particle":str(gun.particles_end.global_position),"range":gun.effective.range}
			rows.append(row)
			check(row.actual_hit == (distance <= 1000 and (not blocked or distance < 600)),"distance/wall damage " + str(distance) + "/" + str(blocked))
			check(row.endpoint_error < 0.1,"beam endpoint " + str(distance) + "/" + str(blocked))
			print("BEAM_RESULT ",JSON.stringify(row))
			gun.cancel_actions()
			if barrier: barrier.queue_free()
			await clean()
	# Exercise independent node transforms, both aim directions and moving origins.
	for angle in [0.0,0.7,PI,-1.2]:
		for zoom in [0.65,1.0,1.7]:
			camera.zoom = Vector2(zoom,zoom)
			aim(gun)
			gun.set_physics_process(false)
			gun.global_position = origin + Vector2(angle*23,zoom*17)
			gun.rotation = angle
			gun.scale = Vector2(zoom,zoom)
			gun.line_2d.position = Vector2(13,-7)
			gun.line_2d.rotation = 0.3
			gun.line_2d.scale = Vector2(0.8,1.2)
			gun.openFire()
			for frame in 6:
				camera.global_position = gun.global_position+Vector2(frame*10,-frame*3)
				gun.global_position += Vector2(3,-2)
				gun.rotation += 0.05
				gun._physics_process(1.0/60.0)
				var ray_end = gun.cast.get_collision_point() if gun.cast.is_colliding() else gun.cast.to_global(gun.cast.target_position)
				check(gun.line_2d.to_global(gun.line_2d.points[1]).distance_to(ray_end)<0.001,"transformed moving beam end")
				check(gun.line_2d.to_global(gun.line_2d.points[0]).distance_to(gun.cast.global_position)<0.001,"transformed moving beam start")
				check(gun.particles_end.global_position.distance_to(ray_end)<0.001,"transformed end particles")
				var screen_end = gun.line_2d.get_global_transform_with_canvas()*gun.line_2d.points[1]
				check(screen_end.distance_to(get_viewport().get_canvas_transform()*ray_end)<0.002,"camera pan and zoom preserve projected endpoint")
				await get_tree().physics_frame
			gun.cancel_actions()
	DirAccess.make_dir_recursive_absolute("res://docs/iteration/evidence/m9")
	var file = FileAccess.open("res://docs/iteration/evidence/m9/beam-final.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(rows,"\t"))
	file.close()
	print("M9_BEAM_CHECKS ",checks," FAILURES ",failures)
	if failures: get_tree().quit(1); return
	await Demo.quit_game()
