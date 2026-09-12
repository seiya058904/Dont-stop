extends Node
var checks = 0
var failures = 0
var origin = Vector2(0,-2000)
func check(ok, title):
	checks += 1
	if not ok: failures += 1
	print(("PASS " if ok else "FAIL ")+title)
func wait(seconds):
	await get_tree().create_timer(seconds).timeout
func enemy(pos, hp = 100.0):
	var target = load("res://game/monster/Monster 2/Monster2.tscn").instantiate()
	target.position = pos
	target.HP = hp
	add_child(target)
	target.set_physics_process(false)
	return target
func wall(pos, size):
	var body = StaticBody2D.new()
	body.collision_layer = 2147483648
	var shape = CollisionShape2D.new()
	var rectangle = RectangleShape2D.new()
	rectangle.size = size
	shape.shape = rectangle
	body.add_child(shape)
	add_child(body)
	body.position = pos
	return body
func clean():
	for group in ["monsters","combat_transient"]:
		for node in get_tree().get_nodes_in_group(group): node.queue_free()
	await wait(0.1)
func aim(gun):
	Utils.player.changeWeapon(gun.weapon_id)
	Utils.player.set_physics_process(false)
	Utils.player.set_process(false)
	gun.set_process(false)
	gun.direction = Vector2.RIGHT
	gun.global_rotation = 0
	gun.gun_tip.global_position = origin
	gun.bullets_count = gun.bullets_max_count
	gun.is_reloading = false
func _ready():
	Demo.test_mode = true
	seed(317)
	var main = load("res://game/map/Main.tscn").instantiate()
	add_child(main)
	Utils.gameStart()
	await wait(0.2)
	Utils.player.global_position = origin-Vector2(100,0)
	for id in WeaponCatalog.DEFINITIONS:
		LevelServer.state = "CAMP"
		check(Demo.try_purchase("weapon",str(id)).success,"purchase "+str(id))
		var gun = PlayerData.player_weapon_list[id]
		aim(gun)
		LevelServer.state = "COMBAT"
		var target = enemy(origin+Vector2(50,8))
		await wait(0.06)
		var count = gun.bullets_count
		gun._shoot()
		await wait(1.5 if id == 121 else 0.65)
		check(target.HP < 100,"real firing collision damage "+str(id))
		check(gun.bullets_count == count-1,"single group consumes once "+str(id))
		gun.bullets_count = 0
		gun._shoot()
		check(gun.bullets_count == 0,"empty firing safe "+str(id))
		PlayerData.player_ammo = 1000
		gun.reload_ammo()
		await wait(gun.effective.reload+0.1)
		check(gun.bullets_count > 0,"real timed reload "+str(id))
		Demo.push_pause(self)
		count = gun.bullets_count
		gun._shoot()
		check(gun.bullets_count == count,"pause stops firing "+str(id))
		Demo.pop_pause(self)
		await clean()
	# Reflect off a vertical wall into a target behind the muzzle.
	var ricochet = PlayerData.player_weapon_list[117]
	aim(ricochet)
	var barrier = wall(origin+Vector2(60,0),Vector2(4,120))
	var reflected = enemy(origin+Vector2(-40,8))
	await wait(0.06)
	ricochet._shoot()
	await wait(0.6)
	check(reflected.HP < 100,"ricochet actual reflected collision")
	barrier.queue_free()
	await clean()
	# Mother hit, then distinct downstream target receives fragments.
	var shardgun = PlayerData.player_weapon_list[118]
	aim(shardgun)
	var mother_target = enemy(origin+Vector2(35,8))
	var fragment_target = enemy(origin+Vector2(70,8))
	await wait(0.06)
	shardgun._shoot()
	await wait(0.4)
	check(mother_target.HP < 100 and fragment_target.HP < 100,"mother and fragment actual distinct hits")
	check(fragment_target.last_context.get("depth",0) == 1,"fragment depth one")
	await clean()
	var missile = PlayerData.player_weapon_list[120]
	aim(missile)
	var lock = enemy(origin+Vector2(180,30))
	await wait(0.06)
	missile._shoot()
	lock.queue_free()
	await wait(2.2)
	check(get_tree().get_nodes_in_group("combat_transient").is_empty(),"dead homing target safely expires")
	aim(ricochet)
	var corner1 = wall(origin+Vector2(6,0),Vector2(3,40))
	var corner2 = wall(origin-Vector2(6,0),Vector2(3,40))
	await wait(0.06)
	ricochet._shoot()
	await wait(2.3)
	check(get_tree().get_nodes_in_group("combat_transient").is_empty(),"corner finite bounces and lifetime")
	corner1.queue_free(); corner2.queue_free()
	await clean()
	LevelServer.return_to_camp()
	await wait(0.4)
	check(get_tree().get_nodes_in_group("combat_transient").is_empty(),"camp cleanup")
	print("M3 SUMMARY checks=",checks," failures=",failures)
	await get_tree().create_timer(0.15).timeout
	get_tree().quit.call_deferred(1 if failures else 0)
