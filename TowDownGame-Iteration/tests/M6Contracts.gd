extends "res://tests/M3Weapons.gd"
func dismiss():
	for panel in Demo.pause_stack.duplicate(): Demo.pop_pause(panel); panel.queue_free()
func _ready():
	Demo.test_mode = true; seed(606)
	var main = load("res://game/map/Main.tscn").instantiate(); add_child(main); Utils.gameStart(); PlayerData.gold = 100000; PlayerData.reward_point = 9999; await wait(0.3)
	Demo.try_purchase("weapon","117")
	Utils.player.set_process(false); Utils.player.set_physics_process(false)
	# Same-size membership replacement used to leave the previous actor RID cached.
	LevelServer.state = "COMBAT"
	var first = enemy(Vector2(0,-2000)); await wait(0.03)
	Combat.clear_line(Vector2(-50,-2000),Vector2(50,-2000))
	var old_rid = first.get_rid(); first.free()
	var second = enemy(Vector2(0,-2000)); await wait(0.03)
	check(Combat.clear_line(Vector2(-50,-2000),Vector2(50,-2000)),"replacement actor excluded from world ray")
	check(second.get_rid() in Combat.actor_exclusions and not old_rid in Combat.actor_exclusions,"same-count replacement refreshes RID identity")
	second.flash_time = 0.08; await wait(0.02)
	check(second.anim.material.get_shader_parameter("flash") == 0.7,"contact flash activates")
	await wait(0.15)
	check(second.anim.material.get_shader_parameter("flash") == 0.0 and second.anim.scale == Vector2.ONE,"cached visual resets after flash")
	await clean(); LevelServer.return_to_camp(); dismiss(); await wait(0.2)
	for stage in [10,20,30]:
		for scenario in ["phase","overkill","double-death","abandon"]:
			PlayerData.resurrectPlayer(PlayerData.player_hp_max,100); LevelServer.state = "CAMP"; dismiss()
			check(LevelServer.town.depart(stage,true),"boss restart "+str(stage)+"/"+scenario); await wait(0.8)
			var boss = instance_from_id(LevelServer.boss_instance)
			check(is_instance_valid(boss),"boss actual instance")
			if scenario == "phase":
				boss.armor = 0
				boss.summon(2)
				boss.locked_direction = Vector2.RIGHT
				var warning = boss.zone("circle",Utils.player.global_position,40,1.0); warning.damage = 0
				var hp = PlayerData.player_hp
				Demo.push_pause(self); await wait(0.2)
				check(warning.elapsed == 0 and PlayerData.player_hp == hp,"pause freezes zero damage warning")
				Demo.pop_pause(self)
				Combat.hit(boss,{"damage":boss.max_hp*0.55,"epoch":LevelServer.epoch}); await wait(0.1)
				check(boss.phase_two and boss.actions.get("phase_two",0) == 1,"phase threshold reachable once")
				check(not is_instance_valid(warning),"phase cancels old warning")
				await wait(0.2)
				check(boss.actions.get("phase_two",0) == 1,"phase transition not repeated")
				# Isolate the Boss target-loss contract; do not invalidate the global
				# player across a frame and accidentally test every unrelated HUD.
				var actual_player = Utils.player; Utils.player = null
				boss._physics_process(0.1)
				Utils.player = actual_player
				check(is_instance_valid(boss) and not boss.is_die,"lost target preserves boss")
				for child_id in boss.children_ids:
					var child = instance_from_id(child_id)
					if is_instance_valid(child): Combat.hit(child,{"damage":10000.0,"epoch":LevelServer.epoch})
			var wallet = PlayerData.gold; var generation = LevelServer.epoch
			Combat.hit(boss,{"damage":10000.0,"epoch":generation})
			var kills = Combat.kill_events
			check(not Combat.hit(boss,{"damage":10000.0,"epoch":generation}) and Combat.kill_events == kills,"dead boss rejects duplicate damage and death")
			if scenario in ["double-death","abandon"]:
				Utils.player.onHit(PlayerData.player_hp+1); await wait(0.1)
				check(LevelServer.state == "DEAD" and PlayerData.gold == wallet,"same frame death defers reward")
				dismiss(); PlayerData.resurrectPlayer(PlayerData.player_hp_max,100)
				if scenario == "double-death": LevelServer.state = "COMBAT"; LevelServer._timeout()
				else: LevelServer.return_to_camp()
			await wait(0.2); dismiss()
			check(LevelServer.state == "CAMP","boss settles or abandons")
			check(PlayerData.gold == wallet+(0 if scenario == "abandon" else 20),"reward exact once")
			LevelServer.boss_defeated(generation)
			check(PlayerData.gold == wallet+(0 if scenario == "abandon" else 20),"stale completion cannot reward")
			await wait(1.0)
			check(get_tree().get_nodes_in_group("monsters").is_empty() and get_tree().get_nodes_in_group("combat_transient").is_empty(),"boss summon projectile hazard cleanup")
	print("M6 CONTRACTS SUMMARY checks=",checks," failures=",failures)
	if failures: get_tree().quit(1)
	else: await Demo.quit_game()
