extends "res://tests/M10Growth.gd"
func _ready():
	await boot(); configure(0)
	Demo.talents.clear(); Demo.owned_global_upgrades.clear(); Demo.refresh()
	var rows = []
	for id in range(24):
		for reward in Utils.player.reward_root.get_children(): reward.free()
		PlayerData.player_fire_rate = 1; PlayerData.player_hp_max = 5; PlayerData.player_hp = 3
		Utils.player.SPEED = 100
		var resource = RewardServer.reward_list[str(id)]
		var prototype = resource.instantiate(); var cap = prototype.max_count; var once = prototype.only_start; var info = prototype.reward_info; prototype.free()
		var gold = PlayerData.gold
		RewardServer.addReward(resource.instantiate())
		var reward = get_reward(id)
		var first_hp = PlayerData.player_hp_max; var first_speed = Utils.player.SPEED
		var values = []
		if once:
			check(reward==null,"one-off reward not persistent "+str(id))
			values.append({"gold_delta":PlayerData.gold-gold,"hp":PlayerData.player_hp})
		else:
			for rank in [1,cap]:
				while reward.count<rank: RewardServer.addReward(resource.instantiate())
				Demo.refresh()
				var target = enemy(origin+Vector2(50,0),100000); target.training = true; target.is_elite = true
				if id == 9: reward._on_timer_timeout()
				if id == 8: reward.doBuff()
				if id == 22: reward.moving_buff = true; Demo.refresh()
				for i in 100: Combat.hit(target,{"damage":10.0,"crit":1.0 if id==16 else 0.0,"depth":0,"epoch":LevelServer.epoch})
				values.append({"rank":rank,"hundred_direct_damage":target.idle_frame_num+target.critical_total,"burn_sources":target.burns.keys(),"slow":target.slow_amount,"hp_max":PlayerData.player_hp_max,"speed":Utils.player.SPEED,"rate":PlayerData.player_fire_rate,"magnet":RewardServer.pickup_bonus()})
				target.free()
			var extra = resource.instantiate(); check(not RewardServer.can_add(extra),"max stack rejects extra "+str(id)); extra.free()
			if id == 2: check(PlayerData.player_hp_max==17 and reward.count==cap,"helmet effect cap preserves count")
			if id == 5: check(Utils.player.SPEED==130 and reward.count==cap,"boots effect cap preserves count")
			if id == 10:
				var target = enemy(origin,1000)
				for i in 1000: reward.onKill(target)
				check(reward.kill_count==100 and is_equal_approx(PlayerData.player_hp_max,15),"bacteria effect cap")
				target.free()
			var before = [Utils.player.SPEED,PlayerData.player_fire_rate,PlayerData.player_hp_max]
			for i in 5: Demo.refresh()
			check(before==[Utils.player.SPEED,PlayerData.player_fire_rate,PlayerData.player_hp_max],"refresh no inflation "+str(id))
		rows.append({"id":id,"max_count":cap,"once":once,"info":info,"first_hp":first_hp,"first_speed":first_speed,"values":values})
		await clean()
	var file = FileAccess.open("res://evidence/visual-upgrade-20260919/b17-reward-matrix.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks":checks,"failures":failures,"rows":rows},"\t")); file.close()
	print("B17_REWARD_MATRIX_CHECKS ",checks," FAILURES ",failures)
	LevelServer.return_to_camp(); await Demo.quit_game()
