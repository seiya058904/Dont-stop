extends "res://tests/M3Weapons.gd"
var running = false
var gun
var tick_count = 0
func _process(delta):
	if not running: return
	if gun.has_method("handle_thermal"):
		gun.handle_thermal(true,delta)
	elif gun.can_shoot:
		gun.can_shoot = false; gun.timer.start(); gun._shoot()
		tick_count += 1
func _ready():
	Demo.test_mode = true
	var main = load("res://game/map/Main.tscn").instantiate()
	add_child(main)
	Utils.gameStart(); PlayerData.gold = 100000; PlayerData.reward_point = 9999
	await wait(0.2)
	Demo.try_purchase("weapon","116")
	gun = PlayerData.player_weapon_list[116]
	Utils.player.global_position = origin-Vector2(100,0)
	LevelServer.state = "COMBAT"
	aim(gun)
	gun.set_physics_process(false)
	var target = enemy(origin+Vector2(40,8)); target.training = true
	await wait(0.05)
	var results = []
	var original_local = gun.position
	for fps in [30,160]:
		Engine.max_fps = fps
		gun.cancel_actions()
		gun.bullets_count = 70
		tick_count = 0
		running = true
		await wait(2.0)
		running = false
		results.append(70-gun.bullets_count)
		print("THERMAL local gun position before=",original_local," after=",gun.position)
		print("THERMAL fps=",fps," actual_ticks=",70-gun.bullets_count)
		await wait(0.2)
		check(gun.position.distance_to(original_local) < 0.01,"local gun returns to same resting anchor at "+str(fps))
	check(absi(results[0]-results[1]) <= 1 and mini(results[0],results[1]) >= 19,"fixed tick throughput independent of process FPS")
	for stop in ["release","pause","switch","reload","death","camp"]:
		aim(gun)
		gun.set_physics_process(false)
		gun.handle_thermal(true,0.09)
		match stop:
			"release": gun.handle_thermal(false,0)
			"pause": Demo.push_pause(self); Demo.pop_pause(self)
			"switch": gun.set_use(false); gun.set_use(true); gun.set_process(false); gun.set_physics_process(false)
			"reload": gun.bullets_count -= 1; gun.reload_ammo(); gun.cancel_actions()
			"death": Utils.player.onHit(PlayerData.player_hp+1); Utils.player.is_dead = false; PlayerData.player_hp = PlayerData.player_hp_max
			"camp": LevelServer.return_to_camp()
		var count = gun.bullets_count
		LevelServer.state = "COMBAT"
		gun.handle_thermal(true,0.02)
		check(gun.bullets_count == count,"thermal accumulator cancelled "+stop)
		gun.cancel_actions()
	await clean()
	await wait(1.5)
	print("M4 THERMAL SUMMARY checks=",checks," failures=",failures)
	get_tree().quit.call_deferred(1 if failures else 0)
