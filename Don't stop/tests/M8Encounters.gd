extends "res://tests/M8Runtime.gd"
var rows = []
var label_name = "encounters"
func _ready():
	await boot()
	if "baseline" in OS.get_cmdline_user_args(): label_name = "baseline-encounters"
	for stage in range(1,31):
		stop(); dismiss()
		if Utils.player.is_dead: PlayerData.resurrectPlayer(PlayerData.player_hp_max,100)
		# Fixed Tier III / purchased full talents+upgrades at all stages: isolates content curve.
		configure(117,true); PlayerData.player_level = 1; PlayerData.player_exp = 0; Demo.refresh()
		PlayerData.player_hp_max = 8; PlayerData.player_hp = 8
		check(LevelServer.town.depart(stage,true),"depart "+str(stage))
		shots_fired = 0; movement = 0; last_position = Utils.player.global_position
		var start = Time.get_ticks_msec(); var previous = {}; var samples = 0; var pursuit = 0; var pressure = 0; var max_threats = 0; var threat_sum = 0; var composition = {}; var incoming = 0.0; var hp = PlayerData.player_hp
		var longest_idle = 0.0; var idle = 0.0
		driving = true; target_boss = true
		while LevelServer.state == "COMBAT" and Time.get_ticks_msec()-start < 240000:
			await wait(0.1)
			var chasing = false; var pressing = false; var threats = 0
			incoming += maxf(0,hp-PlayerData.player_hp); hp = PlayerData.player_hp
			for actor in get_tree().get_nodes_in_group("monsters"):
				if actor.is_die: continue
				var key = actor.get_instance_id(); var pos = actor.global_position; var old = previous.get(key,pos)
				var toward = old.direction_to(Utils.player.global_position)
				var advancing = (pos-old).dot(toward)>0.6
				var contact = pos.distance_to(Utils.player.global_position)<42
				chasing = chasing or advancing; pressing = pressing or advancing or contact
				if advancing or contact or actor.get("phase") == "warn": threats += 1
				previous[key] = pos
				var id = actor.get_meta("content_id","")
				composition[id] = composition.get(id,0)+1
			if chasing: pursuit += 1
			if pressing: pressure += 1; idle = 0.0
			else: idle += 0.1; longest_idle = maxf(longest_idle,idle)
			samples += 1; max_threats = maxi(max_threats,threats); threat_sum += threats
		var row = {"stage":stage,"boss":DemoConfig.ENCOUNTERS[stage].get("boss",""),"clear":LevelServer.state == "CAMP" and not Utils.player.is_dead,"death":Utils.player.is_dead,"seconds":(Time.get_ticks_msec()-start)/1000.0,"incoming_damage":incoming,"pursuit_uptime":pursuit/float(maxi(1,samples)),"pressure_uptime":pressure/float(maxi(1,samples)),"longest_no_pressure":longest_idle,"simultaneous_threats_peak":max_threats,"simultaneous_threats_mean":threat_sum/float(maxi(1,samples)),"actor_samples_by_role":composition,"player_movement":movement,"shots":shots_fired,"weapon":117,"effective":Utils.player.gun.effective.duplicate(true)}
		stop(); LevelServer.return_to_camp(); dismiss(); await wait(0.8)
		row.cleanup = get_tree().get_nodes_in_group("monsters").size()+get_tree().get_nodes_in_group("combat_transient").size()
		check(row.cleanup==0,"cleanup "+str(stage)); rows.append(row); print("M8 ENCOUNTER ",JSON.stringify(row))
		var f = FileAccess.open("res://docs/iteration/evidence/m8/"+label_name+".json",FileAccess.WRITE); f.store_string(JSON.stringify(rows,"\t")); f.close()
	print("M8 ENCOUNTERS SUMMARY checks=",checks," failures=",failures)
	await Demo.quit_game()
