extends "res://tests/M8Runtime.gd"
func _ready():
	await boot(); configure(124,true)
	var typical = "typical" in OS.get_cmdline_user_args()
	if typical:
		Demo.owned_global_upgrades = ["110","0","1","117","120"]
		Demo.talents = {"T01":2,"T02":2,"T03":2,"T04":2,"T07":3,"T08":2,"T19":1,"T24":2}
		for id in [12,14,17,18,20,21,22,23]: RewardServer.addReward(RewardServer.reward_list[str(id)].instantiate())
		Demo.refresh()
	var rows = []
	var probe = "probe" in OS.get_cmdline_user_args()
	for stage in ([7,13,17,22,26,29] if probe else [22,26,29]):
		if "only29" in OS.get_cmdline_user_args() and stage!=29: continue
		stop(); dismiss(); LevelServer.return_to_camp(); await wait(0.3)
		PlayerData.resurrectPlayer(PlayerData.player_hp_max,100); configure(117 if typical else 124,not typical)
		if probe: PlayerData.player_hp_max = 10000; PlayerData.player_hp = 10000
		else: PlayerData.player_hp_max = 8; PlayerData.player_hp = 8
		check(LevelServer.town.depart(stage,true),"density depart "+str(stage))
		var sample = []; var peak = 0; var born = {}; var near_peak = 0; var illegal = 0
		var start = Time.get_ticks_msec(); movement = 0; shots_fired = 0
		driving = not probe; moving = true; target_boss = false
		while LevelServer.state=="COMBAT" and Time.get_ticks_msec()-start < 55000:
			await wait(0.1)
			var actors = get_tree().get_nodes_in_group("monsters").filter(func(n): return not n.is_die and not n.training)
			peak = maxi(peak,actors.size()); sample.append(actors.size())
			var near = 0
			for actor in actors:
				var distance = actor.global_position.distance_to(Utils.player.global_position)
				if distance<80: near+=1
				if not born.has(actor.get_instance_id()):
					born[actor.get_instance_id()] = actor.get_meta("content_id","")
					if Time.get_ticks_msec()-actor.get_meta("born_ms",0)<150 and not actor.get_meta("summoned",false) and distance<125: illegal+=1
			near_peak=maxi(near_peak,near)
		var simple = born.values().filter(func(id): return id in ["E01","E02"]).size()
		var sum = 0.0
		for count in sample: sum+=count
		var row = {"stage":stage,"probe":probe,"typical":typical,"alive_peak":peak,"mean_alive":sum/maxi(1,sample.size()),"near80_peak":near_peak,"spawns":born.size(),"simple_spawns":simple,"simple_ratio":float(simple)/maxi(1,born.size()),"illegal_near_spawns":illegal,"clear":LevelServer.state=="CAMP" and not Utils.player.is_dead,"movement":movement,"shots":shots_fired,"seconds":(Time.get_ticks_msec()-start)/1000.0}
		rows.append(row); print("M10 DENSITY ",JSON.stringify(row))
		check(illegal==0,"safe spawn "+str(stage))
		if not probe: check(row.clear and movement>1000,"legal clear while moving "+str(stage))
		stop(); LevelServer.return_to_camp(); await wait(0.4)
	var file = FileAccess.open("res://docs/iteration/evidence/m10/density.json",FileAccess.WRITE); file.store_string(JSON.stringify(rows,"\t")); file.close()
	print("M10_DENSITY_CHECKS ",checks," FAILURES ",failures)
	await Demo.quit_game()
