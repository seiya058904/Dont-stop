extends Node
var checks = 0
var failures = 0
var laser
var target
func check(ok,name):
	checks += 1
	if not ok: failures += 1
	print(("PASS " if ok else "FAIL ")+name)
func wait(seconds):
	await get_tree().create_timer(seconds,true).timeout
func shooting(value):
	if value: Input.action_press("shoot")
	else:
		Input.action_release("shoot")
		Demo.fire_released = false
func start_beam():
	Utils.player.changeWeapon(6)
	Utils.player.set_physics_process(false)
	laser.rotation = 0
	laser.bullets_count = laser.bullets_max_count
	laser.cancel_actions()
	Input.mouse_mode = Input.MOUSE_MODE_CONFINED_HIDDEN
	Demo.fire_released = true
	shooting(true)
func _ready():
	process_mode = Node.PROCESS_MODE_ALWAYS
	Demo.test_mode = true
	add_child(load("res://game/map/Main.tscn").instantiate())
	Utils.gameStart(); PlayerData.gold = 100000; PlayerData.reward_point = 9999
	await wait(0.2)
	for id in Utils.weapon_list: Demo.try_purchase("weapon",id)
	Demo.try_purchase("talent","T10","points")
	Demo.try_purchase("attachment","9")
	Demo.try_purchase("attachment","114")
	var launcher = PlayerData.player_am_list.values()[0]
	var overload = PlayerData.player_am_list.values()[1]
	var rifle = PlayerData.player_weapon_list[0]
	rifle.addAttachMent(launcher)
	for gun in PlayerData.player_weapon_list.values():
		check(gun.audio.bus == "SFX" and gun.audio_reload_ammo.bus == "SFX","R07 original/new gun and reload route "+str(gun.weapon_id))
	check(LevelServer.town.get_node("Kill").bus == "SFX" and launcher.get_node("AudioStreamPlayer2D").bus == "SFX","R07 old kill and grenade launcher route")
	Demo.set_volume("SFX",0)
	check(AudioServer.is_bus_mute(AudioServer.get_bus_index("SFX")) and not AudioServer.is_bus_mute(AudioServer.get_bus_index("UI")),"R07 SFX mute retains UI bus")
	Demo.set_volume("Master",0)
	check(AudioServer.is_bus_mute(0),"R07 master mute applies to grouped child buses")
	Demo.set_volume("Master",80); Demo.set_volume("SFX",80)
	LevelServer.town.depart(1,true); LevelServer.timerStop()
	Utils.player.global_position = Vector2(0,-1000)
	laser = PlayerData.player_weapon_list[6]
	target = load("res://game/monster/Monster 2/Monster2.tscn").instantiate()
	target.HP = 500
	add_child(target)
	target.set_physics_process(false)
	Utils.player.changeWeapon(6)
	target.global_position = laser.cast.to_global(Vector2(65,0))+Vector2(0,9)
	await wait(0.05)
	start_beam()
	var damage_start = Combat.damage_events
	await wait(0.34)
	check(Combat.damage_events-damage_start >= 3,"V02 held laser real ray hits across 0.1s ticks")
	check(is_equal_approx(laser.tick.wait_time,0.1) and laser.is_cast,"V02 original .1 tick and .4 pulse active at .34")
	shooting(false)
	await wait(0.15)
	check(not laser.is_cast and not laser.audio.playing,"V02 original pulse ends after .4s")
	for reason in ["pause","switch","equip","death","camp"]:
		start_beam(); await wait(0.06)
		match reason:
			"pause": Demo.push_pause(self)
			"switch": PlayerData.switch_deadline = 0; PlayerData.changeWeapon(0)
			"equip": laser.addAttachMent(overload)
			"death": PlayerData.player_hp = 0
			"camp": LevelServer.return_to_camp()
		shooting(false)
		var count = Combat.damage_events
		await wait(0.18)
		check(not laser.is_cast and not laser.audio.playing and not laser.particles_end.emitting and Combat.damage_events == count,"V02 stop damage audio particles on "+reason)
		for menu in Demo.pause_stack.duplicate(): Demo.pop_pause(menu); if menu != self: menu.queue_free()
		if Utils.player.is_dead:
			PlayerData.resurrectPlayer(PlayerData.player_hp_max,100)
			LevelServer.state = "COMBAT"
		await wait(0.15)
	if LevelServer.state != "CAMP": LevelServer.return_to_camp()
	await wait(0.05)
	# Five actual direct deaths activate the purchased legal fire-rate talent.
	LevelServer.town.depart(1,true); LevelServer.timerStop()
	Utils.player.global_position = Vector2(0,-1000)
	for i in 5:
		var victim = load("res://game/monster/Monster 2/Monster2.tscn").instantiate()
		victim.HP = 0.1; victim.global_position = Vector2(150+i*20,-1000)
		add_child(victim); victim.set_physics_process(false)
		Combat.hit(victim,{"damage":1})
	check(Demo.kill_stacks == 5 and laser.effective.rate > laser.base_stats.rate,"V02 legitimate T10 kill fire-rate bonus")
	target = load("res://game/monster/Monster 2/Monster2.tscn").instantiate()
	target.HP = 500; add_child(target); target.set_physics_process(false)
	start_beam(); target.global_position = laser.cast.to_global(Vector2(65,0))+Vector2(0,9)
	damage_start = Combat.damage_events
	await wait(1.8)
	shooting(false)
	check(Combat.damage_events-damage_start >= 6,"V02 sustained real beam with legal increased pulse rate")
	Demo.stop_attacks()
	Utils.player.changeWeapon(0)
	var right = InputEventMouseButton.new(); right.button_index = MOUSE_BUTTON_RIGHT; right.pressed = true
	Input.mouse_mode = Input.MOUSE_MODE_CONFINED_HIDDEN
	Input.parse_input_event(right)
	await wait(0.05)
	var grenades = get_tree().get_nodes_in_group("combat_transient").filter(func(n): return n.get_script() == load("res://game/other/Grenade.gd"))
	check(grenades.size() == 1,"V02 original right-click grenade creates actual projectile")
	if not grenades.is_empty(): check(grenades[0].get_node("AudioStreamPlayer2D").bus == "SFX","R07 old grenade explosion SFX route")
	right.pressed = false; Input.parse_input_event(right)
	Demo.push_pause(self)
	check(not launcher.get_node("AudioStreamPlayer2D").playing,"R07 attachment audio stops when paused")
	Demo.pop_pause(self)
	LevelServer.return_to_camp(); await wait(0.1)
	check(get_tree().get_nodes_in_group("combat_transient").is_empty(),"V02 grenade and beam effects cleared at camp")
	print("R1 TIMELINE checks=",checks," failures=",failures)
	await Demo.quit_game()
