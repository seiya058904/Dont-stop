extends "res://tests/M8Runtime.gd"

const BASE_ATTACKS = {10:["charge","cleave","slam"],20:["brood","lockdown","pulse"],30:["dash","sweep","burst"],40:["dash","sweep","burst"]}
var executed_attacks: Dictionary = {}
var observed_attack_serial := 0

func isolated_stage() -> int:
	for stage in [10,20,30,40]:
		if "only"+str(stage) in OS.get_cmdline_user_args(): return stage
	return 0

func run_isolated_cases() -> void:
	# Full cases must not inherit the previous fight's RNG consumption, bot
	# clock, talent cooldowns or epoch-derived hazard seed. Start the same
	# fixture afresh; do not reset production state by hand or change its AI.
	var arguments := OS.get_cmdline_user_args()
	var stages := [10,20,30]
	if "with40" in arguments: stages.append(40)
	var environment := "APPDATA" if OS.get_name() == "Windows" else "XDG_DATA_HOME"
	var had_environment := OS.has_environment(environment)
	var previous_environment := OS.get_environment(environment)
	var case_root := ProjectSettings.globalize_path("user://boss-cases/"+str(Time.get_ticks_usec()))
	var rows: Array = []
	for stage in stages:
		var data_path := case_root.path_join(str(stage))
		DirAccess.make_dir_recursive_absolute(data_path)
		OS.set_environment(environment,data_path)
		var command := PackedStringArray(["--headless","--fixed-fps","120","--quit-after","90000","--path",ProjectSettings.globalize_path("res://"),"res://tests/M10Bosses.tscn","--"])
		command.append_array(arguments)
		command.append("only"+str(stage))
		var captured: Array = []
		var code := OS.execute(OS.get_executable_path(),command,captured,true,false)
		var log := "\n".join(captured)
		print(log)
		var completed := false
		var issues := false
		var previous_row_count := rows.size()
		for raw_line in log.split("\n"):
			var line := raw_line.strip_edges()
			if line.begins_with("PASS "): checks += 1
			if line.begins_with("FAIL ") or line.begins_with("SCRIPT ERROR"):
				issues = true
			if line.begins_with("M10 BOSSES SUMMARY") and line.ends_with("failures=0"): completed = true
			if line.begins_with("M10 BOSS "): rows.append(JSON.parse_string(line.substr(9)))
		check(code == 0 and completed and not issues and rows.size() == previous_row_count+1 and rows.back().stage == stage,"isolated boss case completes "+str(stage))
	if had_environment: OS.set_environment(environment,previous_environment)
	else: OS.unset_environment(environment)
	var tier := "full"
	for arg in arguments:
		if arg in ["middle","high","full"]: tier = arg
	var prefix := "r1-boss-" if "--r1" in arguments else "boss-"
	var file := FileAccess.open("res://docs/iteration/evidence/m10/"+prefix+tier+".json",FileAccess.WRITE)
	file.store_string(JSON.stringify(rows,"\t")); file.close()
	print("M10 BOSSES SUMMARY checks=",checks," failures=",failures)
	get_tree().quit(1 if failures else 0)

func _process(delta):
	var boss = LevelServer.get_boss()
	if driving and is_instance_valid(boss):
		# A zone can increment a geometry counter during windup (e.g. charge).
		# Only perform_attack's serial proves that the authored attack executed.
		var serial := int(boss.actions.get("attack",0))
		if serial > observed_attack_serial:
			executed_attacks[boss.attack_kind] = true
			observed_attack_serial = serial
	super._process(delta)

