extends "res://tests/M8Runtime.gd"

var fragments: Array = []
var rows: Array = []

func _ready():
	await boot()
	get_tree().node_added.connect(func(node):
		if node.get_script() == load("res://game/bullets/MechanismProjectile.gd") and node.spec.get("mode","") == "fragment":
			fragments.append({"damage":node.context.damage,"depth":node.context.depth}))
	for upgraded in [false,true]:
		await clean()
		Demo.owned_global_upgrades = ["120"] if upgraded else []
		configure(118)
		var gun = Utils.player.gun
		gun.updateGun()
		aim(gun)
		var target = enemy(origin+Vector2(50,8),10000)
		var downstream = enemy(origin+Vector2(90,8),10000)
		await wait(0.08)
		fragments.clear()
		LevelServer.state = "COMBAT"
		gun._shoot()
		await wait(0.4)
		rows.append({"case":"shards-upgrade" if upgraded else "shards-native","fragments":fragments.duplicate(true),"primary_damage":10000-target.HP,"downstream_damage":10000-downstream.HP,"effective":gun.effective.duplicate(true)})
		check(fragments.size() == (5 if upgraded else 3),"actual fragment count %s" % str(upgraded))
		check(not fragments.is_empty() and fragments.all(func(f): return f.depth == 1),"fragments stay one generation")
	check(rows[1].fragments[0].damage >= rows[0].fragments[0].damage,"upgrade never lowers native fragment damage")
	# Thermal: same real cone targets/ticks, only the legal T10 stack state changes.
	Demo.owned_global_upgrades = []
	Demo.talents = {"T10":1}
	for stacks in [0,5]:
		await clean()
		configure(116)
		Demo.kill_stacks = stacks; Demo.stack_time = 10
		var gun = Utils.player.gun
		gun.updateGun(); aim(gun)
		var target = enemy(origin+Vector2(50,8),10000)
		await wait(0.08)
		LevelServer.state = "COMBAT"
		var attacks = Combat.attacks
		for tick in 10:
			gun.handle_thermal(true,0.1)
			await get_tree().physics_frame
		rows.append({"case":"thermal-stacks-%d" % stacks,"attacks":Combat.attacks-attacks,"damage":10000-target.HP,"effective":gun.effective.duplicate(true)})
	check(rows[2].attacks == 10 and rows[3].attacks == 10,"ten requested thermal ticks emit ten attacks")
	check(rows[3].damage > rows[2].damage*1.1,"T10 increases actual thermal damage")
	Demo.talents={};Demo.kill_stacks=0;Demo.stack_time=0
	var reflected_damage=[]
	for upgraded in [false,true]:
		await clean()
		Demo.owned_global_upgrades=["119"] if upgraded else []
		configure(117)
		var gun=Utils.player.gun
		gun.updateGun();aim(gun)
		var target=enemy(origin+Vector2(-40,8),10000)
		var barrier=wall(origin+Vector2(60,0),Vector2(4,120))
		await wait(0.08);LevelServer.state="COMBAT"
		gun._shoot();await wait(0.6)
		reflected_damage.append(10000-target.HP)
		rows.append({"case":"bounce-upgrade" if upgraded else "bounce-native","damage":10000-target.HP,"effective":gun.effective.duplicate(true)})
		barrier.queue_free()
	check(reflected_damage[0]>0 and reflected_damage[1]>=reflected_damage[0],"purchased bounce core never lowers the actual first reflected hit")
	var rotary_damage=[]
	Demo.owned_global_upgrades=[]
	for accelerated in [false,true]:
		await clean()
		Demo.talents={"T02":3} if accelerated else {}
		configure(124)
		var gun=Utils.player.gun
		gun.updateGun();aim(gun)
		var target=enemy(origin+Vector2(50,8),10000)
		await wait(0.08);LevelServer.state="COMBAT"
		gun._shoot();await wait(0.25)
		rotary_damage.append(10000-target.HP)
		check(gun.effective.rate==24,"rotary keeps 24/s ceiling")
		rows.append({"case":"rotary-T02" if accelerated else "rotary-native","damage":10000-target.HP,"effective":gun.effective.duplicate(true)})
	check(rotary_damage[0]>0 and rotary_damage[1]>rotary_damage[0]*1.2,"capped rotary converts purchased cycle growth to actual shot damage")
	await clean()
	Demo.talents={"T13":1}
	configure(0)
	var rifle=Utils.player.gun
	rifle.updateGun();aim(rifle)
	var line_targets=[]
	for i in 4:line_targets.append(enemy(origin+Vector2(30+i*30,8),10000))
	await wait(0.08);LevelServer.state="COMBAT"
	Utils.aim_override=get_viewport().get_canvas_transform()*(origin+Vector2(200,0))
	rifle._shoot();await wait(0.4)
	Utils.aim_override=null
	print("B14_T13_HITS ",line_targets.map(func(t):return 10000-t.HP)," stats=",rifle.effective)
	check(line_targets.slice(0,3).all(func(t):return t.HP<10000) and line_targets[3].HP==10000,"legendary T13 reaches exactly three targets without other piercing")
	await clean()
	Demo.talents={}
	for id in DemoConfig.TALENTS:Demo.talents[id]=DemoConfig.TALENTS[id].max
	Demo.owned_global_upgrades=[]
	for id in AttachmentCatalog.DEFINITIONS:Demo.owned_global_upgrades.append(str(id))
	configure(118)
	var splitter=Utils.player.gun
	splitter.updateGun();aim(splitter)
	enemy(origin+Vector2(50,8),10000);enemy(origin+Vector2(90,8),10000)
	await wait(0.08);fragments.clear();LevelServer.state="COMBAT"
	splitter._shoot();await wait(0.4)
	check(fragments.size()==5 and fragments.all(func(f):return f.depth==1),"full account keeps exactly five first-generation fragments")
	print("B14_GROWTH_ROWS ",JSON.stringify(rows))
	print("B14_GROWTH_CHECKS ",checks," FAILURES ",failures)
	get_tree().quit.call_deferred(1 if failures else 0)
