extends Node
var checks = 0
var failures = 0
var main
var town
func check(value, name):
	checks += 1
	if not value: failures += 1
	print(("PASS " if value else "FAIL ") + name)
func enemy(point, hp):
	var target = load("res://game/monster/Monster 2/Monster2.tscn").instantiate()
	target.global_position = point
	target.HP = hp
	add_child(target)
	target.set_physics_process(false)
	return target
func physical_shot(gun, target, distance = 35):
	var bullet = gun.bullet_scene.instantiate()
	add_child(bullet)
	bullet.global_position = target.global_position + Vector2(-distance,-8)
	bullet.rotation = 0
	gun.fire(bullet)
	return bullet
func _ready():
	process_mode = Node.PROCESS_MODE_ALWAYS
	Demo.test_mode = true
	seed(920)
	main = load("res://game/map/Main.tscn").instantiate()
	add_child(main)
	Utils.gameStart()
	town = main.get_node("Town")
	for frame in 8: await get_tree().physics_frame
	Demo.try_purchase("weapon","0")
	Demo.try_purchase("weapon","4")
	var gun = PlayerData.player_weapon_list[0]
	var reserve = PlayerData.player_weapon_list[4]
	Utils.player.changeWeapon(0)
	Utils.player.global_position = Vector2(0,-1000)
	LevelServer.state = "COMBAT"
	PlayerData.player_exp = PlayerData.getMaxExp()-1
	var old_damage = gun.effective.damage
	var target = enemy(Vector2(400,-1000),50)
	var old_bullet = physical_shot(gun,target,350)
	var victim = enemy(Vector2(80,-1050),0.1)
	physical_shot(gun,victim)
	var remaining = gun.bullets_count
	reserve.bullets_count -= 3
	for frame in 16: await get_tree().physics_frame
	check(PlayerData.player_level == 2 and Demo.rank("T10") == 0,"R01 actual bullet kill levels up without T10")
	check(is_equal_approx(gun.damage_context().damage,gun.base_stats.damage+0.6),"R01 first new shot snapshot refreshed")
	check(is_equal_approx(reserve.damage_context().damage,reserve.base_stats.damage+0.6),"R01 held reserve gun refreshed")
	check(gun.bullets_count == remaining,"R01 level does not refill ammo")
	check(is_equal_approx(old_bullet.hurt,old_damage),"R01 in-flight normal projectile keeps snapshot")
	var next_target = enemy(Vector2(80,-1100),50)
	physical_shot(gun,next_target)
	for frame in 16: await get_tree().physics_frame
	check(is_equal_approx(50-next_target.HP,gun.base_stats.damage+0.6),"R01 first post-level actual collision damage")
	Utils.player.changeWeapon(4)
	var reserve_target = enemy(Vector2(80,-1150),50)
	physical_shot(reserve,reserve_target)
	for frame in 16: await get_tree().physics_frame
	check(is_equal_approx(50-reserve_target.HP,reserve.base_stats.damage+0.6),"R01 reserve weapon actual collision damage")
	LevelServer.return_to_camp()
	Demo.try_purchase("attachment","110")
	Demo.try_purchase("attachment","1")
	var a = PlayerData.player_am_list.values()[0]
	var b = PlayerData.player_am_list.values()[1]
	gun.addAttachMent(a)
	gun.addAttachMent(b)
	var data = Demo.snapshot()
	check(Demo.valid_save(data),"R03 valid current snapshot")
	var bad = data.duplicate(true)
	bad.legacy = {}
	check(not Demo.valid_save(bad),"R03 legacy dictionary rejected")
	bad = data.duplicate(true); bad.legacy = [null]
	check(not Demo.valid_save(bad),"R03 null legacy entry rejected")
	bad = data.duplicate(true); bad.weapons[0].id = "unknown"; bad.equipped = "unknown"
	check(not Demo.valid_save(bad),"R03 unknown weapon rejected")
	bad = data.duplicate(true); bad.attachments[0].gun = "9"
	check(not Demo.valid_save(bad),"R03 dangling attachment owner rejected")
	bad = data.duplicate(true); bad.attachments[1].definition = "110"
	check(not Demo.valid_save(bad),"R03 occupied slot conflict rejected")
	bad = data.duplicate(true); bad.attachments[0].instance = 1.5
	check(not Demo.valid_save(bad),"R03 fractional instance rejected")
	bad = data.duplicate(true); bad.next_instance = 2
	check(not Demo.valid_save(bad),"R03 next instance collision rejected")
	bad = data.duplicate(true); bad.talents.T01 = 4
	check(not Demo.valid_save(bad),"R03 invalid talent rejected")
	bad = data.duplicate(true); bad.erase("legacy"); bad.schema_version = 1
	check(Demo.valid_save(bad),"R03 schema1 missing legacy migration")
	var result = Demo.save_camp()
	check(result is Dictionary and result.has("success"),"R04 save returns structured outcome")
	Demo.try_purchase("weapon","3")
	var baby = PlayerData.player_weapon_list[3]
	Utils.player.changeWeapon(3)
	baby.bullets_count = 27
	baby._shoot()
	Demo.push_pause(self)
	await get_tree().create_timer(0.05,true).timeout
	Demo.pop_pause(self)
	var cancelled = baby.bullets_count
	await get_tree().create_timer(0.35,true).timeout
	check(baby.bullets_count == cancelled,"V02 old Baby volley cancelled across pause")
	LevelServer.state = "COMBAT"; LevelServer.level = 1; Demo.trial = false
	LevelServer.victory()
	for menu in Demo.pause_stack.duplicate(): Demo.pop_pause(menu); menu.queue_free()
	for frame in 3: await get_tree().process_frame
	town._on_portal_move_in(town.portal_lv1)
	town._on_portal_2_move_out()
	check(LevelServer.level == 3 and not Demo.trial,"R05 old portal uses next normal encounter")
	LevelServer.return_to_camp()
	var camera = get_tree().get_nodes_in_group("camera")[0]
	Utils.shake = 0.35
	camera.shootShake(Vector2.ONE)
	check(camera.is_shake,"feedback nonzero default shake is active")
	check(town.get_node("Kill").bus == "SFX","R07 old kill sound uses SFX")
	Demo.try_purchase("legacy","6")
	var star = Utils.player.reward_root.get_node("REWARD AMBER STAR")
	var marked = enemy(Vector2(0,-1500),20)
	star.afterAtk(marked,1)
	marked.queue_free()
	for frame in 2: await get_tree().process_frame
	check(star.mark_dict.is_empty(),"V01 freed target removes mark cache")
	LevelServer.town.depart(1,true); LevelServer.timerStop()
	var derived = enemy(Vector2(0,-1500),0.1)
	star.afterAtk(derived,0.01)
	var kills = Combat.kill_events
	Combat.hit(derived,{"damage":1,"depth":1})
	check(star.mark_dict.is_empty() and Combat.kill_events == kills+1,"V01 derived death clears cache without extra reward kills")
	var cleaned = enemy(Vector2(0,-1550),20)
	star.afterAtk(cleaned,0.01)
	LevelServer.return_to_camp()
	for frame in 2: await get_tree().process_frame
	check(star.mark_dict.is_empty(),"V01 camp cleanup clears live target marks")
	print("R1 SUMMARY checks=",checks," failures=",failures)
	for kind in ["AudioStreamPlayer","AudioStreamPlayer2D"]:
		for node in get_tree().root.find_children("*",kind,true,false): node.stream_paused = false; node.stop()
	await get_tree().create_timer(0.15,true).timeout
	get_tree().quit(1 if failures else 0)
