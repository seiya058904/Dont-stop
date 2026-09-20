extends "res://tests/B12WeaponBench.gd"

func _ready():
	await boot()
	var output=[]
	for stage in [10,20,30,40]:
		stop(); dismiss(); LevelServer.return_to_camp(); await clean()
		if Utils.player.is_dead: PlayerData.resurrectPlayer(PlayerData.player_hp_max,100)
		configure(112,true)
		PlayerData.player_level=20; PlayerData.player_exp=0
		PlayerData.player_hp_max=5+19*PlayerData.PROGRESSION.HP_PER_LEVEL+DemoConfig.talent_value("T07",Demo.rank("T07"))
		Demo.refresh()
		PlayerData.player_hp=PlayerData.player_hp_max
		seed(808); load("res://game/map/ArenaHazardDirector.gd").fixed_seed=808
		check(LevelServer.town.depart(stage,true),"normal-health boss departure "+str(stage))
		movement=0; last_position=Utils.player.global_position
		driving=true; moving=true; target_boss=true
		var start=Time.get_ticks_msec()
		var timeline=[]
		while LevelServer.state=="COMBAT" and not Utils.player.is_dead and Time.get_ticks_msec()-start<120000:
			await wait(0.25)
			var bosses=get_tree().get_nodes_in_group("monsters").filter(func(m): return m.is_boss and not m.is_die)
			timeline.append({"s":(Time.get_ticks_msec()-start)/1000.0,"hp":PlayerData.player_hp,"boss_hp":bosses[0].HP if not bosses.is_empty() else 0,"shots":get_tree().get_nodes_in_group("enemy_projectiles").size(),"position":[Utils.player.global_position.x,Utils.player.global_position.y]})
		stop()
		var row={"stage":stage,"level_at_start":20,"seed":808,"weapon":112,"completed":LevelServer.state=="CAMP" and not Utils.player.is_dead,"dead":Utils.player.is_dead,"hp":PlayerData.player_hp,"movement":movement,"timeline":timeline,"observer":"normal HP autonomous movement and shooting; no HP refill, no human acceptance"}
		output.append(row)
		print("B17_BOSS_LATE ",JSON.stringify(row))
		var file=FileAccess.open("res://evidence/visual-upgrade-20260919/b17-boss-late.json",FileAccess.WRITE)
		file.store_string(JSON.stringify(output,"\t")); file.close()
		check(row.completed,"normal-health boss completion "+str(stage))
	print("B17 BOSS LATE checks=",checks," failures=",failures)
	get_tree().quit(1 if failures else 0)
