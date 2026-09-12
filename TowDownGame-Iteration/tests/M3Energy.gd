extends "res://tests/M3Weapons.gd"

func _ready():
	Demo.test_mode = true
	var main = load("res://game/map/Main.tscn").instantiate()
	add_child(main)
	Utils.gameStart()
	await wait(0.2)
	Utils.player.global_position = origin-Vector2(100,0)
	for id in [111,113,115,116]: Demo.try_purchase("weapon",str(id))
	LevelServer.state = "COMBAT"
	var rail = PlayerData.player_weapon_list[113]
	aim(rail)
	var targets = []
	for i in 7: targets.append(enemy(origin+Vector2(30+i*25,8)))
	await wait(0.06)
	rail.handle_charge(true,2.0)
	check(is_equal_approx(rail.charge_time,1.2),"charge capped at 1.2 seconds")
	var ammo = rail.bullets_count
	rail.handle_charge(false,0)
	check(rail.bullets_count == ammo-1 and not rail.charging,"release consumes once")
	check(targets.slice(0,6).all(func(t): return t.HP < 100) and targets[6].HP == 100,"rail max six distinct actual hits")
	check(is_equal_approx(100-targets[0].HP,rail.effective.damage*2.5),"full charge actual 2.5 multiplier")
	for stop in ["switch","pause","reload","death","camp"]:
		rail.can_shoot = true
		rail.handle_charge(true,0.7)
		ammo = rail.bullets_count
		match stop:
			"switch": Utils.player.changeWeapon(111)
			"pause": Demo.push_pause(self); Demo.pop_pause(self)
			"reload": rail.reload_ammo()
			"death": Utils.player.is_dead = true; Demo.stop_attacks(); Utils.player.is_dead = false
			"camp": LevelServer.return_to_camp()
		rail.handle_charge(false,0.0)
		check(not rail.charging and rail.bullets_count == ammo,"charge cancel "+stop)
		LevelServer.state = "COMBAT"
		aim(rail)
	await clean()
	aim(rail)
	var block = wall(origin+Vector2(65,0),Vector2(4,120))
	var behind = enemy(origin+Vector2(100,8))
	await wait(0.06)
	rail._shoot()
	check(behind.HP == 100,"rail wall blocks")
	block.queue_free()
	await clean()
	var prism = PlayerData.player_weapon_list[111]
	aim(prism)
	var close = enemy(origin+Vector2(28,8))
	await wait(0.06)
	prism._shoot()
	check(is_equal_approx(100-close.HP,prism.effective.damage*3),"prism actual intersecting three beams")
	await clean()
	var cone = PlayerData.player_weapon_list[115]
	aim(cone)
	var inside = enemy(origin+Vector2(50,8))
	var outside = enemy(origin+Vector2(20,80))
	var distant = enemy(origin+Vector2(160,8))
	await wait(0.06)
	cone._shoot()
	check(inside.HP < 100 and outside.HP == 100 and distant.HP == 100,"cone angle and range real exclusion")
	await clean()
	var thermal = PlayerData.player_weapon_list[116]
	aim(thermal)
	var hot = enemy(origin+Vector2(50,8))
	await wait(0.06)
	thermal._shoot()
	var after_tick = hot.HP
	await wait(0.3)
	check(hot.HP < after_tick and hot.burns.size() == 1,"thermal finite timed burn actual damage")
	for i in 8: thermal._shoot()
	check(hot.burns.size() == 1,"thermal same source refresh has one record")
	Demo.push_pause(self)
	check(not thermal.sustained,"thermal pause clears sustained state")
	Demo.pop_pause(self)
	await wait(1.3)
	check(hot.burns.is_empty(),"burn expires")
	await clean()
	await wait(1.5)
	print("M3 ENERGY SUMMARY checks=",checks," failures=",failures)
	get_tree().quit(1 if failures else 0)
