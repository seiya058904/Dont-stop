extends "res://tests/M8Runtime.gd"

func _ready():
	await boot()
	var amounts = []
	for boosted in [false,true]:
		await clean()
		Demo.talents = {"T12":1,"T22":1} if boosted else {}
		configure(112)
		var gun = Utils.player.gun
		gun.updateGun(); aim(gun); gun.effective.crit = 0
		var target = enemy(origin+Vector2(50,8),10000)
		await wait(0.1)
		LevelServer.state = "COMBAT"
		if boosted:
			gun.bullets_count = 0; gun.reload_ammo()
			await wait(gun.effective.reload+0.1)
		Demo.crowd_active = boosted
		gun._shoot()
		amounts.append(10000-target.HP)
		print("ARC_DAMAGE boosted=",boosted," amount=",amounts[-1])
	check(amounts[1] > amounts[0]*1.1,"real arc uses reload first round and crowd damage")
	Demo.talents = {}; Demo.crowd_active = false
	await clean(); configure(112)
	var gun = Utils.player.gun
	gun.updateGun(); aim(gun); gun.effective.crit = 0
	var targets = []
	for i in 10: targets.append(enemy(origin+Vector2(60+(i%4)*30,-25+(i/4)*30),10000))
	await wait(0.1); LevelServer.state = "COMBAT"
	var events = Combat.damage_events
	gun._shoot()
	check(targets.filter(func(t): return t.HP<10000).size() >= 8,"arc damages at least eight distinct targets")
	check(Combat.damage_events-events <= 12,"single discharge deduplicates its targets")
	var discharge=get_tree().get_nodes_in_group("combat_transient").filter(func(n): return n.get_script()==load("res://game/effects/ArcDischarge.gd"))[-1]
	check(discharge.edges.size()==discharge.contacts.size() and discharge.contacts.size()==targets.filter(func(t):return t.HP<10000).size(),"rendered arc graph corresponds to successful real hits")
	await clean()
	print("B15 ARC checks=",checks," failures=",failures)
	get_tree().quit(1 if failures else 0)
