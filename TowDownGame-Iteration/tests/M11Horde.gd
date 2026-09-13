extends "res://tests/M8Runtime.gd"
var collecting = false
var births = {}
var engaged = {}
var damage_work = 0.0
var hp_loss = 0.0
var previous_hp = 0.0
var samples = []
var close_samples = []
var frame_ms = []
var cpu_ms = []
var since_sample = 0.0
var dead_air = 0.0
var dead_air_peak = 0.0
var below_five = 0.0
var enemy_peak = 0
var player_peak = 0
var vfx_peak = 0
var illegal = 0
var previous_tick = 0
var side_counts = {}
var stuck_peak = 0.0
var path_queries = 0
var spawn_queries = 0
var timing_clock = 0.0
var cold_max_ms = 0.0
var player_vfx_peak = 0
var viewport_draw_peak = 0
var navigation_instrumented = false
func born(node):
	if not collecting or not node is BaseMonster or node.training: return
	var id = node.get_instance_id()
	var offset=node.global_position-Utils.player.global_position
	var side=(0 if offset.x>=0 else 2) if absf(offset.x)>absf(offset.y) else (1 if offset.y>=0 else 3)
	side_counts[side]=side_counts.get(side,0)+1
	births[id] = {"ref":weakref(node),"hp":node.HP,"simple":node.get_meta("content_id","") in ["E01","E02"],"point":node.global_position,"engaged":false,"stuck":0.0}
	if not node.get_meta("summoned",false) and node.global_position.distance_to(Utils.player.global_position)<140: illegal+=1
func _process(delta):
	super._process(delta)
	if not collecting or get_tree().paused: return
	var now = Time.get_ticks_usec()
	timing_clock+=delta
	if previous_tick>0:
		cold_max_ms=maxf(cold_max_ms,(now-previous_tick)/1000.0)
		if timing_clock>3: frame_ms.append((now-previous_tick)/1000.0); cpu_ms.append(Performance.get_monitor(Performance.TIME_PROCESS)*1000.0)
	previous_tick = now
	if DisplayServer.get_name()!="headless": viewport_draw_peak=maxi(viewport_draw_peak,RenderingServer.viewport_get_render_info(play_view.get_viewport_rid(),RenderingServer.VIEWPORT_RENDER_INFO_TYPE_CANVAS,RenderingServer.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME))
	since_sample += delta
	if since_sample<0.1: return
	var dt = since_sample; since_sample = 0
	if is_instance_valid(LevelServer.town.arena):
		navigation_instrumented=LevelServer.town.arena.get("path_queries")!=null
		path_queries=int(LevelServer.town.arena.get("path_queries") if LevelServer.town.arena.get("path_queries")!=null else 0)
		spawn_queries=int(LevelServer.town.arena.get("spawn_path_queries") if LevelServer.town.arena.get("spawn_path_queries")!=null else 0)
	var alive = 0; var nearby = 0
	for id in births:
		var row = births[id]; var node = row.ref.get_ref()
		if not is_instance_valid(node): continue
		damage_work += maxf(0,row.hp-maxf(0,node.HP)); row.hp=maxf(0,node.HP)
		if node.is_die: continue
		alive+=1
		var distance = node.global_position.distance_to(Utils.player.global_position)
		if row.simple and distance>120 and node.global_position.distance_to(row.point)<0.5: row.stuck+=dt
		else: row.stuck=0
		row.point=node.global_position; stuck_peak=maxf(stuck_peak,row.stuck)
		if distance<=120: nearby+=1
		if distance<=200: engaged[id]=true
	samples.append(alive); close_samples.append(nearby)
	if alive<5: below_five+=dt
	if alive==0: dead_air+=dt; dead_air_peak=maxf(dead_air_peak,dead_air)
	else: dead_air=0
	enemy_peak=maxi(enemy_peak,get_tree().get_nodes_in_group("enemy_projectiles").size())
	player_peak=maxi(player_peak,get_tree().get_nodes_in_group("combat_transient").filter(func(n): return not n.is_in_group("enemy_projectiles") and (n.get("context")!=null)).size())
	vfx_peak=maxi(vfx_peak,get_tree().get_nodes_in_group("hostile_vfx").size())
	player_vfx_peak=maxi(player_vfx_peak,get_tree().get_nodes_in_group("combat_transient").filter(func(n): return n.get_script()==load("res://game/effects/CombatEffect.gd")).size())
func stats(values: Array) -> Dictionary:
	if values.is_empty(): return {"mean":0,"median":0,"p90":0,"p95":0,"p99":0,"peak":0}
	var sorted=values.duplicate(); sorted.sort(); var total=0.0
	for value in sorted: total+=value
	return {"mean":total/sorted.size(),"median":sorted[int(sorted.size()*0.5)],"p90":sorted[int(sorted.size()*0.9)],"p95":sorted[int(sorted.size()*0.95)],"p99":sorted[int(sorted.size()*0.99)],"peak":sorted.back()}
