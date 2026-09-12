extends "res://tests/M3Weapons.gd"
func _ready():
	Demo.test_mode = true
	var main = load("res://game/map/Main.tscn").instantiate()
	add_child(main)
	Utils.gameStart(); PlayerData.gold = 100000; PlayerData.reward_point = 9999
	await wait(0.2)
	Utils.player.global_position = origin-Vector2(100,0)
	for id in Utils.weapon_list: Demo.try_purchase("weapon",id)
	check(Utils.weapon_list.size() == 24 and Utils.am_dict.size() == 24,"actual 24 weapons and 24 attachment definitions")
	var compatibility = {}
	for id in Utils.am_dict:
		var result = Demo.try_purchase("attachment",id)
		check(result.success,"attachment purchase "+id)
		var am = PlayerData.player_am_list[result.instance_id]
		var yes = []
		var no = []
		for gun in PlayerData.player_weapon_list.values():
			if am.can_equip(gun): yes.append(gun)
			else: no.append(gun)
		check(not yes.is_empty(),"attachment has real compatible weapon "+id)
		var gun = yes[0]
		var before = gun.effective.duplicate(true)
		var drift = false
		for cycle in 20:
			if not gun.addAttachMent(am): drift = true
			gun.removeAttachMent(am)
			if gun.effective != before: drift = true
		check(not drift,"20 equip/unequip cycles no drift "+id)
		if not no.is_empty():
			var old = no[0].effective.duplicate(true)
			check(not no[0].addAttachMent(am) and am.gun == null and no[0].effective == old,"incompatible rejected unchanged "+id)
		else:
			var unsupported = BaseGun.new()
			unsupported.tags = []
			unsupported.weapon_type = "UNSUPPORTED"
			unsupported.damage = 0
			unsupported.bullets_max_count = 0
			check(not am.can_equip(unsupported),"universal across roster; unsupported definition rejected "+id)
			unsupported.free()
		compatibility[id] = {"compatible":yes.size(),"incompatible":no.size(),"cycles":20}
		if AttachmentCatalog.DEFINITIONS.has(int(id)):
			gun.addAttachMent(am)
			check(gun.effective != before,"real effective stats change "+id)
			gun.removeAttachMent(am)
	# Same model distinct instances, same-slot replacement and two gun ownership.
	var one = Demo.try_purchase("attachment","1")
	var two = Demo.try_purchase("attachment","1")
	var a = PlayerData.player_am_list[one.instance_id]
	var b = PlayerData.player_am_list[two.instance_id]
	var gun = PlayerData.player_weapon_list[0]
	gun.addAttachMent(a); gun.addAttachMent(b)
	check(a.gun == null and b.gun == gun and a.id != b.id,"same slot returns exact instance")
	PlayerData.player_weapon_list[4].addAttachMent(a)
	check(a.gun != b.gun,"same model on two different guns")
	var schema = Demo.snapshot()
	check(Demo.valid_save(schema),"complete multi-attachment schema valid")
	Demo.save_path = "user://m4-attachments-test.json"
	check(Demo.save_store.save(Demo.save_path,schema).success and Demo.load_camp(),"new schema real save restore")
	check(PlayerData.player_am_list.size() == 26,"all distinct instances restored")
	LevelServer.state = "COMBAT"
	var rail = PlayerData.player_weapon_list[113]
	aim(rail)
	var pierced = []
	for i in 7: pierced.append(enemy(origin+Vector2(30+i*24,8)))
	await wait(0.06)
	var core = PlayerData.player_am_list.values().filter(func(am): return am.am_id == 118)[0]
	rail.addAttachMent(core)
	rail._shoot()
	check(pierced.all(func(t): return t.HP < 100),"A18 actual rail seventh target")
	await clean()
	var prism = PlayerData.player_weapon_list[111]
	aim(prism)
	var lens = PlayerData.player_am_list.values().filter(func(am): return am.am_id == 111)[0]
	var distant = enemy(origin+Vector2(320,8))
	await wait(0.06)
	prism._shoot()
	check(distant.HP == 100,"A11 range baseline misses distant target")
	prism.addAttachMent(lens)
	prism._shoot()
	check(distant.HP < 100,"A11 actual extended beam hit")
	await clean()
	var cone = PlayerData.player_weapon_list[115]
	aim(cone)
	var diffuser = PlayerData.player_am_list.values().filter(func(am): return am.am_id == 113)[0]
	var edge = enemy(origin+Vector2(70,0).rotated(0.8)+Vector2(0,8))
	await wait(0.06)
	cone._shoot()
	check(edge.HP == 100,"A13 base cone excludes edge")
	cone.addAttachMent(diffuser)
	cone._shoot()
	check(edge.HP < 100 and is_equal_approx(cone.effective.damage,(cone.base_stats.damage+PlayerData.player_damage)*WeaponCatalog.power(cone.weapon_id)*1.1),"A13 wider actual cone with universal damage buff")
	await clean()
	gun = PlayerData.player_weapon_list[0]
	aim(gun)
	var shardmod = PlayerData.player_am_list.values().filter(func(am): return am.am_id == 120)[0]
	gun.addAttachMent(shardmod)
	var first = enemy(origin+Vector2(35,8))
	var next = enemy(origin+Vector2(65,8))
	await wait(0.06)
	var bullet = gun.bullet_scene.instantiate()
	add_child(bullet)
	bullet.global_position = origin
	bullet.rotation = 0
	gun.fire(bullet)
	await wait(0.3)
	check(first.HP < 100 and next.HP < 100 and next.last_context.depth == 1,"A20 actual ordinary projectile fragments")
	await clean()
	var refill = PlayerData.player_am_list.values().filter(func(am): return am.am_id == 124)[0]
	gun.addAttachMent(refill)
	gun.bullets_count = 1
	var victim = enemy(origin+Vector2(25,8),0.1)
	await wait(0.06)
	bullet = gun.bullet_scene.instantiate(); add_child(bullet); bullet.position = origin; bullet.rotation = 0; gun.fire(bullet)
	await wait(0.15)
	check(gun.bullets_count == 1,"A24 real direct kill refills one")
	var count = gun.bullets_count
	var derived = enemy(origin+Vector2(65,8),0.1)
	var context = gun.damage_context(1)
	Combat.hit(derived,context)
	check(gun.bullets_count == count,"A24 derived kill cannot refill")
	await clean()
	await wait(1.0)
	print("M4 COMPATIBILITY ",JSON.stringify(compatibility))
	print("M4 ATTACHMENTS SUMMARY checks=",checks," failures=",failures)
	get_tree().quit.call_deferred(1 if failures else 0)
