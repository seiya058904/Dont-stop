extends "res://tests/M3Weapons.gd"
## B13 talent effect contract. Complements M4Talents: M4 proves the behaviour of every
## talent (purchase/reset/conditions/bounds); this contract pins the exact RUNTIME MAGNITUDE
## each talent must produce at its catalog values, so a rebalanced number can never silently
## stop reaching the live stats (UI says one thing, runtime does less).

var gun: BaseGun
var base: Dictionary

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

func near(a: float, b: float) -> bool:
	return is_equal_approx(a,b)

func _ready():
	Demo.test_mode = true
	seed(134)
	var main = load("res://game/map/Main.tscn").instantiate()
	add_child(main)
	Utils.gameStart(); PlayerData.gold = 100000; PlayerData.reward_point = 9999
	await wait(0.2)
	Utils.player.global_position = origin-Vector2(100,0)
	Demo.try_purchase("weapon","0")
	gun = PlayerData.player_weapon_list[0]
	aim(gun)
	ranks({})
	base = gun.effective.duplicate(true)
	LevelServer.state = "COMBAT"
	# --- the exact passives ------------------------------------------------------------
	ranks({"T01":3})
	check(near(gun.effective.damage,base.damage*(1.0+DemoConfig.talent_value("T01",3))),"T01 damage magnitude is the catalog value")
	ranks({"T02":3})
	check(near(gun.effective.rate,base.rate*(1.0+DemoConfig.talent_value("T02",3))),"T02 fire rate magnitude is the catalog value")
	ranks({"T02":1})
	check(near(gun.effective.rate,base.rate*(1.0+DemoConfig.talent_value("T02",1))),"T02 rank 1 matches its catalog step")
	ranks({"T03":3})
	check(near(gun.effective.reload,maxf(DemoConfig.MIN_RELOAD_SECONDS,base.reload*(1.0-DemoConfig.talent_value("T03",3)))),"T03 reload magnitude is the catalog value")
	ranks({"T04":3})
	check(int(gun.effective.magazine)==int(float(gun.base_stats.magazine)*(1.0+DemoConfig.talent_value("T04",3))),"T04 magazine magnitude is the catalog value")
	ranks({"T05":3})
	check(near(float(gun.effective.range),float(base.range)*(1.0+DemoConfig.talent_value("T05",3))),"T05 range magnitude is the catalog value")
	ranks({"T06":3})
	check(near(gun.effective.crit,base.crit+DemoConfig.talent_value("T06",3)),"T06 crit magnitude is the catalog value")
	ranks({"T07":3,"T08":3,"T09":3,"T18":3})
	check(PlayerData.player_hp_max==5+3,"T07 HP magnitude is the catalog value")
	check(is_equal_approx(Utils.player.SPEED,100*PlayerData.player_speed+100*DemoConfig.talent_value("T08",3)),"T08 speed magnitude is the catalog value")
	var inspect = EffectiveStats.inspect(gun)
	check(is_equal_approx(float(inspect.player.coin_radius),DemoConfig.talent_value("T09",3)),"T09 pickup magnitude is the catalog value")
	check(is_equal_approx(gun.effective.impulse,base.impulse*(1.0+DemoConfig.talent_value("T18",3))),"T18 impulse magnitude is the catalog value")
	# --- conditional values --------------------------------------------------------------
	ranks({"T10":3})
	Demo.kill_stacks = DemoConfig.TALENTS.T10.stacks
	gun.updateGun()
	check(near(gun.effective.rate,base.rate*(1.0+Demo.kill_stacks*DemoConfig.talent_value("T10",3))),"T10 full-stack rate is stacks x catalog step")
	ranks({"T12":3})
	gun.bullets_count = 0; PlayerData.reserve_magazines = 100
	gun.reload_ammo(); gun.cancel_actions()
	gun.reload_ammo()
	await wait(gun.effective.reload+0.1)
	var first = gun.shot_context()
	check(near(first.damage,gun.effective.damage*(1.0+DemoConfig.talent_value("T12",3))),"T12 first-shot magnitude is the rank-3 catalog value")
	check(near(DemoConfig.talent_value("T12",3),0.55),"T12 rank 3 is +55 percent")
	ranks({"T15":3})
	var burn_target = enemy(origin+Vector2(40,8),1000)
	var context = gun.damage_context()
	Combat.hit(burn_target,context)
	check(burn_target.burns.has("T15"),"T15 burn applies")
	check(near(float(burn_target.burns["T15"].context.damage),DemoConfig.talent_value("T15",3)),"T15 per-tick burn damage equals step x rank")
	var burn_hp = burn_target.HP
	await wait(0.3)
	check(burn_target.HP < burn_hp,"T15 burn tick deals real damage")
	ranks({"T17":3})
	burn_target.burns.clear()
	Combat.hit(burn_target,gun.damage_context())
	check(near(burn_target.slow_amount,DemoConfig.talent_value("T17",3)),"T17 slow magnitude is step x rank (cap 0.24)")
	ranks({"T21":3})
	var elite = enemy(origin+Vector2(60,8)); elite.is_elite = true
	var hp0 = elite.HP
	Combat.hit(elite,gun.damage_context())
	check(near(hp0-elite.HP,context.damage*(1.0+DemoConfig.talent_value("T21",3))),"T21 elite multiplier is the rank-3 catalog value")
	ranks({"T22":3})
	Utils.player.global_position = origin
	for i in 3: enemy(origin+Vector2(50+i*20,8),3.0)
	Demo.crowd_clock = 0; Demo._process(0.2)
	check(Demo.crowd_active,"T22 density condition met")
	check(near(gun.damage_context().damage,gun.effective.damage*(1.0+DemoConfig.talent_value("T22",3))),"T22 crowd multiplier is the rank-3 catalog value")
	ranks({})
	await clean()
	# --- legendary mechanisms, exact ----------------------------------------------------
	ranks({"T13":1})
	var straight = [enemy(origin+Vector2(30,8)),enemy(origin+Vector2(60,8)),enemy(origin+Vector2(90,8)),enemy(origin+Vector2(120,8))]
	await wait(0.06)
	var bullet = gun.bullet_scene.instantiate(); add_child(bullet); bullet.position = origin; bullet.rotation = 0; gun.fire(bullet)
	await wait(0.35)
	check(straight[0].HP < 100 and straight[1].HP < 100 and straight[2].HP < 100 and straight[3].HP == 100,"T13 B14 value: exactly two extra targets; fourth remains unharmed")
	await clean()
	ranks({"T14":1})
	var arc_source = enemy(origin+Vector2(40,8),100000)
	var arc_next = enemy(origin+Vector2(75,8),100000)
	var forced = gun.damage_context()
	forced.damage = 10.0; forced.crit = 0.0
	var arc_procd = false
	for i in 40:
		if Demo.cooldown("T14") <= 0:
			var hp_before = arc_next.HP
			Combat.hit(arc_source,forced)
			if is_equal_approx(hp_before-arc_next.HP,forced.damage*DemoConfig.TALENTS.T14.damage): arc_procd = true
		await wait(0.55)
	check(arc_procd,"T14 arc deals exactly the catalog 50 percent rider")
	check(is_equal_approx(DemoConfig.TALENTS.T14.cooldown,0.5) and DemoConfig.TALENTS.T14.step > 0.2,"T14 legendary values were deepened")
	await clean()
	ranks({"T16":1})
	var blast_victim = enemy(origin+Vector2(35,8),0.1)
	var blast_neighbour = enemy(origin+Vector2(50,8),1000)
	var nb_hp = blast_neighbour.HP
	Combat.hit(blast_victim,gun.damage_context())
	check(near(nb_hp-blast_neighbour.HP,DemoConfig.TALENTS.T16.damage),"T16 kill blast deals the catalog 2.6")
	check(is_equal_approx(DemoConfig.TALENTS.T16.radius,40.0),"T16 legendary radius was deepened")
	ranks({"T19":1})
	PlayerData.player_hp = PlayerData.player_hp_max
	var hp = PlayerData.player_hp
	Utils.player.onHit(1)
	check(PlayerData.player_hp == hp and Demo.cooldown("T19") > 0,"T19 shield blocks one hit")
	check(Demo.cooldown("T19") > 5.0 and is_equal_approx(DemoConfig.TALENTS.T19.cooldown,6.0),"T19 legendary cooldown was deepened to 6s")
	Utils.player.onHit(1)
	check(PlayerData.player_hp == hp-1,"T19 same-frame follow-up still damages")
	await clean()
	ranks({"T23":1})
	var echo_source = enemy(origin+Vector2(40,8),100000)
	var echo_next = enemy(origin+Vector2(80,8),100000)
	forced = gun.damage_context(); forced.crit = 1.0; forced.damage = 10.0
	var echo_hp = echo_next.HP
	Combat.hit(echo_source,forced)
	# A forced crit multiplies the hit by 1.5 first; the echo rides the CRITICAL amount.
	check(near(echo_hp-echo_next.HP,forced.damage*1.5*DemoConfig.TALENTS.T23.step),"T23 echo deals exactly the catalog 40 percent of the critical hit")
	check(is_equal_approx(DemoConfig.TALENTS.T23.radius,85.0),"T23 legendary radius was deepened")
	await clean()
	ranks({"T24":3})
	var heal_victim = enemy(origin+Vector2(35,8),0.1)
	PlayerData.player_hp = 2
	Combat.hit(heal_victim,gun.damage_context())
	check(near(PlayerData.player_hp-2.0,DemoConfig.talent_value("T24",3)),"T24 kill heal equals step x rank")
	# --- prices actually charged ---------------------------------------------------------
	LevelServer.state = "CAMP"
	ranks({})
	Demo.replenish()
	var gold = PlayerData.gold
	check(Demo.try_purchase("talent","T01","gold").success and PlayerData.gold == gold-150,"T01 rank 1 charges the common price 150")
	check(Demo.try_purchase("talent","T01","gold").success and PlayerData.gold == gold-150-250,"T01 rank 2 charges 250")
	check(Demo.try_purchase("talent","T16","gold").success and PlayerData.gold == gold-150-250-2400,"T16 charges the legendary price 2400")
	var points = PlayerData.reward_point
	check(Demo.try_purchase("talent","T02","points").success and PlayerData.reward_point == points-2,"T02 rank 1 charges 2 points")
	check(Demo.try_purchase("talent","T02","points").success and PlayerData.reward_point == points-2-3,"T02 rank 2 charges 3 points")
	ranks({})
	await clean()
	await wait(0.5)
	print("B13_TALENT_EFFECTS_CHECKS ",checks," FAILURES ",failures)
	get_tree().quit.call_deferred(1 if failures else 0)
