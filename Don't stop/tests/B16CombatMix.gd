extends "res://tests/B12WeaponBench.gd"

func _ready():
	await boot()
	Utils.player.set_process(false); Utils.player.set_physics_process(false)
	Utils.player.global_position = origin-Vector2(20,0)
	for id in [0,1,6,116,112,113,120,121,122]:
		await clean(); configure(id,true)
		var gun = Utils.player.gun
		Demo.grenade_cooldown = 0; Demo.talent_cooldowns.clear()
		Demo.heal_cooldown = 0; PlayerData.player_hp = 2
		var targets = []
		for i in 12:
			var target = enemy(origin+Vector2(40+(i%4)*20,8+(i/4-1)*16),20)
			target.knockback_def = 100000
			targets.append(target)
		await wait(0.08); LevelServer.state = "COMBAT"
		var hits = Combat.damage_events
		var start = Time.get_ticks_msec()
		var previous = start
		while Time.get_ticks_msec()-start < 3000:
			var now = Time.get_ticks_msec()
			var living = targets.filter(func(t):return is_instance_valid(t) and not t.is_die)
			if living.is_empty(): break
			fire_at(living[0].global_position-Vector2(0,8),(now-previous)/1000.0)
			if id == 6: gun._physics_process((now-previous)/1000.0)
			previous = now
			await wait(0.01)
		gun.cancel_actions()
		check(Combat.damage_events > hits,"real full-growth weapon produces hits "+str(id))
		check(Combat.max_depth_seen <= DemoConfig.MAX_DERIVATION,"bounded derived hits "+str(id))
		check(gun.bullets_count <= gun.bullets_max_count,"refill never overfills "+str(id))
		print("B16_MIX ",JSON.stringify({"id":id,"hits":Combat.damage_events-hits,"hp":PlayerData.player_hp,"blast_cooldown":Demo.grenade_cooldown,"ammo":gun.bullets_count}))
	await clean()
	print("B16 MIX checks=",checks," failures=",failures)
	get_tree().quit(1 if failures else 0)
