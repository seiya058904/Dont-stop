extends "res://tests/M8Runtime.gd"

# Render-only fixture. Uses real owned gun scenes and the real hero aim/flip path.
# Never changes a gun's anchor, muzzle, texture, camera zoom or combat parameters.
func _ready():
	await boot()
	dismiss()
	Utils.player.set_process(false)
	Utils.player.set_physics_process(false)
	# A fixed observer camera avoids OS-cursor-driven camera drift between runs.
	# It keeps the project's 410x230 scale at zoom 1; only this test owns it.
	var observer = Camera2D.new()
	play_view.add_child(observer)
	observer.global_position = Utils.player.global_position
	observer.make_current()
	var output = OS.get_environment("PRESENTATION_OUTPUT")
	if output.is_empty():
		push_error("PRESENTATION_OUTPUT must identify an evidence directory")
		get_tree().quit(2)
		return
	DirAccess.make_dir_recursive_absolute(output)
	var rows: Array = []
	for key in Utils.weapon_list:
		var id = int(key)
		configure(id,false)
		var gun = Utils.player.gun
		gun.cancel_actions()
		gun.image.get_image().save_png(output+"/body-"+str(id)+".png")
		for direction_index in 8:
			var aim_point = Utils.player.global_position+Vector2.RIGHT.rotated(direction_index*PI/4.0)*100
			Utils.player.setGunLookat(aim_point)
			gun.look_at(aim_point)
			gun.direction = gun.gun_tip.global_position.direction_to(aim_point)
			await wait(0.06)
			RenderingServer.force_draw(false)
			await RenderingServer.frame_post_draw
			var capture = play_view.get_texture().get_image()
			capture.save_png(output+"/held-"+str(id)+"-"+str(direction_index)+".png")
			capture.get_region(Rect2i(173,83,64,64)).save_png(output+"/detail-"+str(id)+"-"+str(direction_index)+".png")
			rows.append({"weapon":id,"direction":direction_index,"position":str(gun.position),"resting_position":str(gun.resting_position),"tip_local":str(gun.gun_tip.position),"sprite_scale":str(gun.gun_image.scale)})
		print("PRESENTATION_CAPTURE ",id," eight directions")
	var record = FileAccess.open(output+"/poses.json",FileAccess.WRITE)
	record.store_string(JSON.stringify(rows,"\t"))
	record.close()
	await Demo.quit_game()
