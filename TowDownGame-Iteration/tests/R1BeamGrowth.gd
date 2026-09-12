extends Node
var failures = 0
func check(ok,name):
	if not ok: failures += 1
	print(("PASS " if ok else "FAIL ")+name)
func enemy(point,hp):
	var target = load("res://game/monster/Monster 2/Monster2.tscn").instantiate()
	target.global_position = point; target.HP = hp
	add_child(target); target.set_physics_process(false)
	return target
func _ready():
	process_mode = Node.PROCESS_MODE_ALWAYS
	Demo.test_mode = true
	add_child(load("res://game/map/Main.tscn").instantiate())
	Utils.gameStart()
	for i in 8: await get_tree().physics_frame
	Demo.try_purchase("weapon","0"); Demo.try_purchase("weapon","6")
	LevelServer.town.depart(1,true); LevelServer.timerStop()
	Utils.player.set_physics_process(false)
	Utils.player.global_position = Vector2(0,-1000)
	Utils.player.body.scale.x = 1
	var rifle = PlayerData.player_weapon_list[0]
	var laser = PlayerData.player_weapon_list[6]
	Utils.player.changeWeapon(0)
	PlayerData.player_exp = PlayerData.getMaxExp()-1
	var victim = enemy(Vector2(0,-1200),0.1)
	var target = enemy(laser.cast.to_global(Vector2(65,0))+Vector2(0,9),500)
	var bullet = rifle.bullet_scene.instantiate(); add_child(bullet)
	bullet.global_position = victim.global_position+Vector2(-50,-9); bullet.rotation = 0
	rifle.fire(bullet)
	Utils.player.changeWeapon(6)
	laser.rotation = 0
	Input.mouse_mode = Input.MOUSE_MODE_CONFINED_HIDDEN
	Demo.fire_released = true
	Input.action_press("shoot")
	var previous_hp = target.HP
	var recorded = []
	var start = Time.get_ticks_msec()
	while Time.get_ticks_msec()-start < 370:
		await get_tree().physics_frame
		if target.HP < previous_hp:
			recorded.append({"level":PlayerData.player_level,"damage":snappedf(previous_hp-target.HP,0.01)})
			previous_hp = target.HP
	Input.action_release("shoot"); Demo.stop_attacks()
	check(victim.is_die and PlayerData.player_level == 2 and Demo.rank("T10") == 0 and laser.attachments_dict.is_empty(),"R01 real in-flight kill upgrades during beam without T10 or attachments")
	var old_seen = false
	var new_seen = false
	for hit in recorded:
		if hit.level == 1 and is_equal_approx(hit.damage,laser.base_stats.damage+0.3): old_seen = true
		if hit.level == 2 and is_equal_approx(hit.damage,laser.base_stats.damage+0.6): new_seen = true
	check(old_seen and new_seen,"R01 subsequent actual beam ticks use upgraded damage within same .4s pulse")
	print("BEAM GROWTH hits=",JSON.stringify(recorded)," failures=",failures)
	LevelServer.return_to_camp()
	await Demo.quit_game()
