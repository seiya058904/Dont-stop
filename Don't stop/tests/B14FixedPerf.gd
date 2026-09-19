extends "res://tests/B8Runtime.gd"

func _ready():
	await boot();configure(0)
	LevelServer.timer.stop();LevelServer.level=40;LevelServer.epoch+=1
	LevelServer.town.prepare_region("R8");await wait(0.2)
	LevelServer.state="COMBAT";ArenaVisibility.apply_stage(40)
	Utils.player.set_physics_process(false);Utils.player.set_process(false)
	PlayerData.player_hp_max=100000;PlayerData.player_hp=100000
	await visual_ready(Vector2i(410,230));recenter()
	var tag="before"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--tag="):tag=arg.substr(6)
	if not rendering():get_tree().quit(2);return
	var center=Utils.player.global_position
	var boss=M5Content.spawn("B04",LevelServer.town.monster_root,LevelServer.town.spawn_near(center,100,150,M5Content.radius_for("B04")))
	boss.set_physics_process(false)
	var rows=[];var next_wave=0.0;var next_ultimate=0.0
	var start=Time.get_ticks_usec();var previous=start;var peak=0;var emitted=0
	while Time.get_ticks_usec()-start<106000000:
		var now=Time.get_ticks_usec();var elapsed=(now-start)/1000000.0
		if elapsed>=next_wave:
			next_wave+=2.5
			for i in 10:
				var zone=load("res://game/monster/HostileZone.gd").new()
				zone.mode="line" if i<6 else "circle";zone.style="laser" if i<6 else "shock"
				zone.world_point=center+Vector2.RIGHT.rotated(i*TAU/10)*100
				zone.direction=(center-zone.world_point).normalized();zone.length=240;zone.radius=36;zone.width=10
				zone.warning=1.0;zone.duration=1.2;zone.damage=0;zone.pierce=i<6
				get_tree().current_scene.add_child(zone);emitted+=1
		if elapsed>=next_ultimate:
			next_ultimate+=5.0
			var ultimate=load("res://game/monster/BossUltimate.gd").new()
			ultimate.role="B04";ultimate.owner_ref=weakref(boss);ultimate.position=boss.global_position
			get_tree().current_scene.add_child(ultimate)
		PlayerData.player_hp=100000
		peak=maxi(peak,get_tree().get_nodes_in_group("combat_transient").size())
		rows.append([elapsed,(now-previous)/1000.0,Performance.get_monitor(Performance.TIME_PROCESS)*1000,Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)*1000,Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)])
		previous=now
		await get_tree().process_frame
	var result={"tag":tag,"method":"native Godot rendered fixed technical fixture; no screenshots while sampling","renderer":RenderingServer.get_current_rendering_method(),"window":[15,105],"columns":["elapsed_s","frame_ms","published_process_proxy_ms","published_physics_proxy_ms","draw_calls"],"rows":rows,"zones_emitted":emitted,"transient_peak":peak,"true_per_frame_cpu":null,"gpu_ms":null,"note":"same stationary observer, no weapon damage, fixed 10-zone cycle and one B04 ultimate per 5s; not gameplay performance or full acceptance"}
	var file=FileAccess.open("res://evidence/visual-upgrade-20260919/b14-fixed-perf-"+tag+".json",FileAccess.WRITE)
	file.store_string(JSON.stringify(result));file.close()
	print("B14_FIXED_PERF_DONE rows=",rows.size()," tag=",tag)
	get_tree().quit.call_deferred()
