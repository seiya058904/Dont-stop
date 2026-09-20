extends "res://tests/M8Runtime.gd"

func _ready():
	await boot()
	configure(120); aim(Utils.player.gun)
	for i in 6: enemy(origin+Vector2(110+i*10,-35+i*15),10000)
	await wait(0.1); LevelServer.state = "COMBAT"
	Utils.player.gun._shoot()
	var missiles = get_tree().get_nodes_in_group("combat_transient").filter(func(n): return n.get_script()==load("res://game/bullets/MechanismProjectile.gd"))
	check(missiles.size()==6,"six real missiles per volley")
	var locks = {}
	for m in missiles:
		if m.target_ref: locks[m.target_ref.get_ref().get_instance_id()] = true
	check(locks.size()>=4,"salvo assigns multiple actual targets")
	await clean(); configure(113); aim(Utils.player.gun)
	var gun = Utils.player.gun
	gun.charge_time = gun.effective.warmup
	var targets = []
	for y in [-30,-23,-15,-6,0,6,15,23,30]: targets.append(enemy(origin+Vector2(180,y+8),10000))
	await wait(0.1); LevelServer.state = "COMBAT"
	gun._shoot()
	check(targets.all(func(t): return t.HP<10000),"three real wide rail beams cover interiors and sides")
	await clean(); configure(121); aim(Utils.player.gun)
	gun = Utils.player.gun
	LevelServer.state = "COMBAT"
	gun._shoot()
	var projectile = get_tree().get_nodes_in_group("combat_transient").filter(func(n): return n.get_script()==load("res://game/bullets/MechanismProjectile.gd"))[0]
	# Spatially valid test corridor; no fixed timer may terminate the projectile.
	projectile.set_physics_process(false)
	for i in 150: projectile._physics_process(1.0/60)
	check(is_instance_valid(projectile) and not projectile.is_queued_for_deletion() and not projectile.finished,"gravity survives 2.5 seconds without collision")
	projectile.gravity_field(); projectile.gravity_field()
	check(get_tree().get_nodes_in_group("combat_transient").filter(func(n): return n.get_script()==load("res://game/effects/GravityField.gd")).size()==1,"gravity collision field is idempotent")
	await clean(); configure(114)
	gun = Utils.player.gun
	var inside = enemy(origin+Vector2(43,0),10000)
	var outside = enemy(origin+Vector2(53,0),10000)
	await wait(0.1); LevelServer.state = "COMBAT"
	Combat.explosion_context(origin,gun.effective.radius,gun.shot_context())
	check(inside.HP<10000 and outside.HP==10000,"plasma real radius 48 inner and outer boundary")
	await clean(); configure(122)
	gun = Utils.player.gun
	check(gun.effective.rate>=4 and gun.effective.magazine/(gun.effective.magazine/gun.effective.rate+gun.effective.reload)>3.0,"saw base rate and full cycle throughput exceed doubled baseline")
	print("B15 WEAPONS checks=",checks," failures=",failures)
	await clean(); get_tree().quit(1 if failures else 0)
