extends "res://tests/M8Runtime.gd"

const SHOT = preload("res://game/monster/EnemyShot.gd")

func clear_attacks(actor):
	for ref in actor.owned_attacks:
		if is_instance_valid(ref.get_ref()): ref.get_ref().queue_free()
	actor.owned_attacks.clear()
	await wait(0.05)

func _ready():
	await boot(); configure(112)
	LevelServer.return_to_camp(); dismiss(); await wait(0.1)
	LevelServer.level = 39; LevelServer.state = "COMBAT"; LevelServer.timerStop()
	PlayerData.player_hp_max = 10000; PlayerData.player_hp = 10000
	var player = Utils.player
	var at: Vector2 = LevelServer.town.global_position+Vector2(0,-40)
	player.global_position = at
	check(not player.has_method("apply_root"),"immobilization API removed")
	check(player.get("root_remaining") == null and player.get("cc_immunity") == null,"control timers removed")
	check(not preload("res://game/monster/B19EnchantmentLayer.gd").SHOW_HEALTH_BARS,"enemy health bars remain hidden")
	for stage in range(1,41):
		var plan = ArenaHazards.plan(stage)
		check(plan.is_empty() if stage < 21 else plan.kinds == ["meteor"],"arena plan %d has only the allowed hazard" % stage)

	# Real ordinary and elite emitters: unchanged recovery, count, speed and damage.
	for id in ["E10","E13"]:
		var actor = M5Content.spawn(id,LevelServer.town.monster_root,at+Vector2(160,0))
		actor.set_physics_process(false)
		for elite in [false,true]:
			actor.is_elite = elite
			actor.set_meta("elite_modifier",("volley_artillery" if id == "E10" else "double_shot") if elite else "")
			actor.attack_kind = "artillery" if id == "E10" else "tremor"
			actor.locked_direction = Vector2.LEFT
			actor.perform_attack()
			if id == "E10":
				var pattern = actor.owned_attacks[-1].get_ref()
				pattern.set_physics_process(false)
				check(pattern.count == (12 if elite else 6) and pattern.waves == 1,"E10 retains pellet count and wave")
				check(pattern.speed == 140 and is_equal_approx(pattern.interval,0.28) and is_equal_approx(actor.phase_time,0.9),"E10 retains speed and cadence")
				pattern._physics_process(0.01)
				check(pattern.next_wave == 1 and pattern.planned == 0,"E10 really emits its complete wave")
			else:
				var shots = get_tree().get_nodes_in_group("enemy_projectiles")
				check(shots.size() == (2 if elite else 1),"E13 retains ordinary/elite projectile count")
				check(shots.all(func(s): return is_equal_approx(s.velocity.length(),150) and s.style == "projectile"),"E13 ordinary pellets retain speed")
				check(is_equal_approx(actor.phase_time,1.4),"E13 retains recovery")
			await clear_attacks(actor)
		actor.queue_free(); await wait(0.05)

	var boss = M5Content.spawn("B02",LevelServer.town.monster_root,at+Vector2(160,0))
	boss.set_physics_process(false)
	boss.continuous_barrage.set_physics_process(false)
	boss.phase_two = true; boss.phase_three = true
	boss.locked_direction = Vector2.LEFT; boss.locked_point = at
	boss._begin("fan_shot")
	var zone = boss.owned_attacks[-1].get_ref()
	zone.set_physics_process(false)
	check(zone.style == "projectile" and zone.radius == 150 and is_equal_approx(zone.angle,0.85),"B02 fan retains warned footprint with ordinary ink")
	check(zone.get("control") == null,"zone has no control payload")
	boss.perform_attack()
	var pattern = boss.owned_attacks[-1].get_ref()
	pattern.set_physics_process(false)
	check(pattern.count == 9 and pattern.waves == 3 and pattern.speed == 120,"B02 retains all 27 pellets and speed")
	check(is_equal_approx(pattern.interval,0.25) and is_equal_approx(pattern.damage,0.55*1.3*0.45),"B02 retains interval and direct damage budget")
	check(pattern.style == "projectile" and pattern.get("control") == null,"barrage has ordinary ink and no control payload")
	await clear_attacks(boss)

	# A landed projectile still hurts, but repeated hits cannot stop movement or dash.
	var hp: float = PlayerData.player_hp
	for i in 3:
		var shot = boss.shot(Vector2.LEFT,120,0.35,false)
		check(shot.hit_segment(player.global_position-Vector2(4,0),player.global_position+Vector2(4,0)),"ordinary projectile reaches real hit path")
	check(PlayerData.player_hp < hp,"converted hits retain real damage")
	var before: Vector2 = player.global_position
	Input.action_press("right"); await wait(0.15)
	check(player.global_position.distance_to(before) > 1,"player moves immediately after repeated hits")
	Input.action_press("dash")
	var event = InputEventAction.new(); event.action = "dash"; event.pressed = true
	player._input(event)
	check(player.is_dash,"dash remains available after hits")
	Input.action_release("dash"); Input.action_release("right")
	await wait(0.1)
	check(preload("res://game/config/CombatStatus.gd").entries().all(func(row): return not "束缚" in row.name),"HUD status has no immobilization")
	check(not Demo.has_method("root_lesson"),"camp cannot open removed training")
	LevelServer.return_to_camp(); dismiss(); await wait(0.1)
	check(SHOT.live_count == 0,"camp drains converted projectiles")
	print("B194_COMBAT checks=",checks," failures=",failures)
	if failures: get_tree().quit(1)
	else: await Demo.quit_game()
