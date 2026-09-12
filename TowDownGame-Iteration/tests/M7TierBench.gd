extends "res://tests/M3Weapons.gd"
var sample_targets = []
var sample_started = 0
var burst_damage = []
var burst_seconds = 0.0
func _process(_delta):
	if sample_started > 0 and burst_damage.is_empty() and Time.get_ticks_msec()-sample_started >= 1000:
		burst_seconds = (Time.get_ticks_msec()-sample_started)/1000.0
		for target in sample_targets: burst_damage.append(100000-target.HP)
func _ready():
	Demo.test_mode = true; seed(707)
	var view = SubViewport.new(); view.size = Vector2i(1536,864); view.world_2d = get_viewport().world_2d; view.render_target_update_mode = SubViewport.UPDATE_DISABLED; add_child(view)
	var main = load("res://game/map/Main.tscn").instantiate(); view.add_child(main); Utils.gameStart(); await wait(0.3)
	PlayerData.gold = 100000
	Utils.player.global_position = origin-Vector2(100,0)
	for id in Utils.weapon_list: Demo.try_purchase("weapon",id)
	var rows = []
	for gun in PlayerData.player_weapon_list.values():
		for old in gun.attachments_dict.values().duplicate(): gun.removeAttachMent(old)
		aim(gun); gun.set_physics_process(true); PlayerData.reserve_magazines = 100
		LevelServer.state = "COMBAT"
		var targets = []
		for offset in [Vector2(50,8),Vector2(80,16),Vector2(90,-10)]:
			var target = enemy(origin+offset,100000); target.training = false; targets.append(target)
		await wait(0.08)
		var motion = InputEventMouseMotion.new(); motion.position = gun.get_global_transform_with_canvas()*gun.to_local(origin+Vector2(100,0)); gun.get_viewport().push_input(motion,true)
		var start = Time.get_ticks_msec(); var shots = 0
		sample_started = start; sample_targets = targets; burst_damage = []
		while Time.get_ticks_msec()-start < 6000:
			var elapsed = (Time.get_ticks_msec()-start)/1000.0
			motion.position = gun.get_viewport().get_canvas_transform()*(origin+Vector2(100,8)); gun.get_viewport().push_input(motion,true)
			gun.direction = (origin+Vector2(100,8)-gun.gun_tip.global_position).normalized()
			if gun.weapon_id == 124: gun.drive_spin(true,0.01)
			if gun.bullets_count <= 0: gun.reload_ammo()
			elif gun.can_shoot and not gun.is_reloading:
				if gun.weapon_id == 113:
					gun.charge_time = gun.effective.warmup
					await wait(gun.effective.warmup)
				gun._shoot(); shots += 1; gun.can_shoot = false; gun.timer.start()
			await wait(0.01)
		var actual_seconds = (Time.get_ticks_msec()-start)/1000.0
		sample_started = 0
		gun.cancel_actions(); await wait(1.5)
		var damage = []
		for target in targets: damage.append(100000-target.HP)
		var row = {"id":gun.weapon_id,"name":tr(gun.weapon_name),"tier":WeaponCatalog.tier(gun.weapon_id),"price":Utils.weapon_money_list[str(gun.weapon_id)],"effective":gun.effective,"target_damage":damage,"seconds":actual_seconds,"burst_damage":burst_damage,"burst_seconds":burst_seconds,"settle_seconds":1.5,"volleys":shots}
		rows.append(row); print("TIER RESULT ",JSON.stringify(row))
		await clean()
		var file = FileAccess.open("res://docs/iteration/evidence/m7/tier-measured.json",FileAccess.WRITE); file.store_string(JSON.stringify(rows,"\t")); file.close()
	await Demo.quit_game()
