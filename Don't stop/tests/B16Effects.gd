extends "res://tests/M8Runtime.gd"

func _ready():
	await boot(); configure(113)
	LevelServer.state = "COMBAT"
	var before = Combat.heat_created
	for tick in 10:
		for i in 20: Combat.heat_contact(origin+Vector2(i*10,0))
	check(Combat.heat_created-before == 20,"200 repeated contacts allocate 20 effects")
	for i in 100: Combat.heat_contact(origin+Vector2(i*10,40))
	check(Combat.heat_cells.size() <= 32,"contact decoration cap never exceeds 32")
	await wait(0.3)
	check(Combat.heat_cells.is_empty(),"expired contact cache releases all weak references")
	var gun = Utils.player.gun
	aim(gun); gun.charge_time = gun.effective.warmup
	gun._shoot()
	var effects = get_tree().get_nodes_in_group("combat_transient").filter(func(n):return n.get_script() == load("res://game/effects/CombatEffect.gd") and n.segments.size()>0)
	check(effects.size() == 3,"three real rail beams use three visual batches")
	check(effects.all(func(n):return n.segments.size() == 7),"each batch retains seven independently clipped lanes")
	await clean()
	print("B16 EFFECTS checks=",checks," failures=",failures)
	get_tree().quit(1 if failures else 0)
