extends "res://tests/M8Runtime.gd"

func _ready():
	await boot()
	Demo.talents={};Demo.owned_global_upgrades=[]
	for fraction in [0.0,0.5,1.0]:
		await clean();configure(113)
		var gun=Utils.player.gun
		gun.updateGun();aim(gun)
		var targets=[]
		for i in 9:targets.append(enemy(origin+Vector2(30+i*30,8),10000))
		await wait(0.08);LevelServer.state="COMBAT"
		gun.charge_time=gun.effective.warmup*fraction
		gun._shoot();await wait(0.05)
		var hits=targets.filter(func(t):return t.HP<10000).size()
		check(hits==[1,4,8][int(fraction*2)],"actual rail tap/half/full target limit %.1f: %d"%[fraction,hits])
		check(gun.bullets_count==gun.bullets_max_count-1,"one rail release uses one round")
	await clean();configure(113)
	var gun=Utils.player.gun
	gun.updateGun();aim(gun)
	var near=enemy(origin+Vector2(35,8),10000)
	var behind=enemy(origin+Vector2(90,8),10000)
	var barrier=wall(origin+Vector2(65,0),Vector2(4,100))
	await wait(0.08);LevelServer.state="COMBAT"
	gun.charge_time=gun.effective.warmup;gun._shoot();await wait(0.05)
	check(near.HP<10000 and behind.HP==10000,"full wide rail stops all lanes at the real wall")
	barrier.queue_free();await clean();configure(113);aim(gun)
	LevelServer.state="COMBAT";gun.can_shoot=true
	gun.handle_charge(true,0.4)
	var ammo=gun.bullets_count
	gun.cancel_actions();gun.handle_charge(false,0.1)
	check(not gun.charging and gun.charge_time==0 and gun.bullets_count==ammo,"cancelled half charge cannot release or consume ammo")
	print("B14_RAIL_CHECKS ",checks," FAILURES ",failures)
	get_tree().quit.call_deferred(1 if failures else 0)
