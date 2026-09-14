extends "res://tests/M8Runtime.gd"
func _ready():
	await boot()
	var tier = "full"
	for arg in OS.get_cmdline_user_args():
		if arg in ["middle","high","full"]: tier = arg
	var gun_id = {"middle":117,"high":113,"full":124}[tier]
	var rows = []
	for stage in [10,20,30]:
		if "only30" in OS.get_cmdline_user_args() and stage != 30: continue
		if "only20" in OS.get_cmdline_user_args() and stage != 20: continue
		stop(); dismiss()
		if Utils.player.is_dead: PlayerData.resurrectPlayer(PlayerData.player_hp_max,100)
		configure(gun_id,true); PlayerData.player_level = 1; PlayerData.player_exp = 0; Demo.refresh()
		PlayerData.player_hp_max = 8
		PlayerData.player_hp = PlayerData.player_hp_max
		check(LevelServer.town.depart(stage,true),"boss depart "+str(stage))
		var boss = instance_from_id(LevelServer.boss_instance)
		var start = Time.get_ticks_msec(); var hp = PlayerData.player_hp; var incoming = 0.0; var hits = 0
		var trace = {"actions":{},"travel":0.0,"phase_two":false}
		var telemetry = 0
		var warnings = {}
		var actual_hits = {"total":0,"boss":0,"damage":0.0}
		var hit_observer = func(_raw,applied,from_boss):
			actual_hits.total += 1; actual_hits.damage += applied
			if from_boss: actual_hits.boss += 1
		Utils.player.incoming_hit.connect(hit_observer)
		# Sample actual health changes and production action counters; no forced attacks/damage.
		shots_fired = 0; movement = 0; last_position = Utils.player.global_position; target_boss = true; driving = true
		while LevelServer.state == "COMBAT" and Time.get_ticks_msec()-start<210000:
			await wait(0.05)
			if PlayerData.player_hp<hp: hits += 1
			incoming += maxf(0,hp-PlayerData.player_hp); hp = PlayerData.player_hp
			if is_instance_valid(boss): trace = {"actions":boss.actions.duplicate(),"travel":boss.travelled,"phase_two":boss.phase_two,"remaining_hp":boss.HP}
			if is_instance_valid(boss) and boss.phase=="warn":
				for zone in get_tree().get_nodes_in_group("hostile_zone"):
					if zone.owner_ref and zone.owner_ref.get_ref()==boss and zone.elapsed<zone.warning and zone.is_visible_in_tree(): warnings[boss.attack_kind] = zone.mode
			if is_instance_valid(boss) and Time.get_ticks_msec()-telemetry>5000:
				telemetry = Time.get_ticks_msec(); print("BOSS TICK ",JSON.stringify({"stage":stage,"seconds":(telemetry-start)/1000.0,"player":str(Utils.player.global_position),"boss":str(boss.global_position),"target":str(boss.desired_point),"step":str(boss.cached_step),"line":Combat.clear_line(boss.global_position,Utils.player.global_position),"hp":boss.HP,"phase":boss.phase,"attacks":boss.actions.get("attack",0)}))
		var row = {"tier":tier,"stage":stage,"gun":gun_id,"seconds":(Time.get_ticks_msec()-start)/1000.0,"clear":LevelServer.state=="CAMP" and not Utils.player.is_dead,"death":Utils.player.is_dead,"damage_received":incoming,"successful_hits":hits,"player_movement":movement,"shots":shots_fired,"boss":trace,"effective":Utils.player.gun.effective.duplicate(true)}
		Utils.player.incoming_hit.disconnect(hit_observer)
		row.damage_received = actual_hits.damage; row.successful_hits = actual_hits.total; row.boss_successful_hits = actual_hits.boss
		row.observed_warnings = warnings
		check(row.clear and trace.phase_two,"boss clear and both phases "+str(stage))
		for attack in {10:["charge","cleave","slam"],20:["brood","lockdown","pulse"],30:["dash","sweep","burst"]}[stage]:
			check(trace.actions.get(attack,0)>0,"boss executed "+attack)
			if "--r1" in OS.get_cmdline_user_args(): check(warnings.has(attack),"boss actual windup telegraph "+attack)
		rows.append(row); print("M8 BOSS ",JSON.stringify(row))
		var suffix = "-20" if "only20" in OS.get_cmdline_user_args() else ("-30" if "only30" in OS.get_cmdline_user_args() else "")
		var prefix = "r1-boss-" if "--r1" in OS.get_cmdline_user_args() else "boss-"
		var file = FileAccess.open("res://docs/iteration/evidence/m8/"+prefix+tier+suffix+".json",FileAccess.WRITE); file.store_string(JSON.stringify(rows,"\t")); file.close()
		stop(); LevelServer.return_to_camp(); dismiss(); await wait(0.8)
		check(get_tree().get_nodes_in_group("monsters").is_empty() and get_tree().get_nodes_in_group("combat_transient").is_empty(),"boss cleanup "+str(stage))
	print("M8 BOSSES SUMMARY checks=",checks," failures=",failures)
	if failures: get_tree().quit(1)
	else: await Demo.quit_game()
