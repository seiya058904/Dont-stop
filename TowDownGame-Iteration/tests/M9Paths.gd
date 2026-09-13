extends "res://tests/M8Runtime.gd"

func prepare(id):
	configure(id,false)
	Utils.player.set_process(false); Utils.player.set_physics_process(false)
	Utils.player.global_position = origin-Vector2(20,0)
	var gun = Utils.player.gun
	gun.global_rotation = 0; gun.gun_tip.global_position = origin; gun.direction = Vector2.RIGHT
	LevelServer.state = "COMBAT"
	return gun

func _ready():
	await boot()
	var prism = prepare(111)
	var targets = []
	for angle in [-0.1,0.0,0.1]: targets.append(enemy(origin+Vector2(200,0).rotated(angle)+Vector2(0,8),10000))
	var block = wall(origin+Vector2(100,0),Vector2(4,6))
	await wait(0.08)
	prism._shoot()
	check(targets[0].HP<10000 and targets[1].HP==10000 and targets[2].HP<10000,"prism side branches hit independently around central wall")
	var beams = get_tree().get_nodes_in_group("combat_transient").filter(func(n): return n.get_script()==load("res://game/effects/CombatEffect.gd"))
	check(beams.size()==9,"three prism branches each expose all three collision lanes")
	check(beams.filter(func(n): return n.points[-1].x<origin.x+105).size()==3,"only central prism lanes visually stop at wall")
	block.queue_free(); await clean()
	var shard = prepare(118)
	var mother = enemy(origin+Vector2(620,8),10000)
	var downstream = enemy(origin+Vector2(1220,8),10000)
	var beyond = enemy(origin+Vector2(1330,8),10000)
	for target in [mother,downstream,beyond]: target.knockback_def = 100000
	await wait(0.08)
	shard._shoot(); await wait(4.5)
	check(mother.HP<10000 and downstream.HP<10000,"fragment actually reaches beyond the mother projectile lifetime path")
	check(downstream.last_context.get("depth",0)==1 and beyond.HP==10000,"fragment depth and combined path outside boundary")
	await clean()
	var saw = prepare(122)
	var crossed = enemy(origin+Vector2(60,8),10000); crossed.knockback_def = 100000
	await wait(0.08); saw._shoot(); await wait(1.8)
	check(is_equal_approx(10000-crossed.HP,snappedf(saw.effective.damage,0.01)*2),"visible saw deals one outbound and one return hit")
	await clean()
	var rail = prepare(113)
	var row = []
	for i in 7:
		var target = enemy(origin+Vector2(30+i*30,8),10000); target.knockback_def = 100000; row.append(target)
	await wait(0.08)
	rail.handle_charge(true,1.2); rail.queue_redraw()
	check(rail.charging and rail.charge_time==rail.effective.warmup,"real rail charge state reaches visual ring limit")
	rail.handle_charge(false,0)
	check(row.slice(0,6).all(func(t): return t.HP<10000) and row[6].HP==10000,"charged rail stops damage at six targets")
	await clean()
	print("M9_PATHS checks=",checks," failures=",failures)
	if failures: get_tree().quit(1)
	else: await Demo.quit_game()
