extends "res://tests/B12WeaponBench.gd"

var observing=false
var arrivals={}
var event_sources={}

func note_actor(node):
	if not observing or not node is BaseMonster or node.training:return
	var source="summoned" if node.get_meta("summoned",false) else ("horde" if LevelServer.horde_active else ("rush" if LevelServer.rush_active else "regular-or-flank"))
	event_sources[source]=event_sources.get(source,0)+1
	finish_arrival.call_deferred(node)

func finish_arrival(node):
	if not is_instance_valid(node):return
	arrivals[node.get_instance_id()]={"role":node.get_meta("content_id","unknown"),"elite":node.is_elite,"speed":node.SPEED,"hp":node.HP}

func special(node) -> bool:
	return node.is_elite or node.get_meta("content_id","") not in ["E01","E02"]

func _ready():
	await boot()
	get_tree().node_added.connect(note_actor)
	var stages=[29,39]
	var chosen=[]
	var tag="before"
	var duration=47.0
	var weapon=115
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--stage="):chosen.append(int(arg.substr(8)))
		if arg.begins_with("--tag="):tag=arg.substr(6)
		if arg.begins_with("--seconds="):duration=float(arg.substr(10))
		if arg.begins_with("--weapon="):weapon=int(arg.substr(9))
	if not chosen.is_empty():stages=chosen
	var output=[]
	for stage in stages:
		stop();dismiss();LevelServer.return_to_camp();await clean()
		if Utils.player.is_dead:PlayerData.resurrectPlayer(PlayerData.player_hp_max,100)
		seed(20260922)
		PlayerData.player_level=20;PlayerData.player_exp=0
		PlayerData.player_hp_max=5+19*PlayerData.PROGRESSION.HP_PER_LEVEL
		Demo.talents={"T01":3,"T02":3,"T03":3,"T04":3,"T08":3,"T10":1,"T19":1,"T24":3}
		Demo.owned_global_upgrades=["0","1","111","115","118","120"]
		Demo.kill_stacks=0;Demo.stack_time=0;Demo.refresh();configure(weapon)
		Utils.player.gun.updateGun();Utils.player.gun.bullets_count=Utils.player.gun.bullets_max_count
		PlayerData.player_hp=PlayerData.player_hp_max
		arrivals={};event_sources={};observing=true
		check(LevelServer.town.depart(stage,true),"real encounter departure %d"%stage)
		var start=Time.get_ticks_msec();var previous=start
		var total_time=0.0;var special_time=0.0;var peak_special=0;var peak=0;var hp_damage=0.0;var hp=PlayerData.player_hp
		var timeline=[];var next_sample=0.0
		var frames=[]
		movement=0;last_position=Utils.player.global_position;moving=true;target_boss=false;driving=true
		while LevelServer.state=="COMBAT" and not Utils.player.is_dead and Time.get_ticks_msec()-start<duration*1000:
			var now=Time.get_ticks_msec();var delta=(now-previous)/1000.0;previous=now
			frames.append([float(now-start)/1000.0,delta*1000,Performance.get_monitor(Performance.TIME_PROCESS)*1000,Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)*1000])
			var live=get_tree().get_nodes_in_group("monsters").filter(func(m):return not m.is_die and not m.training)
			var count=live.filter(special).size()
			total_time+=live.size()*delta;special_time+=count*delta;peak=maxi(peak,live.size());peak_special=maxi(peak_special,count)
			hp_damage+=maxf(0,hp-PlayerData.player_hp);hp=PlayerData.player_hp
			if (now-start)/1000.0>=next_sample:
				next_sample+=1
				timeline.append({"s":(now-start)/1000.0,"live":live.size(),"special":count,"hp":hp,"hazards":get_tree().get_nodes_in_group("hostile_zone").size()})
			await get_tree().process_frame
		stop();observing=false
		var special_arrivals=arrivals.values().filter(func(a):return a.elite or a.role not in ["E01","E02"]).size()
		var row={"stage":stage,"tag":tag,"seed":20260922,"seconds":(Time.get_ticks_msec()-start)/1000.0,"completed":LevelServer.state=="CAMP" and not Utils.player.is_dead,"dead":Utils.player.is_dead,"spawned":arrivals.size(),"special_spawned":special_arrivals,"ordinary_spawn_fraction":1.0-float(special_arrivals)/maxi(1,arrivals.size()),"ordinary_alive_time_fraction":1.0-special_time/maxf(0.001,total_time),"live_peak":peak,"special_peak":peak_special,"movement":movement,"damage_received":hp_damage,"event_sources":event_sources.duplicate(),"arrivals":arrivals.values(),"timeline":timeline,"weapon":115,"level_at_start":20,"level_at_end":PlayerData.player_level,"talents":Demo.talents.duplicate(),"upgrades":Demo.owned_global_upgrades.duplicate(),"observer":"real encounter, normal HP, autonomous walking/dodging, no human acceptance"}
		row.weapon=weapon
		row.frame_samples=frames
		row.frame_columns=["elapsed_s","frame_ms","published_process_proxy_ms","published_physics_proxy_ms"]
		output.append(row);print("B14_ENCOUNTER_ROW ",JSON.stringify(row))
		var file=FileAccess.open("res://evidence/visual-upgrade-20260919/b14-encounter-"+tag+".json",FileAccess.WRITE)
		file.store_string(JSON.stringify(output,"\t"));file.close()
	get_tree().quit.call_deferred(1 if failures else 0)
