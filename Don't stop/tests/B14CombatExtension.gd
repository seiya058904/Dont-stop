extends "res://tests/B14HordeBench.gd"

var charge_fraction := 1.0

func fire_at(point: Vector2, delta: float):
	if Utils.player.gun.weapon_id != 113 or charge_fraction == 1.0:
		super.fire_at(point,delta)
		return
	var gun=Utils.player.gun
	Utils.aim_override=get_viewport().get_canvas_transform()*point
	gun.look_at(point);gun.direction=gun.gun_tip.global_position.direction_to(point)
	gun.handle_charge(not (gun.charging and gun.charge_time>=gun.effective.warmup*charge_fraction),delta)

func _ready():
	await boot()
	var ids=[6,112,113,115,119,124]
	var scenario="wave"
	var tag="before"
	var run_seed=20260921
	var chosen=[]
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--id="): chosen.append(int(arg.substr(5)))
		if arg.begins_with("--scenario="): scenario=arg.substr(11)
		if arg.begins_with("--tag="): tag=arg.substr(6)
		if arg.begins_with("--fraction="): charge_fraction=float(arg.substr(11))
	if not chosen.is_empty(): ids=chosen
	var output=[]
	for id in ids:
		stop();dismiss();LevelServer.return_to_camp();await clean()
		if Utils.player.is_dead: PlayerData.resurrectPlayer(PlayerData.player_hp_max,100)
		seed(run_seed)
		PlayerData.player_level=20;PlayerData.player_exp=0
		PlayerData.player_hp_max=5+19*PlayerData.PROGRESSION.HP_PER_LEVEL
		Demo.talents={"T01":3,"T02":3,"T03":3,"T04":3,"T08":3,"T10":1}
		Demo.owned_global_upgrades=["0","1","111","115","118","120"]
		Demo.kill_stacks=0;Demo.stack_time=0;Demo.refresh();configure(id)
		var gun=Utils.player.gun
		gun.updateGun();gun.bullets_count=gun.bullets_max_count;PlayerData.reserve_magazines=100
		var boss=null
		var seconds=20.0 if scenario=="boss" else 18.0
		if scenario=="boss":
			check(LevelServer.town.depart(40,true),"real Stage40 departure")
			boss=instance_from_id(LevelServer.boss_instance)
		else:
			LevelServer.timer.stop();LevelServer.level=39;LevelServer.epoch+=1
			LevelServer.town.prepare_region("R8");await wait(0.1);LevelServer.state="COMBAT"
		PlayerData.player_hp=PlayerData.player_hp_max
		run_kills=0;first_kill=-1;run_overkill=0;bench_time=0;spawned_stats=[]
		var spawned=0
		if scenario=="wave":
			for i in 24:
				if spawn_chaser(spawned): spawned+=1
		elif scenario=="elite":
			var elite=M5Content.spawn("E03",LevelServer.town.monster_root,LevelServer.town.spawn_near(Utils.player.global_position,140,180,M5Content.radius_for("E03")))
			M5Content.promote_elite(elite)
			boss=elite
		var initial_hp=boss.HP if is_instance_valid(boss) else 0
		var remaining_hp=initial_hp
		var clear_seconds=-1.0
		var start=Time.get_ticks_msec();var previous=start
		var alive_integral=0.0;var peak=0;var hp_damage=0.0;var reload_time=0.0;var charge_time_total=0.0
		var hp_before=PlayerData.player_hp;var wall_blocked=0;var samples=0;var hits=Combat.damage_events
		var trace={}
		movement=0;shots_fired=0;last_position=Utils.player.global_position;bot_clock=0
		target_boss=scenario=="boss";moving=true;driving=true
		while Time.get_ticks_msec()-start<seconds*1000 and LevelServer.state=="COMBAT" and not Utils.player.is_dead:
			var now=Time.get_ticks_msec();var delta=(now-previous)/1000.0;previous=now;bench_time=(now-start)/1000.0
			var actors=get_tree().get_nodes_in_group("monsters").filter(func(m):return not m.is_die and not m.training)
			alive_integral+=actors.size()*delta;peak=maxi(peak,actors.size())
			if gun.is_reloading: reload_time+=delta
			if gun.get("charging")==true: charge_time_total+=delta
			if id==6: gun._physics_process(delta)
			if is_instance_valid(boss):
				remaining_hp=maxf(0,boss.HP)
				trace={"actions":boss.actions.duplicate(),"phase_two":boss.phase_two,"phase_three":boss.phase_three}
				if not Combat.clear_line(gun.gun_tip.global_position,boss.global_position):wall_blocked+=1
				samples+=1
			hp_damage+=maxf(0,hp_before-PlayerData.player_hp);hp_before=PlayerData.player_hp
			if actors.is_empty():clear_seconds=bench_time;break
			await get_tree().process_frame
		stop()
		var row={"id":id,"scenario":scenario,"seed":run_seed,"tag":tag,"charge_fraction":charge_fraction,"seconds":bench_time,"clear_seconds":clear_seconds,"kills":run_kills,"spawned":spawned,"alive_mean":alive_integral/maxf(0.001,bench_time),"alive_peak":peak,"damage_received":hp_damage,"dead":Utils.player.is_dead,"movement":movement,"reload_s":reload_time,"charge_s":charge_time_total,"first_kill_s":first_kill,"overkill":run_overkill,"target_initial_hp":initial_hp,"target_remaining_hp":remaining_hp,"target_damage":initial_hp-remaining_hp,"target_trace":trace,"wall_blocked_fraction":float(wall_blocked)/maxi(1,samples),"hit_events":Combat.damage_events-hits,"level":20,"talents":Demo.talents.duplicate(),"upgrades":Demo.owned_global_upgrades.duplicate(),"effective":gun.effective.duplicate(true),"observer":"normal health, autonomous movement; bounded observation not human acceptance"}
		output.append(row);print("B14_EXTENSION_ROW ",JSON.stringify(row))
		var file=FileAccess.open("res://evidence/visual-upgrade-20260919/b14-extension-"+scenario+"-"+tag+".json",FileAccess.WRITE)
		file.store_string(JSON.stringify(output,"\t"));file.close()
	print("B14_EXTENSION_DONE rows=",output.size())
	get_tree().quit.call_deferred(1 if failures else 0)
