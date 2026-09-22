extends "res://tests/M10Growth.gd"
func _ready():
	await boot(); configure(0)
	var rows = []
	# Same real gun and target: A, B, A+B, then A+B+reward.
	for mode in ["base","upgrade","talent","both","three"]:
		Demo.owned_global_upgrades = ["110","114"] if mode in ["upgrade","both","three"] else []
		Demo.talents = {"T01":1,"T02":1,"T06":1,"T15":1} if mode in ["talent","both","three"] else {}
		if mode == "three": give(14); give(12,4); give(15); give(16,3)
		PlayerData.player_level = 1; PlayerData.player_exp = 0; Demo.refresh()
		var gun = Utils.player.gun; gun.bullets_count = gun.bullets_max_count
		var target = enemy(origin+Vector2(80,0),100000); target.training = false; target.is_elite = true; target.knockback_def = 100000
		Utils.player.global_position = origin; gun.global_rotation = 0
		gun.cancel_actions(); gun.can_shoot = true; gun.is_reloading = false; gun.change_timer.stop(); gun.timer.stop()
		LevelServer.state = "COMBAT"; LevelServer.timerStop(); seed(1234)
		var start = Time.get_ticks_msec(); shots_fired = 0
		while Time.get_ticks_msec()-start<6000:
			fire_at(target.global_position-Vector2(0,8),0.02); await wait(0.02)
		var row = {"mode":mode,"damage":100000-target.HP,"shots":shots_fired,"burn_sources":target.burns.keys(),"stats":gun.effective.duplicate()}
		check(row.damage>0 and row.shots>0,"real firing "+mode)
		rows.append(row); await clean()
	check(rows[3].damage>maxf(rows[1].damage,rows[2].damage),"real combined damage retains both")
	check(rows[4].damage>rows[3].damage,"real three-layer conditional damage")
	LevelServer.state = "COMBAT"; LevelServer.timerStop()
	PlayerData.player_hp_max = 50; PlayerData.player_hp = 10
	var gel = give(18,3); var latch = give(21,3)
	Demo.talents.T11 = 1; Demo.talents.T24 = 1; Demo.refresh()
	var hp = PlayerData.player_hp; var mags = PlayerData.reserve_magazines
	for i in 10:
		var target = enemy(origin+Vector2(80,0),1)
		Combat.hit(target,{"damage":10.0,"depth":0,"epoch":LevelServer.epoch})
	check(PlayerData.player_hp>=hp+0.5,"gel plus talent healing actual kills")
	check(PlayerData.reserve_magazines>=mags+3,"latch plus talent reserve actual kills")
	var kills = gel.direct_kills
	var derived_target = enemy(origin+Vector2(80,0),1)
	Combat.hit(derived_target,{"damage":10.0,"depth":1,"epoch":LevelServer.epoch})
	check(gel.direct_kills==kills,"derived kill cannot refill or heal")
	var target = enemy(origin+Vector2(80,0),100000); target.training = true
	var prism = get_reward(16); var pulse = get_reward(15)
	var context = Utils.player.gun.damage_context(); context.crit = 1.0
	for i in 50: Combat.hit(target,context)
	var shards = get_tree().get_nodes_in_group("combat_transient").filter(func(n): return n is Bullet)
	check(shards.size()>0,"critical reward emits real fragment sprites")
	check(shards.all(func(n): return n.context.depth==1 and n.context.crit==0 and n.context.shards==0),"fragments one generation")
	var hit_counter = pulse.direct_hits
	for shard in shards: Combat.hit(target,shard.context)
	check(pulse.direct_hits==hit_counter,"fragment cannot recurse direct proc")
	var before = Utils.player.global_position
	Input.action_press("right"); await wait(0.15)
	check(Utils.player.global_position.distance_to(before)>1.0,"ordinary damage does not block movement")
	var gun = Utils.player.gun; gun.bullets_count = 0; gun.is_reloading = false
	gun.change_timer.stop(); gun.reload_ammo()
	check(gun.is_reloading and not gun.change_timer.is_stopped(),"reload remains available")
	Input.action_release("right"); await wait(1.8)
	var ammo = gun.bullets_count; gun.can_shoot = true; Demo.fire_released = true
	fire_at(target.global_position,0.02); await wait(0.05)
	check(gun.bullets_count<ammo,"real firing remains available")
	LevelServer.return_to_camp(); await wait(0.3)
	# Old reward caps preserve storage counts; repeated refresh must not add stats.
	for id in [2,3,4,5,6,7,8,9,10,11]:
		var reward = get_reward(id)
		if not reward: reward = give(id)
		var cap = reward.max_count
		while reward.count < cap: RewardServer.addReward(RewardServer.reward_list[str(id)].instantiate())
		var extra = RewardServer.reward_list[str(id)].instantiate()
		check(not RewardServer.can_add(extra),"stack cap "+str(id)); extra.free()
		rows.append({"id":id,"stored_count":reward.count,"max_count":cap})
	var speed = Utils.player.SPEED; hp = PlayerData.player_hp_max; var rate = PlayerData.player_fire_rate
	for i in 10: Demo.refresh()
	check(Utils.player.SPEED==speed and PlayerData.player_hp_max==hp and PlayerData.player_fire_rate==rate,"old effects no refresh inflation")
	var file = FileAccess.open("res://docs/iteration/evidence/m10/reward-audit.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks":checks,"failures":failures,"rows":rows},"\t")); file.close()
	print("M10_REWARD_AUDIT_CHECKS ",checks," FAILURES ",failures)
	await Demo.quit_game()
