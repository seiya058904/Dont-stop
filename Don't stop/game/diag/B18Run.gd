extends "res://game/diag/B11Stress.gd"
# Explicit isolated measurement only; all normal gameplay remains in the base game.
var population := []
var gauge_clock := 0.0
var simulation := 0.0
var stop_boss_at_limit := true
var capacity_shots := 0

func _apply_scenario():
	if scenario != "capacity":
		super._apply_scenario()
		return
	for arg in OS.get_cmdline_args()+OS.get_cmdline_user_args():
		if arg.begins_with("--b18-shots="): capacity_shots = clampi(int(arg.substr(12)),0,512)
	DemoConfig.ENCOUNTERS[stage].cap = maxi(enemies,DemoConfig.ENCOUNTERS[stage].cap)
	preload("res://game/monster/EnemyShot.gd").capacity_limit = maxi(180,capacity_shots)
	print("B18_CAPACITY enemies=",enemies," shots=",capacity_shots," technical high-HP top-up; not survival")

func top_up_capacity():
	var town = LevelServer.town
	if not is_instance_valid(town) or not is_instance_valid(town.arena): return
	var live = M5Content.living_mix(get_tree()).ordinary
	for i in mini(30,maxi(0,enemies-live)):
		var point = town.spawn_near(Utils.player.global_position,65.0,105.0,M5Content.radius_for("E01"))
		if not point.is_finite(): continue
		var actor = M5Content.spawn("E01",town.monster_root,point,true)
		if actor: actor.HP = 100000.0
	var shot_script = preload("res://game/monster/EnemyShot.gd")
	for i in maxi(0,capacity_shots-shot_script.live_count):
		var direction = Vector2.RIGHT.rotated(float(i)*2.399963)
		var point = Utils.player.global_position+direction*85.0
		if not town.arena.point_clear(point,4.0,[],2147483648): continue
		var pellet = shot_script.new(); pellet.position = point
		pellet.velocity = direction.orthogonal()*65.0; pellet.bounces_left = 2; pellet.style = "ricochet"
		get_tree().current_scene.add_child(pellet)

func release_after_switch():
	Input.action_release("shoot")
	await get_tree().process_frame
	await get_tree().process_frame

func _drive_movement(_now: int):
	super._drive_movement(int(simulation*1000.0))

func _process(delta):
	if LevelServer.state != "COMBAT": return
	simulation += delta
	if (stop_boss_at_limit and stage%10 == 0 or scenario == "capacity") and simulation >= seconds:
		_total_combat_s = seconds
		LevelServer.return_to_camp()
		return
	if stage%10 == 0:
		var boss = instance_from_id(LevelServer.boss_instance)
		if is_instance_valid(boss):
			Utils.aim_override = get_viewport().get_canvas_transform()*(boss.global_position-Vector2(0,8))
	gauge_clock += delta
	if gauge_clock < 0.25: return
	gauge_clock = 0.0
	if scenario == "capacity": top_up_capacity()
	var ordinary = 0
	var visible_ordinary = 0
	var giant = 0
	var enchanted = 0
	var screen = get_viewport().get_visible_rect()
	var nearest = null
	var nearest_distance = INF
	for actor in get_tree().get_nodes_in_group("monsters"):
		if actor.is_die or actor.training or actor.is_queued_for_deletion(): continue
		var distance = actor.global_position.distance_squared_to(Utils.player.global_position)
		if distance < nearest_distance:
			nearest = actor; nearest_distance = distance
		if actor.get_meta("content_id","") in ["E01","E02"] and not actor.is_elite:
			ordinary += 1
			if screen.has_point(actor.get_global_transform_with_canvas().origin): visible_ordinary += 1
		if actor.get_meta("giant",false): giant += 1
		if actor.get_meta("enchantment",0)>0: enchanted += 1
	if is_instance_valid(nearest) and stage%10 != 0:
		Utils.aim_override = get_viewport().get_canvas_transform()*(nearest.global_position-Vector2(0,8))
	population.append({"t":simulation,"ordinary":ordinary,"screen":visible_ordinary,"giant":giant,"enchanted":enchanted,"shots":get_tree().get_nodes_in_group("enemy_projectiles").size(),"damage":Combat.damage_events,"kills":Combat.kill_events,"fire_released":Demo.fire_released,"mouse":Utils.is_gameplay_mouse_mode(),"ammo":Utils.player.gun.bullets_count if Utils.player.gun else -1})

func _grant_everything():
	super._grant_everything()
	# Camp microbenchmark: identical real on_kill path, 24 owned weapons, capped T10.
	# Derived context suppresses unrelated native-only rewards; no synthetic gameplay claim.
	Demo.kill_stacks = DemoConfig.TALENTS.T10.stacks
	Demo.refresh()
	var before = B11Probe.refresh_calls
	var started = Time.get_ticks_usec()
	for i in 200: Demo.on_kill({"training":false},{"native_attack":false})
	print("B18_REFRESH ",JSON.stringify({"kills":200,"refreshes":B11Probe.refresh_calls-before,"usec":Time.get_ticks_usec()-started,"weapons":PlayerData.player_weapon_list.size()}))
	Demo.kill_stacks = 0; Demo.stack_time = 0; Demo.refresh()

func _dump():
	super._dump()
	print("B18_OBSERVATION ",JSON.stringify({"population":population,"refresh_calls":B11Probe.refresh_calls,"refresh_usec":B11Probe.refresh_usec,"simulation":simulation,"damage_events":Combat.damage_events,"kills":Combat.kill_events}))
