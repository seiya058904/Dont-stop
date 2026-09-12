extends Node

var failures = 0
var checks = 0
var main
var town

func check(ok: bool, title: String):
	checks += 1
	if not ok: failures += 1
	print(("PASS " if ok else "FAIL ")+title)

func enemy(position: Vector2, hp = 20):
	var target = load("res://game/monster/Monster 2/Monster2.tscn").instantiate()
	target.HP = hp
	target.global_position = position
	add_child(target)
	target.set_physics_process(false)
	return target

func _ready():
	process_mode = Node.PROCESS_MODE_ALWAYS
	Demo.test_mode = true
	seed(721)
	main = load("res://game/map/Main.tscn").instantiate()
	add_child(main)
	town = main.get_node("Town")
	Utils.gameStart()
	for i in 8: await get_tree().physics_frame
	check(PlayerData.gold == 9999 and PlayerData.reward_point == 9999,"A01 new wallets")
	check(Utils.weapon_list.size() == 24 and Utils.am_dict.size() == 24,"E M3-M4 registered counts (M2 baseline 13/15 retained in history)")
	var exact = PlayerData.getMaxExp()
	PlayerData.player_exp = exact-1
	check(PlayerData.player_level == 1,"B01 threshold minus one")
	PlayerData.player_exp += 1
	check(PlayerData.player_level == 2 and PlayerData.player_exp == 0,"B01 exact threshold")
	var two_levels = PlayerData.getMaxExp()+pow(3,2.2)+15+3
	PlayerData.player_exp = two_levels
	check(PlayerData.player_level == 4 and is_equal_approx(PlayerData.player_exp,3),"B02 multiple levels retain overflow")
	PlayerData.player_exp = -1
	check(is_equal_approx(PlayerData.player_exp,3),"B negative XP rejected")
	var damage = PlayerData.player_damage
	PlayerData.player_level = PlayerData.player_level
	check(PlayerData.player_damage == damage,"B03 assigning level does not stack growth")
	PlayerData.player_level = 1
	PlayerData.player_exp = 0
	PlayerData.player_hp_max = 5
	PlayerData.player_hp = 5
	PlayerData.reward_point = 9999
	var result = Demo.try_purchase("weapon","0")
	check(result.success and PlayerData.gold == 9989,"A03 gold buys actual gun")
	var balance = PlayerData.gold
	check(not Demo.try_purchase("weapon","0").success and PlayerData.gold == balance,"A06 owned gun cannot charge twice")
	check(not Demo.try_purchase("weapon","invalid").success and PlayerData.gold == balance,"A12 invalid transaction")
	for id in Utils.weapon_list:
		if id != "0": check(Demo.try_purchase("weapon",id).success,"E acquire gun "+id)
	var gun = PlayerData.player_weapon_list[0]
	var original = gun.effective.duplicate()
	for id in ["T01","T03","T04","T10","T16","T24"]:
		var gold = PlayerData.gold
		var points = PlayerData.reward_point
		check(Demo.try_purchase("talent",id,"gold").success and PlayerData.gold == gold-100 and PlayerData.reward_point == points,"A07 talent gold "+id)
	var gold = PlayerData.gold
	var points = PlayerData.reward_point
	check(Demo.try_purchase("talent","T01","points").success and PlayerData.gold == gold and PlayerData.reward_point == points-1,"A08 talent points only")
	Demo.try_purchase("talent","T01","points")
	points = PlayerData.reward_point
	check(not Demo.try_purchase("talent","T01","points").success and PlayerData.reward_point == points,"A09 max talent free rejection")
	check(is_equal_approx(gun.effective.damage,original.damage*1.24),"B05 talent damage applies to effective combat snapshot")
	PlayerData.gold = 0
	check(not Demo.try_purchase("attachment","110").success and PlayerData.gold == 0,"A10 insufficient balance")
	Demo.replenish()
	var ranks = Demo.talents.duplicate()
	var owned_count = PlayerData.player_weapon_list.size()
	Demo.replenish()
	check(Demo.talents == ranks and PlayerData.player_weapon_list.size() == owned_count,"A11 replenish preserves content")
	var attachment_result = Demo.try_purchase("attachment","1")
	var am = PlayerData.player_am_list[attachment_result.instance_id]
	check(am.gun == null,"A13 purchased instance stays in backpack")
	var capacity = gun.bullets_max_count
	for iteration in 20:
		gun.addAttachMent(am)
		gun.removeAttachMent(am)
	check(gun.bullets_max_count == capacity,"A19 twenty equip/remove cycles no drift")
	gun.addAttachMent(am)
	var second = Demo.try_purchase("attachment","1")
	var am2 = PlayerData.player_am_list[second.instance_id]
	gun.addAttachMent(am2)
	check(am.gun == null and am.get_parent() == PlayerData and am2.gun == gun,"A16 same-slot replacement returns old item")
	var other = PlayerData.player_weapon_list[4]
	other.addAttachMent(am2)
	check(am2.gun == other and not gun.attachments_dict.values().has(am2),"A18 instance transfers between guns")
	check(am.id != am2.id,"A17 duplicate definitions unique instances")
	for id in ["110","112","114","117","121","122"]:
		var bought = Demo.try_purchase("attachment",id)
		var a = PlayerData.player_am_list[bought.instance_id]
		var yes = 0
		var no = 0
		for weapon in PlayerData.player_weapon_list.values():
			if a.can_equip(weapon): yes += 1
			else: no += 1
		check(yes > 0,"E attachment compatible "+id)
		if id != "114": check(no > 0,"E attachment rejects unsupported mechanism "+id)
		else: check(yes == 24,"A14 overload explicitly universal")
	var plasma = PlayerData.player_weapon_list[114]
	var fuse
	for a in PlayerData.player_am_list.values():
		if a.am_id == 121: fuse = a
	check(not gun.addAttachMent(fuse) and fuse.gun == null,"A15 incompatible installation cannot mutate")
	plasma.addAttachMent(fuse)
	check(is_equal_approx(plasma.effective.radius,38.4),"B explosion radius changes actual value")
	var save = Demo.snapshot()
	check(Demo.valid_save(save),"A20 structured camp snapshot accepted")
	check(not Demo.valid_save({"schema_version":1}),"save rejects partial schema")
	check(not Demo.valid_save("bad json"),"save rejects malformed document")
	var a_menu = Control.new()
	var b_menu = Control.new()
	add_child(a_menu)
	add_child(b_menu)
	Demo.push_pause(a_menu)
	Demo.push_pause(b_menu)
	Demo.pop_pause(b_menu)
	check(get_tree().paused and Demo.top_pause(a_menu),"D04 closing settings preserves inventory pause")
	Demo.pop_pause(a_menu)
	check(not get_tree().paused,"D04 last menu resumes")
	a_menu.queue_free()
	b_menu.queue_free()
	# The original 1.1s expectations remain for baseline comparison. M2-R1
	# explicitly replaces that product rule with <= .15s input debounce.
	if DemoConfig.SWITCH_SECONDS == 1.1:
		PlayerData.changeWeapon(0)
		PlayerData._physics_process(0.5)
		check(PlayerData.is_change_weapon,"D01 relative switch lock not global frame")
		PlayerData._physics_process(0.61)
		check(not PlayerData.is_change_weapon,"D01 documented animation duration releases switch")
	else:
		PlayerData.changeWeapon(4)
		check(PlayerData.is_change_weapon,"D01 relative input debounce active")
		while Time.get_ticks_msec() <= PlayerData.switch_deadline:
			await get_tree().process_frame
		PlayerData._physics_process(0)
		check(not PlayerData.is_change_weapon and DemoConfig.SWITCH_SECONDS <= 0.15,"D01 requested short input debounce releases independently of HUD")
	check(town.nav_ready and town.walkable.size() > 50,"E R1 navigation built from actual ground and physics")
	check(town.depart(1,true),"D11 first departure accepted")
	var camp_only_gold = PlayerData.gold
	var camp_only_instances = PlayerData.player_am_list.size()
	check(not Demo.try_purchase("attachment","110").success and PlayerData.gold == camp_only_gold and PlayerData.player_am_list.size() == camp_only_instances,"D camp purchases rejected during combat without charge")
	Demo.replenish()
	check(PlayerData.gold == camp_only_gold,"D camp refill unavailable during combat")
	var camp_only_targets = get_tree().get_nodes_in_group("monsters").size()
	town.practice()
	check(get_tree().get_nodes_in_group("monsters").size() == camp_only_targets,"D practice cannot inject targets during combat")
	check(not LevelServer.roundStart(),"D11 duplicate departure rejected")
	LevelServer.timerStop()
	var spawn = town.spawn_point()
	print("NAV cells=",town.walkable.size()," spawn=",spawn," hero=",Utils.player.global_position)
	check(spawn != Vector2.INF,"E R1 reachable safe spawning")
	for id in [1,3,4]:
		LevelServer.level = id
		for count in 8: town.monsterCreate()
	await get_tree().physics_frame
	var roles = {"E01":0}
	for e in get_tree().get_nodes_in_group("monsters"):
		if e.get_script().resource_path.ends_with("DemoEnemy.gd"): roles[e.role] = roles.get(e.role,0)+1
	check(roles.has_all(["E02","E04","E05"]),"E all three new enemy behaviors spawn in actual encounters")
	for e in get_tree().get_nodes_in_group("monsters"): e.queue_free()
	await get_tree().physics_frame
	# Controlled actual collisions, no input/UI or artificial success victory shortcut.
	Utils.player.global_position = Vector2(280,530)
	var laser = PlayerData.player_weapon_list[6]
	Utils.player.changeWeapon(6)
	var target = enemy(Vector2(320,521),200)
	var before = target.HP
	laser.bulletHurt(target)
	check(target.HP < before,"C04 laser damage applies without temporary Bullet")
	before = target.HP
	laser.bulletHurt(target)
	check(target.HP == before,"C04 same tick target deduplicated")
	laser._on_tick_timeout()
	laser.bulletHurt(target)
	check(target.HP < before,"C04 next tick applies")
	var orphans = Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)
	for tick in 60:
		laser._on_tick_timeout()
		laser.bulletHurt(target)
	check(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT) == orphans,"C14 sixty laser hits do not allocate orphan nodes")
	laser.bullets_count = 8
	laser.openFire()
	Demo.push_pause(self)
	check(not laser.is_cast and laser.tick.is_stopped() and not laser.audio.playing,"D03 pause stops beam tick audio")
	Demo.pop_pause(self)
	await get_tree().create_timer(0.45).timeout
	check(not laser.is_cast,"D10 old laser callback cannot reactivate")
	var burst = PlayerData.player_weapon_list[123]
	Utils.player.changeWeapon(123)
	burst.bullets_count = 1
	burst.direction = Vector2.RIGHT
	burst._shoot()
	await get_tree().create_timer(0.25).timeout
	check(burst.bullets_count == 0,"C12 burst with one remaining shot cannot go negative")
	burst.bullets_count = 6
	burst._shoot()
	burst.cancel_actions()
	await get_tree().create_timer(0.25).timeout
	check(burst.bullets_count == 5,"D10 interrupted burst cancels remaining shots")

	# Isolated physical fixture: real rays and projectiles, outside map obstacles.
	target.queue_free()
	await get_tree().physics_frame
	Utils.player.global_position = Vector2(0,-1000)
	var fixtures = []
	for point in [Vector2(45,-991),Vector2(65,-981),Vector2(85,-991),Vector2(105,-981),Vector2(125,-991)]:
		fixtures.append(enemy(point,50))
	await get_tree().physics_frame
	var arc = PlayerData.player_weapon_list[112]
	Utils.player.changeWeapon(112)
	arc.direction = Vector2.RIGHT
	var hit_before = Combat.damage_events
	Combat.arc(arc,Vector2(0,-1000),Vector2.RIGHT)
	check(Combat.damage_events-hit_before == 4,"C06 default arc hits initial plus three distinct targets")
	var relay
	for a in PlayerData.player_am_list.values():
		if a.am_id == 122: relay = a
	arc.addAttachMent(relay)
	hit_before = Combat.damage_events
	Combat.arc(arc,Vector2(0,-1000),Vector2.RIGHT)
	check(Combat.damage_events-hit_before == 5,"A22 relay adds one actual target")
	var wall = StaticBody2D.new()
	wall.collision_layer = 1
	var wall_shape = CollisionShape2D.new()
	wall_shape.shape = RectangleShape2D.new()
	wall_shape.shape.size = Vector2(8,100)
	wall.add_child(wall_shape)
	wall.position = Vector2(26,-1000)
	add_child(wall)
	await get_tree().physics_frame
	hit_before = Combat.damage_events
	Combat.arc(arc,Vector2(0,-1000),Vector2.RIGHT)
	check(Combat.damage_events == hit_before,"C06 arc initial ray stops at real wall")
	wall.queue_free()
	for fixture in fixtures: fixture.queue_free()
	await get_tree().physics_frame
	var inside = enemy(Vector2(30,-991),100)
	var outside = enemy(Vector2(50,-991),100)
	await get_tree().physics_frame
	hit_before = Combat.damage_events
	Combat.explosion(Vector2(0,-1000),38.4,5,plasma)
	check(Combat.damage_events == hit_before+1 and inside.HP == 95 and outside.HP == 100,"C08 explosion radius and same-target single damage")
	inside.queue_free()
	outside.queue_free()
	await get_tree().physics_frame
	for weapon in PlayerData.player_weapon_list.values():
		Utils.player.changeWeapon(weapon.weapon_id)
		weapon.bullets_count = weapon.bullets_max_count
		var ammo_before = weapon.bullets_count
		weapon.direction = Vector2.RIGHT
		weapon._shoot()
		await get_tree().create_timer(0.32).timeout
		check(weapon.bullets_count < ammo_before and weapon.bullets_count >= 0,"C actual firing and ammo use gun "+str(weapon.weapon_id))
		weapon.cancel_actions()
	for transient in get_tree().get_nodes_in_group("combat_transient"): transient.queue_free()
	await get_tree().physics_frame
	Utils.player.global_position = Vector2(280,530)
	Utils.player.changeWeapon(0)
	var victim = enemy(Vector2(290,550),0.5)
	var kills = Combat.kill_events
	var xp = PlayerData.player_exp
	Combat.hit(victim,gun.damage_context())
	victim.onDie()
	victim.onHit(50)
	check(Combat.kill_events == kills+1,"C15 one death one kill")
	check(PlayerData.player_exp == xp+1,"C15 one death one XP")
	check(Combat.max_depth_seen <= 2,"C16 derived depth bounded")
	var safe = enemy(Vector2(340,570),20)
	before = safe.HP
	check(not Combat.hit(safe,{"damage":100,"depth":3}),"C16 excessive depth rejected")
	check(safe.HP == before,"C16 rejected damage not applied")
	PlayerData.player_hp = 3
	Demo.heal_cooldown = 0
	Demo.blast_cooldown = 0
	victim = enemy(Vector2(285,560),0.5)
	Combat.hit(victim,gun.damage_context())
	check(PlayerData.player_hp > 3,"T24 direct kill heals")
	var hp = PlayerData.player_hp
	victim = enemy(Vector2(285,560),0.5)
	Combat.hit(victim,gun.damage_context(1))
	check(PlayerData.player_hp == hp,"T24 derived kill does not heal")
	check(Demo.kill_stacks > 0 and gun.effective.rate > gun.base_stats.rate,"T10 kill stacks affect actual rate")
	Demo._process(5)
	check(Demo.kill_stacks == 0,"T10 buff expires")
	LevelServer.level = 1
	LevelServer.level_time = 0.05
	gold = PlayerData.gold
	LevelServer._timeout()
	check(LevelServer.state == "CAMP" and PlayerData.gold == gold+20,"D07 timeout settles and returns camp")
	check(not LevelServer.victory() and PlayerData.gold == gold+20,"D07 repeated victory cannot reward")
	await get_tree().physics_frame
	var transient_count = get_tree().get_nodes_in_group("combat_transient").size()
	check(transient_count == 0,"D09 return clears encounter projectiles/effects")
	for stage in [3,4]:
		for menu in Demo.pause_stack.duplicate(): Demo.pop_pause(menu)
		check(town.depart(stage,true),"E start actual stage "+str(stage))
		LevelServer.timerStop()
		LevelServer.level_time = 0.01
		LevelServer._timeout()
		check(LevelServer.state == "CAMP","E resolve stage "+str(stage))
	for menu in Demo.pause_stack.duplicate(): Demo.pop_pause(menu)
	# Exercise actual viewport input, not only the pause service.
	for menu in Demo.pause_stack.duplicate():
		Demo.pop_pause(menu)
		menu.queue_free()
	for frame in 2: await get_tree().process_frame
	for cycle in 2:
		var key = InputEventKey.new()
		key.physical_keycode = KEY_TAB
		key.keycode = KEY_TAB
		key.pressed = true
		Input.parse_input_event(key.duplicate())
		for frame in 2: await get_tree().process_frame
		check(is_instance_valid(Demo.ui) and get_tree().paused,"D03 viewport Tab opens camp cycle " + str(cycle))
		key.pressed = false
		Input.parse_input_event(key.duplicate())
		Demo.open_settings()
		for frame in 2: await get_tree().process_frame
		key = InputEventKey.new()
		key.keycode = KEY_ESCAPE
		key.pressed = true
		Input.parse_input_event(key.duplicate())
		for frame in 2: await get_tree().process_frame
		check(Demo.pause_stack.size() == 1 and get_tree().paused,"D04 Esc closes only settings cycle " + str(cycle))
		key.pressed = false
		Input.parse_input_event(key.duplicate())
		key.pressed = true
		Input.parse_input_event(key.duplicate())
		for frame in 2: await get_tree().process_frame
		check(Demo.pause_stack.is_empty() and not get_tree().paused,"D04 next Esc resumes camp cycle " + str(cycle))
		key.pressed = false
		Input.parse_input_event(key.duplicate())
	print("CONTRACT SUMMARY checks=",checks," failures=",failures," damage_events=",Combat.damage_events)
	await get_tree().create_timer(0.6).timeout
	for kind in ["AudioStreamPlayer","AudioStreamPlayer2D"]:
		for player in get_tree().root.find_children("*",kind,true,false):
			player.stream_paused = false
			player.stop()
	await get_tree().create_timer(0.1).timeout
	get_tree().quit(1 if failures else 0)
