extends "res://tests/M3Weapons.gd"
var rows = []
var output = "baseline"
var actors: Node2D
func write_rows():
	var f = FileAccess.open("res://docs/iteration/evidence/m8/"+output+".json",FileAccess.WRITE)
	f.store_string(JSON.stringify(rows,"\t")); f.close()
func _ready():
	Demo.test_mode = true; seed(808)
	var view = SubViewport.new(); view.size = Vector2i(1536,864); view.world_2d = get_viewport().world_2d; view.render_target_update_mode = SubViewport.UPDATE_DISABLED; add_child(view)
	view.add_child(load("res://game/map/Main.tscn").instantiate()); Utils.gameStart(); await wait(0.3)
	actors = Node2D.new(); add_child(actors)
	Utils.player.set_process(false); Utils.player.set_physics_process(false)
	Utils.player.global_position = origin
	if "damage" in OS.get_cmdline_user_args(): await damage_audit()
	else: await behavior_audit()
	LevelServer.state = "CAMP"
	print("M8 BASELINE SUMMARY checks=",checks," failures=",failures)
	await Demo.quit_game()
func behavior_audit():
	output = "baseline-behavior"
	if "revised" in OS.get_cmdline_user_args(): output = "revised-behavior"
	for id in M5Content.ENEMIES.keys()+M5Content.BOSSES.keys():
		LevelServer.state = "COMBAT"; PlayerData.player_hp_max = 500; PlayerData.player_hp = 500
		Utils.player.global_position = origin
		var actor = M5Content.spawn(id,actors,origin+Vector2(160,0))
		var previous = actor.global_position
		var result = {"id":id,"seconds":0.0,"moving":0.0,"pursuing":0.0,"cooldown_moving":0.0,"travel":0.0,"near_response":0.0,"damage":0.0,"samples":[]}
		for step in 80:
			await wait(0.2)
			if not is_instance_valid(actor) or actor.is_die: break
			var displacement = actor.global_position-previous
			var distance = actor.global_position.distance_to(Utils.player.global_position)
			result.seconds += 0.2; result.travel += displacement.length()
			if displacement.length()>1:
				result.moving += 0.2
				if displacement.dot(previous.direction_to(Utils.player.global_position))>0.5: result.pursuing += 0.2
				if actor.get("phase") == "recover": result.cooldown_moving += 0.2
			if step == 40: Utils.player.global_position = actor.global_position+Vector2(25,0)
			if step > 40: result.near_response += displacement.length()
			if step%5 == 0: result.samples.append({"s":step*0.2,"distance":distance,"phase":actor.get("phase")})
			previous = actor.global_position
		result.damage = 500-PlayerData.player_hp
		result.actions = actor.actions.duplicate() if is_instance_valid(actor) and actor.get("actions") != null else {}
		rows.append(result); print("BEHAVIOR ",JSON.stringify(result)); write_rows()
		await clean()
func damage_audit():
	output = "baseline-damage"
	PlayerData.gold = 100000; PlayerData.reward_point = 9999
	for id in [113,119,120,121,124]: Demo.try_purchase("weapon",str(id))
	for id in Utils.am_dict: Demo.try_purchase("attachment",id)
	for talent in DemoConfig.TALENTS:
		for rank in DemoConfig.TALENTS[talent].max: Demo.try_purchase("talent",talent,"points")
	for gun_id in [113,119,120,121,124]:
		var gun = PlayerData.player_weapon_list[gun_id]
		for am in PlayerData.player_am_list.values(): gun.addAttachMent(am)
		for boss_id in M5Content.BOSSES:
			LevelServer.state = "COMBAT"; PlayerData.player_hp = PlayerData.player_hp_max
			aim(gun); gun.set_physics_process(false)
			var actor = load("res://game/monster/Monster 2/Monster2.tscn").instantiate()
			actor.set_script(load("res://tests/M8DamageProbe.gd")); actor.role = boss_id
			actor.position = origin+Vector2(50,8); add_child(actor); actor.set_physics_process(false)
			await wait(0.08)
			var shots = 0; var start = Time.get_ticks_msec()
			while not actor.is_die and Time.get_ticks_msec()-start < 30000:
				if gun_id == 124: gun.drive_spin(true,0.01)
				if gun.bullets_count == 0: gun.reload_ammo()
				if gun.can_shoot and not gun.is_reloading:
					if gun_id == 113:
						await wait(gun.effective.warmup); gun.charge_time = gun.effective.warmup
					gun.gun_tip.global_position = origin; gun.direction = Vector2.RIGHT
					shots += 1; actor.volley = shots; gun._shoot(); gun.can_shoot = false; gun.timer.start()
				await wait(0.01)
			var result = {"boss":boss_id,"gun":gun_id,"hp":actor.max_hp,"armor":M5Content.definition(boss_id).get("armor",0),"effective":gun.effective.duplicate(true),"equipped":gun.attachments_dict.values().map(func(am): return am.am_id),"seconds":(Time.get_ticks_msec()-start)/1000.0,"shots":shots,"killed":actor.is_die,"trace":actor.damage_trace.duplicate(true)}
			rows.append(result); print("DAMAGE ",JSON.stringify(result)); write_rows()
			gun.cancel_actions(); await clean()
			LevelServer.state = "CAMP"
