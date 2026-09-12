extends "res://tests/M3Weapons.gd"
var gun
func ranks(values: Dictionary):
	Demo.talents = values.duplicate()
	Demo.talent_payments.clear()
	Demo.talent_cooldowns.clear()
	Demo.kill_stacks = 0; Demo.stack_time = 0; Demo.ammo_kills = 0
	Demo.blast_cooldown = 0; Demo.heal_cooldown = 0
	Demo.crowd_active = false
	Demo.refresh()
	gun.first_round = false
	gun.boosted_frame = -1
func hit_enemy(target, depth = 0, damage = -1):
	var context = gun.damage_context(depth)
	if damage >= 0: context.damage = damage
	Combat.hit(target,context)
func _ready():
	Demo.test_mode = true
	seed(444)
	var main = load("res://game/map/Main.tscn").instantiate()
	add_child(main)
	Utils.gameStart(); PlayerData.gold = 100000; PlayerData.reward_point = 9999
	await wait(0.2)
	Utils.player.global_position = origin-Vector2(100,0)
	Demo.try_purchase("weapon","0")
	Demo.try_purchase("weapon","116")
	gun = PlayerData.player_weapon_list[0]
	aim(gun)
	check(DemoConfig.TALENTS.size() == 24,"24 persistent talent definitions")
	for id in DemoConfig.TALENTS:
		LevelServer.state = "CAMP"
		ranks({})
		Demo.replenish()
		check(Demo.rank(id) == 0 and not DemoConfig.talent_info(id).is_empty(),"unowned and explicit condition "+id)
		for level in DemoConfig.TALENTS[id].max: check(Demo.try_purchase("talent",id,"gold" if level%2 else "points").success,"purchase level "+id+"/"+str(level+1))
		var gold = PlayerData.gold
		var points = PlayerData.reward_point
		check(not Demo.try_purchase("talent",id).success and PlayerData.gold == gold and PlayerData.reward_point == points,"max rank rejects without charge "+id)
		var preview = Demo.reset_preview()
		check(Demo.reset_talents(preview.revision).success and Demo.rank(id) == 0,"reset removes effect source "+id)
		check(PlayerData.gold == gold+preview.gold and PlayerData.reward_point == points+preview.points,"refund exact mixed currencies "+id)
		check(not Demo.reset_talents(preview.revision).success,"repeat reset rejected "+id)
	LevelServer.state = "COMBAT"
	ranks({})
	var base = gun.effective.duplicate(true)
	var hp_max = PlayerData.player_hp_max
	var speed = Utils.player.SPEED
	for pair in [["T01","damage"],["T02","rate"],["T03","reload"],["T04","magazine"],["T05","range"],["T06","crit"],["T18","impulse"]]:
		ranks({pair[0]:3})
		check(gun.effective[pair[1]] != base[pair[1]],"passive actual calculated effect "+pair[0])
		ranks({})
		check(is_equal_approx(gun.effective[pair[1]],base[pair[1]]),"passive inactive/restored "+pair[0])
	ranks({"T02":3})
	var thermal = PlayerData.player_weapon_list[116]
	check(thermal.effective.rate == 10 and thermal.effective.damage > thermal.base_stats.damage+PlayerData.player_damage,"T02 continuous fixed tick uses damage strategy")
	ranks({"T07":3,"T08":3})
	check(PlayerData.player_hp_max == hp_max+3 and Utils.player.SPEED == speed+9,"T07 T08 real health and movement")
	for cycle in 20: Demo.refresh()
	check(PlayerData.player_hp_max == hp_max+3 and Utils.player.SPEED == speed+9,"T07 T08 repeat refresh no drift")
	ranks({})
	check(PlayerData.player_hp_max == hp_max and Utils.player.SPEED == speed,"T07 T08 removal restores")
	# T09 real coin collection expanded only when unobstructed.
	Utils.player.global_position = origin
	var gold_before = PlayerData.gold
	var coin = load("res://game/items/Gold.tscn").instantiate(); coin.position = origin+Vector2(30,0); add_child(coin)
	await wait(0.1)
	check(PlayerData.gold == gold_before,"T09 absent does not collect outside base radius")
	ranks({"T09":3})
	await wait(0.1)
	check(PlayerData.gold == gold_before+1,"T09 expanded radius collects actual coin")
	var barrier = wall(origin+Vector2(-15,0),Vector2(3,100))
	coin = load("res://game/items/Gold.tscn").instantiate(); coin.position = origin-Vector2(30,0); add_child(coin)
	await wait(0.1)
	check(not coin.collected,"T09 obstacle blocks pickup")
	barrier.queue_free()
	await clean()
	Utils.player.global_position = origin-Vector2(100,0)
	# Direct kills versus derived kills and fake targets.
	ranks({"T10":3,"T11":3,"T16":1,"T24":3})
	PlayerData.player_hp = 2
	var ammo = PlayerData.reserve_magazines
	var victim = enemy(origin+Vector2(35,8),0.1)
	var neighbour = enemy(origin+Vector2(45,8))
	hit_enemy(victim,0,1)
	check(Demo.kill_stacks == 1 and Demo.stack_time > 0,"T10 kill stack active")
	check(neighbour.HP < 100 and Demo.blast_cooldown > 0,"T16 direct kill explosion hits neighbour")
	check(PlayerData.player_hp > 2 and Demo.heal_cooldown > 0,"T24 direct kill heal")
	var healed = PlayerData.player_hp
	victim = enemy(origin+Vector2(150,8),0.1); hit_enemy(victim,1,1)
	check(PlayerData.player_hp == healed and Demo.ammo_kills == 1,"T11 T24 derived kill exclusion")
	for i in 4:
		victim = enemy(origin+Vector2(220+i*35,8),0.1); hit_enemy(victim,0,1)
	check(PlayerData.reserve_magazines == ammo+3 and Demo.ammo_kills == 0,"T11 five direct kills restore reserve")
	check(Demo.kill_stacks <= 5,"T10 bounded stacks")
	var dummy = enemy(origin); dummy.training = true
	var stacks = Demo.kill_stacks
	hit_enemy(dummy,0,5000)
	check(Demo.kill_stacks == stacks and PlayerData.player_hp == healed,"training cannot give kill benefits")
	Demo._process(5)
	check(Demo.kill_stacks == 0,"T10 expiry removes rate stack")
	await clean()
	# First shot comes only from completed actual refill.
	ranks({"T12":3})
	aim(gun)
	gun.bullets_count = 0; PlayerData.reserve_magazines = 1000
	gun.reload_ammo(); gun.cancel_actions()
	check(not gun.first_round,"T12 cancelled reload does not prime")
	gun.reload_ammo()
	await wait(gun.effective.reload+0.1)
	check(gun.first_round,"T12 actual completed refill primes")
	var context = gun.shot_context()
	check(is_equal_approx(context.damage,gun.effective.damage*1.25),"T12 first shot snapshot has 25 percent")
	await wait(0.03)
	check(is_equal_approx(gun.shot_context().damage,gun.effective.damage),"T12 later shot no bonus")
	# Actual ordinary projectile pierces exactly one additional target.
	ranks({"T13":1})
	var targets = [enemy(origin+Vector2(30,8)),enemy(origin+Vector2(60,8)),enemy(origin+Vector2(90,8))]
	await wait(0.06)
	var bullet = gun.bullet_scene.instantiate(); add_child(bullet); bullet.position = origin; bullet.rotation = 0; gun.fire(bullet)
	await wait(0.2)
	check(targets[0].HP < 100 and targets[1].HP < 100 and targets[2].HP == 100,"T13 real ordinary two-target penetration")
	check(thermal.effective.pierce == 0,"T13 incompatible thermal unchanged")
	await clean()
	# Secondary arc, burn, cold, echo: root-only, bounded records and cooldown.
	ranks({"T14":1,"T15":3,"T17":3,"T23":1})
	var source = enemy(origin+Vector2(40,8),1000)
	var secondary = enemy(origin+Vector2(75,8),1000)
	var forced = gun.damage_context()
	forced.crit = 1.0 # Deterministic critical fixture; chance for T14 remains catalog 20%.
	var arc_seen = false
	for i in 50:
		Combat.hit(source,forced)
		if Demo.cooldown("T14") > 0: arc_seen = true
	check(arc_seen and secondary.HP < 1000,"T14 seeded chance creates real secondary damage")
	check(Demo.cooldown("T23") > 0,"T23 actual critical echo triggers cooldown")
	check(source.burns.size() == 1 and is_equal_approx(source.slow_amount,0.24),"T15 T17 finite burn and capped slow")
	var second_hp = secondary.HP
	forced.depth = 1
	Combat.hit(source,forced)
	check(secondary.HP == second_hp and secondary.burns.is_empty(),"secondary cannot re-arc echo burn or slow")
	var burn_hp = source.HP
	await wait(0.3)
	check(source.HP < burn_hp,"T15 burn tick causes actual damage")
	await wait(1.5)
	check(source.burns.is_empty() and source.slow_time == 0,"T15 T17 conditions expire")
	await clean()
	ranks({})
	source = enemy(origin+Vector2(40,8)); secondary = enemy(origin+Vector2(75,8))
	forced = gun.damage_context(); forced.crit = 1
	Combat.hit(source,forced)
	check(secondary.HP == 100 and source.burns.is_empty() and source.slow_time == 0,"unowned secondary talents do not trigger")
	await clean()
	# Shield same-frame protection is single-use, then a true cooldown.
	ranks({"T19":1})
	PlayerData.player_hp = PlayerData.player_hp_max
	var hp = PlayerData.player_hp
	Utils.player.onHit(1); Utils.player.onHit(1)
	check(PlayerData.player_hp == hp-1 and Demo.cooldown("T19") > 0,"T19 one shield then same-frame damage")
	ranks({})
	hp = PlayerData.player_hp; Utils.player.onHit(1)
	check(PlayerData.player_hp == hp-1,"T19 absent does not prevent damage")
	ranks({"T20":3})
	PlayerData.player_hp = 1
	LevelServer.return_to_camp()
	check(PlayerData.player_hp == 1,"T20 ordinary camp return no heal")
	LevelServer.state = "COMBAT"; LevelServer.epoch += 1
	check(LevelServer.victory(),"T20 actual victory resolves")
	hp = PlayerData.player_hp
	check(hp > 1 and not LevelServer.victory() and PlayerData.player_hp == hp,"T20 victory heal once")
	for menu in Demo.pause_stack.duplicate(): Demo.pop_pause(menu); menu.queue_free()
	LevelServer.state = "COMBAT"
	ranks({"T21":3})
	source = enemy(origin+Vector2(35,8)); source.is_elite = true
	secondary = enemy(origin+Vector2(100,8)); secondary.is_boss = true; secondary.is_elite = true
	hit_enemy(source,0,10); hit_enemy(secondary,0,10)
	check(source.HP == 88 and secondary.HP == 90,"T21 elite bonus excludes boss")
	await clean()
	ranks({"T22":3})
	Utils.player.global_position = origin
	source = enemy(origin+Vector2(30,8))
	Demo.crowd_clock = 0; Demo._process(0.2)
	check(not Demo.crowd_active,"T22 insufficient density inactive")
	for i in 2: enemy(origin+Vector2(50+i*20,8))
	Demo.crowd_clock = 0; Demo._process(0.2)
	check(Demo.crowd_active and gun.damage_context().damage > gun.effective.damage,"T22 cached density modifies emitted context")
	await clean()
	ranks({})
	await wait(1.0)
	print("M4 TALENTS SUMMARY checks=",checks," failures=",failures)
	get_tree().quit.call_deferred(1 if failures else 0)