func _ready():
	if DisplayServer.get_name() == "headless" and isolated_stage() == 0:
		run_isolated_cases()
		return
	# Headless render speed is machine-dependent. M8Runtime's bot and gun
	# timers run on that clock, so a seed alone does not fix their physics phase.
	# The isolated child uses --fixed-fps 120 (two renders per 60 Hz
	# physics tick). Free firing, the 8 HP pool and production AI stay intact.
	if DisplayServer.get_name() == "headless":
		await get_tree().process_frame
		check(is_equal_approx(get_process_delta_time(),Engine.time_scale/120.0),"headless boss driver uses the fixed 120 Hz render clock")
		if failures: get_tree().quit(1); return
	await boot()
	var tier = "full"
	for arg in OS.get_cmdline_user_args():
		if arg in ["middle","high","full"]: tier = arg
	var gun_id = {"middle":117,"high":113,"full":124}[tier]
	var rows = []
	# Stage 40 is the new Hell final boss. It is covered in full by tests/B5Bosses.gd, and
	# included here only when asked for, so this scene's cost stays where the gate expects it.
	var stages = [10,20,30]
	if "with40" in OS.get_cmdline_user_args(): stages.append(40)
	for stage in stages:
		if "only10" in OS.get_cmdline_user_args() and stage != 10: continue
		if "only30" in OS.get_cmdline_user_args() and stage != 30: continue
		if "only20" in OS.get_cmdline_user_args() and stage != 20: continue
		if "only40" in OS.get_cmdline_user_args() and stage != 40: continue
		stop(); dismiss()
		executed_attacks.clear(); observed_attack_serial = 0
		if Utils.player.is_dead: PlayerData.resurrectPlayer(PlayerData.player_hp_max,100)
		configure(gun_id,true); PlayerData.player_level = 1; PlayerData.player_exp = 0; Demo.refresh()
		PlayerData.player_hp_max = 8
		PlayerData.player_hp = PlayerData.player_hp_max
		check(LevelServer.town.depart(stage,true),"boss depart "+str(stage))
		var directors = get_tree().get_nodes_in_group("hazard_director")
		print("BOSS INITIAL ",JSON.stringify({"stage":stage,"epoch":LevelServer.epoch,"bot_clock":bot_clock,"dash_cooldown":dash_cooldown,"talent_cooldowns":Demo.talent_cooldowns,"shield_age":Demo.shield_age,"hazard_seed":directors[0].rng.seed if not directors.is_empty() else 0}))
		var boss = instance_from_id(LevelServer.boss_instance)
		var start = Time.get_ticks_msec(); var start_tick := Engine.get_physics_frames()
		var hp = PlayerData.player_hp; var incoming = 0.0; var hits = 0
		var trace = {"actions":{},"travel":0.0,"phase_two":false}
		var telemetry = 0; var projectile_peak = 0
		var warnings = {}
		var timeline: Array = []
		var previous_event := ""
		var actual_hits = {"total":0,"boss":0,"damage":0.0}
		var hit_observer = func(_raw,applied,from_boss):
			actual_hits.total += 1; actual_hits.damage += applied
			if from_boss: actual_hits.boss += 1
		Utils.player.incoming_hit.connect(hit_observer)
		# Sample actual health changes and production action counters; no forced attacks/damage.
		shots_fired = 0; movement = 0; last_position = Utils.player.global_position; target_boss = true; driving = true
		while LevelServer.state == "COMBAT" and Engine.get_physics_frames()-start_tick < 210*Engine.physics_ticks_per_second:
			await wait(0.05)
			projectile_peak = maxi(projectile_peak,get_tree().get_nodes_in_group("combat_transient").filter(func(n): return n.get_script()==load("res://game/monster/EnemyShot.gd")).size())
			if PlayerData.player_hp<hp: hits += 1
			incoming += maxf(0,hp-PlayerData.player_hp); hp = PlayerData.player_hp
			if is_instance_valid(boss): trace = {"actions":boss.actions.duplicate(),"travel":boss.travelled,"phase_two":boss.phase_two,"remaining_hp":boss.HP}
			if is_instance_valid(boss):
				var event := "%s:%s:%s:%s:%s" % [boss.phase,boss.attack_kind,boss.phase_three,trace.actions.get("attack",0),trace.actions.get("ultimate_activated",0)]
				if event != previous_event:
					previous_event = event
					timeline.append({"seconds":float(Engine.get_physics_frames()-start_tick)/Engine.physics_ticks_per_second,"us":Time.get_ticks_usec(),"tick":Engine.get_physics_frames(),"frame":Engine.get_process_frames(),"phase":boss.phase,"kind":boss.attack_kind,"tier":3 if boss.phase_three else (2 if boss.phase_two else 1),"hp":boss.HP,"attack_serial":trace.actions.get("attack",0),"ultimate_activated":trace.actions.get("ultimate_activated",0)})
			if is_instance_valid(boss) and boss.phase=="warn":
				for zone in get_tree().get_nodes_in_group("hostile_zone"):
					if zone.owner_ref and zone.owner_ref.get_ref()==boss and zone.elapsed<zone.warning and zone.is_visible_in_tree(): warnings[boss.attack_kind] = zone.mode
			if is_instance_valid(boss) and Time.get_ticks_msec()-telemetry>5000:
				telemetry = Time.get_ticks_msec(); print("BOSS TICK ",JSON.stringify({"stage":stage,"seconds":(telemetry-start)/1000.0,"player":str(Utils.player.global_position),"boss":str(boss.global_position),"target":str(boss.desired_point),"step":str(boss.cached_step),"line":Combat.clear_line(boss.global_position,Utils.player.global_position),"hp":boss.HP,"phase":boss.phase,"attacks":boss.actions.get("attack",0)}))
		var row = {"tier":tier,"stage":stage,"gun":gun_id,"seconds":float(Engine.get_physics_frames()-start_tick)/Engine.physics_ticks_per_second,"wall_seconds":(Time.get_ticks_msec()-start)/1000.0,"physics_ticks":Engine.get_physics_frames()-start_tick,"physics_hz":Engine.physics_ticks_per_second,"clear":LevelServer.state=="CAMP" and not Utils.player.is_dead,"death":Utils.player.is_dead,"damage_received":incoming,"successful_hits":hits,"player_movement":movement,"shots":shots_fired,"boss":trace,"effective":Utils.player.gun.effective.duplicate(true)}
		Utils.player.incoming_hit.disconnect(hit_observer)
		row.damage_received = actual_hits.damage; row.successful_hits = actual_hits.total; row.boss_successful_hits = actual_hits.boss
		row.observed_warnings = warnings
		row.timeline = timeline
		row.executed_attacks = executed_attacks.duplicate()
		row.projectile_peak = projectile_peak
		check(trace.actions.get("ultimate_activated",0)>0,"boss used ultimate "+str(stage))
		# Retain the original 8 HP mechanism contract: real resolution (clear or
		# death), damage, every base attack and the activated ultimate. Actual
		# survival/TTK is reported; B5Bosses separately requires real clears for
		# all four bosses. No forced attack, damage or extra HP is used here.
		var authored_hp = M5Content.definition(DemoConfig.ENCOUNTERS[stage].boss).hp
		check(row.clear or row.death,"the boss fight resolves "+str(stage))
		check(trace.get("remaining_hp",authored_hp) <= authored_hp*0.75,
			"boss really lost more than a quarter of its HP "+str(stage))
		if "--expect-clear" in OS.get_cmdline_user_args():
			check(row.clear,"a strong build clears the three-phase boss "+str(stage))
		for attack in BASE_ATTACKS[stage]:
			check(trace.actions.get(attack,0)>0,"boss executed "+attack)
			check(executed_attacks.has(attack),"boss perform_attack observed "+attack)
			if "--r1" in OS.get_cmdline_user_args(): check(warnings.has(attack),"boss actual windup telegraph "+attack)
		rows.append(row); print("M10 BOSS ",JSON.stringify(row))
		var suffix = "-"+str(stage) if isolated_stage() else ""
		var prefix = "r1-boss-" if "--r1" in OS.get_cmdline_user_args() else "boss-"
		var file = FileAccess.open("res://docs/iteration/evidence/m10/"+prefix+tier+suffix+".json",FileAccess.WRITE); file.store_string(JSON.stringify(rows,"\t")); file.close()
		stop(); LevelServer.return_to_camp(); dismiss(); await wait(0.8)
		check(get_tree().get_nodes_in_group("monsters").is_empty() and get_tree().get_nodes_in_group("combat_transient").is_empty(),"boss cleanup "+str(stage))
	print("M10 BOSSES SUMMARY checks=",checks," failures=",failures)
	if failures: get_tree().quit(1)
	else: await Demo.quit_game()
