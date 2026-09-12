extends "res://tests/M8Runtime.gd"
func _ready():
	await boot()
	Demo.try_purchase("attachment","124")
	for id in Utils.weapon_list: Demo.try_purchase("weapon",id)
	Utils.player.global_position = origin-Vector2(100,0)
	for gun in PlayerData.player_weapon_list.values():
		aim(gun); gun.set_physics_process(false)
		LevelServer.state = "COMBAT"
		var target = enemy(origin+Vector2(45,8),0.01)
		await wait(0.05)
		var motion = InputEventMouseMotion.new(); motion.position = play_view.get_canvas_transform()*(origin+Vector2(100,0)); play_view.push_input(motion,true)
		if gun.weapon_id == 6: gun.cast.global_position = origin; gun.cast.global_rotation = 0; gun.set_physics_process(true)
		gun.bullets_count = maxi(1,gun.bullets_max_count-2)
		PlayerData.reserve_magazines = 0 # Isolate kill refill from the prototype's empty-volley auto-reload.
		var before = gun.bullets_count; var kills = Combat.kill_events
		gun._shoot()
		await wait(1.6 if gun.weapon_id==121 else 0.7)
		check(Combat.kill_events==kills+1,"real direct kill exactly once "+str(gun.weapon_id))
		var spent = {1:3,3:3,5:4,8:5,123:3}.get(gun.weapon_id,1)
		check(gun.bullets_count==maxi(0,before-spent)+1,"global refill triggers after authored volley cost "+str(gun.weapon_id))
		gun.cancel_actions(); await clean(); LevelServer.state = "CAMP"
	# A derived kill must not refill, even while the global upgrade is owned.
	var gun = Utils.player.gun; gun.bullets_count = 1
	LevelServer.state = "COMBAT"
	var target = enemy(origin,0.01)
	Combat.hit(target,{"damage":1.0,"gun":gun,"refill":1,"depth":1,"epoch":LevelServer.epoch})
	check(gun.bullets_count==1,"derived kill cannot recursively refill")
	await clean(); LevelServer.return_to_camp(); dismiss(); await wait(1.0)
	print("M8 REFILL SUMMARY checks=",checks," failures=",failures)
	if failures: get_tree().quit(1)
	else: await Demo.quit_game()
