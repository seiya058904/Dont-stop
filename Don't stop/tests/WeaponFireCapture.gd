extends "res://tests/M8Runtime.gd"

# Native rendered observation fixture; two identical lanes, with/without a real wall.
# All shots run production weapon code. Test targets have high HP to survive captures.
func _ready():
	await boot()
	Combat.reduced_flash = OS.get_environment("PRESENTATION_REDUCED_FLASH") == "1"
	dismiss()
	Utils.player.set_process(false)
	Utils.player.set_physics_process(false)
	Utils.player.global_position = origin
	var observer = Camera2D.new()
	play_view.add_child(observer)
	observer.global_position = origin+Vector2(60,0)
	observer.make_current()
	var output = OS.get_environment("PRESENTATION_OUTPUT")
	if output.is_empty(): get_tree().quit(2); return
	DirAccess.make_dir_recursive_absolute(output)
	var results: Array = []
	var requested = OS.get_environment("PRESENTATION_WEAPONS").split(",",false)
	for key in Utils.weapon_list:
		if not requested.is_empty() and not str(key) in requested: continue
		var id = int(key)
		for blocked in [false,true]:
			configure(id,false)
			LevelServer.state = "COMBAT"
			var gun = Utils.player.gun
			Utils.player.setGunLookat(origin+Vector2(200,0))
			gun.rotation = 0
			gun.direction = Vector2.RIGHT
			var target = enemy(origin+Vector2(65,8),100000)
			target.knockback_def = 100000
			var barrier = wall(origin+Vector2(45,0),Vector2(4,100)) if blocked else null
			if barrier:
				var face = Polygon2D.new()
				face.color = Color("89969e")
				face.polygon = PackedVector2Array([Vector2(-2,-50),Vector2(2,-50),Vector2(2,50),Vector2(-2,50)])
				barrier.add_child(face)
			await wait(0.1)
			# Same aim hook as B12WeaponBench: some guns re-read the root mouse in
			# _shoot(), so a frozen native observation camera alone cannot aim them.
			Utils.aim_override = get_viewport().get_canvas_transform()*(target.global_position-Vector2(0,8))
			var ammo_before = gun.bullets_count
			if id == 113: gun.charge_time = gun.effective.warmup
			gun._shoot()
			if id == 6: gun.set_physics_process(true)
			var elapsed = 0.0
			for moment in [0.02,0.08,0.2,0.6,1.1,1.6]:
				await wait(moment-elapsed)
				elapsed = moment
				RenderingServer.force_draw(false)
				await RenderingServer.frame_post_draw
				play_view.get_texture().get_image().save_png(output+"/fire-%d-%s-%03d.png" % [id,"wall" if blocked else "target",roundi(moment*100)])
			results.append({"weapon":id,"wall":blocked,"target_hp":target.HP,"ammo_before":ammo_before,"ammo_after":gun.bullets_count,"muzzle":str(gun.gun_tip.global_position),"anchor":str(gun.resting_position)})
			check(target.HP == 100000 if blocked else target.HP < 100000,"observed target outcome %d wall=%s" % [id,str(blocked)])
			gun.cancel_actions()
			gun.set_physics_process(false)
			if barrier: barrier.queue_free()
			await clean()
		print("WEAPON_FIRE_CAPTURE ",id," target and wall")
	var record = FileAccess.open(output+"/events.json",FileAccess.WRITE)
	record.store_string(JSON.stringify(results,"\t"))
	record.close()
	Utils.aim_override = null
	print("WEAPON_FIRE_CHECKS=",checks," FAILURES=",failures)
	if failures: get_tree().quit(1)
	else: await Demo.quit_game()
