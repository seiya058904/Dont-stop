extends "res://tests/M8Runtime.gd"
func _ready():
	await boot()
	Demo.save_path = "res://evidence/m8-globals.json"
	Demo.try_purchase("weapon","0")
	for id in Utils.am_dict:
		var gold = PlayerData.gold
		Demo.test_mode = false
		var result = Demo.try_purchase("attachment",id)
		check(result.success and result.saved,"first activation saved "+id)
		var paid = PlayerData.gold
		check(paid == gold-result.charged_amount,"exact purchase debit "+id)
		for click in 3: check(not Demo.try_purchase("attachment",id).success and PlayerData.gold == paid,"repeat purchase no debit "+id)
		check(Demo.load_camp() and id in Demo.owned_global_upgrades,"disk restore activation "+id)
		check(not Demo.try_purchase("attachment",id).success and PlayerData.gold == paid,"reload no duplicate purchase "+id)
		check(PlayerData.player_am_list.is_empty() and not Demo.snapshot().has("attachments"),"no runtime instance "+id)
		Demo.test_mode = true
	var all = Demo.owned_global_upgrades.duplicate()
	check(all.size()==24,"24 unique owned states")
	for id in Utils.weapon_list: Demo.try_purchase("weapon",id)
	for gun in PlayerData.player_weapon_list.values():
		check(gun.effective == EffectiveStats.calculate(gun) and gun.attachments_dict.is_empty(),"future/current gun gets full global build "+str(gun.weapon_id))
	var snap = Demo.snapshot()
	for version in range(1,6):
		var old = snap.duplicate(true); old.schema_version = version
		old.erase("owned_global_upgrades"); old.attachments = []; old.next_instance = 73
		var index = 1
		for id in Utils.am_dict:
			for duplicate in 3:
				old.attachments.append({"definition":str(id),"instance":index,"gun":"0" if index==1 else ""}); index += 1
		# Historical loaded ammo was not full-global capacity. Empty is legal in every schema.
		for weapon in old.weapons: weapon.ammo = 0
		if version<5: old.ammo = 251; old.erase("reserve_magazines")
		check(Demo.valid_save(old),"valid genuine legacy shape schema "+str(version))
		check(Demo.save_store.save(Demo.save_path,old).success,"legacy written "+str(version))
		Demo.test_mode = false
		check(Demo.load_camp(),"legacy disk migration "+str(version))
		Demo.test_mode = true
		var migrated = Demo.snapshot()
		check(migrated.owned_global_upgrades == all and not migrated.has("attachments") and migrated.gold == snap.gold,"duplicates collapse without refund "+str(version))
		check(JSON.parse_string(FileAccess.get_file_as_string(Demo.save_path)).schema_version==6,"migration persists new schema "+str(version))
		for repeat in 2: check(Demo.load_camp() and Demo.snapshot()==migrated,"migration idempotent "+str(version))
	for invalid in [["0","0"],["no-such-upgrade"],[0],null]:
		var bad = Demo.snapshot(); bad.owned_global_upgrades = invalid
		check(not Demo.valid_save(bad),"invalid global ownership rejected "+str(invalid))
	# 576 pairs: real property calculation AND real engine firing against collision bodies.
	var pair_rows = []
	Utils.player.global_position = origin-Vector2(100,0)
	for id in Utils.am_dict:
		Demo.owned_global_upgrades = [str(id)]; Demo.refresh()
		for gun in PlayerData.player_weapon_list.values():
			aim(gun); gun.set_physics_process(false)
			LevelServer.state = "COMBAT"
			var target = enemy(origin+Vector2(45,8),100000)
			var next = enemy(origin+Vector2(75,12),100000)
			await wait(0.04)
			var motion = InputEventMouseMotion.new(); motion.position = play_view.get_canvas_transform()*(origin+Vector2(100,0)); play_view.push_input(motion,true)
			if gun.weapon_id == 6:
				gun.cast.global_position = origin; gun.cast.global_rotation = 0; gun.set_physics_process(true)
			var stats = gun.effective.duplicate(true)
			check(stats == EffectiveStats.calculate(gun) and stats.damage>0 and stats.magazine>0,"pair effective "+id+"/"+str(gun.weapon_id))
			gun._shoot()
			await wait(1.5 if gun.weapon_id == 121 else 0.4)
			var actual = 200000-target.HP-next.HP
			check(actual>0,"pair runtime hit "+id+"/"+str(gun.weapon_id))
			pair_rows.append({"upgrade":id,"gun":gun.weapon_id,"damage":actual,"effective":stats})
			gun.cancel_actions(); await clean()
			LevelServer.state = "CAMP"
	Demo.owned_global_upgrades = all; Demo.refresh()
	check(pair_rows.size()==576,"576 real firing combinations")
	var f = FileAccess.open("res://docs/iteration/evidence/m8/global-combinations.json",FileAccess.WRITE); f.store_string(JSON.stringify(pair_rows,"\t")); f.close()
	print("M8 GLOBALS SUMMARY checks=",checks," failures=",failures)
	if failures: get_tree().quit(1)
	else: await Demo.quit_game()