func _ready():
	await boot()
	var args=OS.get_cmdline_user_args(); var build="B"
	for id in ["A","B","C"]:
		if id in args: build=id
	var installed=load("res://tests/M11Builds.gd").install(build)
	check(installed.failures.is_empty(),"all benchmark purchases legal within fixed budget")
	var initial=Demo.snapshot().duplicate(true)
	get_tree().node_added.connect(born)
	PlayerData.onHpChange.connect(func(hp,_maximum):
		if collecting: hp_loss+=maxf(0,previous_hp-hp)
		previous_hp=hp)
	var rows=[]
	for stage in [18,21,24,26,27,28,29]:
		if "quick" in args and stage!=29: continue
		stop(); dismiss(); LevelServer.return_to_camp(); await wait(0.3); dismiss()
		# Same exact legal profile starts each stage; normal combat EXP/procs/healing remain enabled.
		Demo.test_mode=false; Demo.save_path="res://docs/iteration/evidence/m11/profile.json"
		var file=FileAccess.open(Demo.save_path,FileAccess.WRITE); file.store_string(JSON.stringify(initial)); file.close()
		check(Demo.load_camp(),"fixed profile reload "+str(stage)); Demo.test_mode=true
		PlayerData.resurrectPlayer(PlayerData.player_hp_max,100)
		check(LevelServer.town.depart(stage,true),"legal departure "+str(stage))
		await wait(0.05); last_position=Utils.player.global_position
		births.clear(); engaged.clear(); samples.clear(); close_samples.clear(); frame_ms.clear(); cpu_ms.clear()
		side_counts.clear(); stuck_peak=0; path_queries=0; spawn_queries=0
		player_vfx_peak=0; viewport_draw_peak=0; navigation_instrumented=false
		damage_work=0; hp_loss=0; dead_air=0; dead_air_peak=0; below_five=0; illegal=0; previous_tick=0
		enemy_peak=0; player_peak=0; vfx_peak=0; movement=0; shots_fired=0
		var kills=Combat.kill_events; var start=Time.get_ticks_msec()
		previous_hp=PlayerData.player_hp; collecting=true; driving=true; moving=not "stationary" in args
		timing_clock=0; cold_max_ms=0
		var captured=false
		while LevelServer.state=="COMBAT" and Time.get_ticks_msec()-start<50000:
			await wait(0.1)
			if DisplayServer.get_name()!="headless" and not captured and Time.get_ticks_msec()-start>18000:
				RenderingServer.force_draw(false)
				var picture=play_view.get_texture().get_image(); picture.resize(1366,768,Image.INTERPOLATE_NEAREST)
				picture.save_png("res://docs/iteration/evidence/m11/horde-"+build+"-"+str(stage)+".png"); captured=true
		collecting=false; stop()
		var seconds=(Time.get_ticks_msec()-start)/1000.0
		var row={"build":build,"stage":stage,"alive":stats(samples),"close120":stats(close_samples),"spawn_rate":births.size()/seconds,"kill_rate":(Combat.kill_events-kills)/seconds,"engagement200_rate":engaged.size()/seconds,"below_five_seconds":below_five,"longest_dead_air":dead_air_peak,"hp_loss":hp_loss,"death":Utils.player.is_dead,"clear":LevelServer.state=="CAMP" and not Utils.player.is_dead,"seconds":seconds,"effective_hp_dps":damage_work/seconds,"shots":shots_fired,"movement":movement,"simple_ratio":float(births.values().filter(func(r): return r.simple).size())/maxi(1,births.size()),"illegal_spawns":illegal,"enemy_projectile_peak":enemy_peak,"player_projectile_peak":player_peak,"vfx_peak":vfx_peak,"frame_ms":stats(frame_ms),"cpu_ms":stats(cpu_ms),"draw_calls":Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)}
		rows.append(row); print("M11 HORDE ",JSON.stringify(row))
		row.arrival_sides=side_counts.duplicate(); row.stuck_seconds_peak=stuck_peak
		row.path_queries=path_queries; row.spawn_path_queries=spawn_queries
		row.including_cold_max_ms=cold_max_ms
		row.player_vfx_peak=player_vfx_peak; row.viewport_draw_peak=viewport_draw_peak; row.navigation_instrumented=navigation_instrumented
		if DisplayServer.get_name()!="headless": check(viewport_draw_peak>0,"native battle viewport rendered "+str(stage))
		row.overlap_peak=LevelServer.get("horde_overlap_peak"); row.reinforcement_with_survivors=LevelServer.get("horde_while_alive")
		check(illegal==0,"safe normal arrivals "+str(stage)); check(shots_fired>0,"active fire "+str(stage))
		LevelServer.return_to_camp(); await wait(0.3); dismiss()
		check(get_tree().get_nodes_in_group("monsters").is_empty() and get_tree().get_nodes_in_group("combat_transient").is_empty(),"stage cleanup "+str(stage))
	var file=FileAccess.open("res://docs/iteration/evidence/m11/horde.json",FileAccess.WRITE); file.store_string(JSON.stringify({"build":installed,"rows":rows,"checks":checks,"failures":failures},"\t")); file.close()
	print("M11_HORDE_CHECKS ",checks," FAILURES ",failures)
	await Demo.quit_game()
