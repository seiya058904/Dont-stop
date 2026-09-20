extends "res://tests/M8Runtime.gd"

func _ready():
	await boot(); configure(0)
	var battery = RewardServer.reward_list["9"].instantiate()
	check(RewardServer.addReward(battery),"battery first layer")
	for i in 2: RewardServer.addReward(RewardServer.reward_list["9"].instantiate())
	battery.is_time_out = true
	check(is_equal_approx(battery.beforeAtk(null,10),15),"independent battery 3 x 50% x 10 = 15 bonus")
	check(not RewardServer.addReward(RewardServer.reward_list["9"].instantiate()),"fourth battery rejected")
	battery.count = 8
	battery.is_time_out = true
	check(battery.count==8 and is_equal_approx(battery.beforeAtk(null,10),15),"historical count preserved; effective bonus capped")
	Utils.player.gun.set_use(false)
	Utils.player.gun = null
	var panel = load("res://ui/StatPanel.gd").new()
	play_view.add_child(panel)
	for tab_name in ["build","player","weapon","effects","level"]:
		panel.tab = tab_name; panel.render()
		check(not panel.snapshot.player.is_empty(),"empty hand retains player snapshot "+tab_name)
	check(panel.snapshot.weapon.is_empty(),"empty hand has no fabricated weapon")
	panel.queue_free(); await wait(0.1)
	var canvas = load("res://game/map/FogPierceCanvas.gd").new()
	add_child(canvas)
	for i in 180:
		canvas.offer({"kind":"line","a":Vector2(i,0),"b":Vector2(i,14),"color":Color.WHITE,"width":2})
		canvas.offer({"kind":"line","a":Vector2(i,0),"b":Vector2(i,14),"color":Color.WHITE,"width":1,"decorative":true})
	canvas.offer({"kind":"circle","a":Vector2.ZERO,"radius":60,"color":Color.RED,"width":3})
	check(canvas.entries.size()==181 and canvas.decorations.size()==128,"all 180 bullets and late meteor survive cosmetic saturation")
	canvas.offer({"kind":"circle","a":Vector2.ZERO,"radius":60,"color":Color.RED,"width":3})
	check(canvas.entries.size()==181,"same physics frame geometry deduplicates")
	await wait(0.05)
	check(canvas.entries.is_empty(),"producer stop clears cached fog geometry")
	canvas.queue_free()
	var pattern = load("res://game/monster/EnemyBarrage.gd").new()
	pattern.kind = "ring"
	for n in [20,24,32,40,48,64]:
		pattern.count=n
		var angles=pattern.angles()
		var nearest=float(angles[0])
		check(2*80*sin(nearest)>24,"ring escape chord exceeds swept hit diameter at R80 N"+str(n))
	pattern.free()
	check("burst" in load("res://game/monster/TacticalEnemy.gd").BOSS_CYCLES["3"]["B04"],"B04 phase 3 schedules barrage")
	print("B17 CONTRACTS checks=",checks," failures=",failures)
	get_tree().quit(1 if failures else 0)
