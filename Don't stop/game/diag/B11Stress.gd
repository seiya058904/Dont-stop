extends Node

## B11.1 test-only deterministic stress driver: the reproduction the human report needs.
##
## WHY THIS FILE EXISTS, AND WHY IT IS SHAPED LIKE THIS.
## B11 measured "Stage 39 for 75 s" and reported averages, and concluded Stage 39 was fine. The
## human then reported that it is NOT fine: the stutter happens in the INSTANT a burst of lasers
## and attacks converges on a rooted player. An average over a whole round cannot show that, and
## neither can a node count. So this driver measures the thing the report is about:
##
##   * FRAME SPIKES, not FPS. Per frame: p95, p99, max, how many frames were over 25/33/50 ms, and
##     the longest unbroken run of slow frames. An average that never moves can hide a 120 ms hitch.
##   * EVERY SPIKE IS TAGGED with what was happening on that frame - rooted or not, inside one
##     lane or several, a hit landed or not. The summary prints one line per condition, so "the
##     frame cost X when rooted inside 3+ firing lanes" is a measured number and not a guess.
##   * COST COUNTERS WITH THEIR PRODUCERS (game/diag/B11Probe.gd): wall-clipping raycasts per
##     second, `Combat.clear_line()` queries per second, incoming hits per second AND per physics
##     frame, damage-number churn, fog-pierce churn. A frame time says a frame was expensive; these
##     say which code path was being asked to do the work.
##
## WHAT IS REAL. Every actor is the shipped one: the round is `LevelServer.town.depart(39, true)`
## through the real encounter table, the real director, the real spawn validation, the real
## `M5Content.spawn()`; the lasers are real `TacticalEnemy` E14/E13 elites running their own AI and
## creating real `HostileZone` footprints that fire on the real damage pipeline; the root is
## `Hero.apply_root()`, the one root system the game has, with its real 1.2 s immunity; the fog is
## the real `ArenaVisibility`. Nothing here fakes a load with bare Nodes.
##
## WHAT IS TEST-ONLY. `?stress=1` is the only way in; no product code path reaches this file. The
## optional amplifier (`lasers=N`) spawns real Elite laser sentinels through the SAME production
## spawn call the director uses, on top of the director's own cap, purely so the "many lanes at
## once" moment is repeatable instead of luck; it is recorded in the evidence as an amplifier and
## the product's own cap is untouched. The driver also keeps the player alive (a level-1 health bar
## would end the round before the peak) and grants the reward set a Hell player would own, so the
## incoming-damage path is measured with the reward tree really populated instead of empty.

# ---- configuration, from the loader's query string ------------------------------------------
var stage := 39
var seconds := 90
var scenario := "A"
var run_seed := 20260918
var lasers := 0
var root_period := 0.0
var park := false
var label := "run"
## B11.2: how many ordinary monsters the density amplifier tops the arena up to, and how many
## barrage attackers it keeps alive. Both are TOP-UPS onto the director's own population, never a
## replacement for it, and neither can push the population past the stage's own published cap.
var enemies := 0
var barrage := 0
## B11.2: comma-separated purely-visual switches for the isolation A/B. Empty means "everything on",
## which is the shipped state.
var iso := ""
var presentation_weapons: Array[int] = []
var presentation_weapon := -1
var presentation_boss_log: Array = []
var presentation_boss_phase := ""
var presentation_boss_entry: Dictionary = {}
var presentation_boss_hold := false
var presentation_ultimate_count := -1

# ---- per-frame samples (parallel packed arrays: no per-frame allocation) ---------------------
var _ms := PackedFloat32Array()
var _engine_ms := PackedFloat32Array()
var _ticks := PackedInt64Array()
var _process_frames := PackedInt64Array()
var _absolute_ticks := PackedInt64Array()
var _epochs := PackedInt64Array()
var _long_frames: Array = []
var _round_contexts: Array = []
var _load_samples: Array = []
var _sample_tick_start := 0
var _driver_active := false
var source_variant := "b19-2-working-tree"
var normal_hp := false
var measurement_timeout := false

# B19.2: this clock advances only while combat is actionable.
var _effective_tick := 0
var _next_amp_tick := 0
var _next_root_tick := 0
var measurement := "light"
var run_mode := "diagnostic"
var spawn_reachability_cache := true
var _observation_frames := 0
var _measured_wall_s := 0.0
var camp_cycles := 0
var _camp_checks: Array = []
var _surface: Dictionary = {}
var controlled_boss := false
var boss_complete := false
var _boss_ready_tick := -1
var _phase_satisfied_tick := -1
var _boss_gate_phase := ""
var _retired_actions: Dictionary = {}
var _pause_usec := 0
var _retired_bounces := 0
var _shots_admitted := 0
var _safe_active := false
var _safe_phase3_seen := false
var _safe_phase3_finished_emitted := -1
var _safe_peak_shots := 0
var _capacity_planned := 0
var _capacity_blocked := 0
var _capacity_emitted := 0
var _capacity_sequence := 0
var _pressure_samples := 0
var _pressure_live_ge_90 := 0
var _pressure_visible_ge_90 := 0
var _pressure_live_min := 0
var _pressure_live_max := 0
var _events: Array = []
var _entry_samples: Array = []
var _orbit_log: Array = []
var _orbit_serial := 0
var _release_until_tick := 0
var _next_aim_tick := 0
const CAPACITY_REFILL_TICKS := 4
func _physics_process(_delta: float) -> void:
	if not _driver_active or get_tree().paused or LevelServer.state != "COMBAT": return
	if not is_instance_valid(Utils.player) or Utils.player.is_dead: return
	_effective_tick += 1
	var tick := _effective_tick
	if not normal_hp: PlayerData.player_hp = PlayerData.player_hp_max
	if tick >= _next_amp_tick:
		var top_up_started := Time.get_ticks_usec()
		var births_before := _topped_up
		_next_amp_tick = tick+4*Engine.physics_ticks_per_second
		if lasers > 0 and _meta_alive("b11_amplified") < lasers: _amplify_lasers()
		if barrage > 0 and _meta_alive("b11_barrage") < barrage: _amplify_barrage()
		if enemies > 0 and _live_enemies() < mini(enemies,_stage_cap()): _top_up_enemies()
		_remember_spawn_stats()
		_events.append({"tick":tick,"event":"top_up","usec":Time.get_ticks_usec()-top_up_started,"ordinary_added":_topped_up-births_before})
	if root_period > 0.0 and tick >= _next_root_tick:
		_next_root_tick = tick+maxi(1,int(root_period*Engine.physics_ticks_per_second))
		_driver_root_attempts += 1
		if Utils.player.apply_root(0.45): _driver_roots += 1
	_observe_boss_tick()
	# The fixture is a real EnemyShot stream, not a frame-by-frame counter. A 15 Hz
	# refill at 60 physics Hz replaces retired shots while avoiding a
	# deferred group scan on every 60 Hz physics tick.
	if scenario == "P" and tick % CAPACITY_REFILL_TICKS == 0: _capacity_tick.call_deferred()
	if not park: _drive_movement(int(tick*1000/Engine.physics_ticks_per_second))
	if (stage != 40 and seconds < 45 and tick >= seconds*Engine.physics_ticks_per_second) or (stage == 40 and boss_complete):
		LevelServer.return_to_camp()
		return
	if not presentation_weapons.is_empty():
		var slot := int(tick/(8*Engine.physics_ticks_per_second)) % presentation_weapons.size()
		if presentation_weapon != presentation_weapons[slot]:
			presentation_weapon = presentation_weapons[slot]
			Utils.player.changeWeapon(presentation_weapon)
			_release_until_tick = tick+10
	if (stage == 40 and presentation_boss_hold) or tick < _release_until_tick or (presentation_weapon == 113 and tick % (Engine.physics_ticks_per_second*2) < 7):
		Input.action_release("shoot")
	else: Input.action_press("shoot")
	if tick >= _next_aim_tick:
		_next_aim_tick = tick+6
		var nearest = LevelServer.get_boss() if stage == 40 else null
		if is_instance_valid(nearest):
			Utils.aim_override = get_viewport().get_canvas_transform()*(nearest.global_position-Vector2(0,8))
			return
		var best := INF
		for actor in get_tree().get_nodes_in_group("monsters"):
			if actor.is_die or actor.is_queued_for_deletion(): continue
			var distance: float = actor.global_position.distance_squared_to(Utils.player.global_position)
			if distance < best:
				best = distance; nearest = actor
		if is_instance_valid(nearest): Utils.aim_override = get_viewport().get_canvas_transform()*(nearest.global_position-Vector2(0,8))

## ENGINE_WINDOW_PEAK_MONITOR: engine-window monitor readings, not per-frame
## CPU durations. Retain raw readings and maxima only; never CPU percentiles.
var _phys := PackedFloat32Array()
var _proc := PackedFloat32Array()
## Draw calls per frame: the reading that answers "did the fog/telegraph rendering grow".
var _draws := PackedInt32Array()
var _flags := PackedInt32Array()
var _beams := PackedInt32Array()
var _combat_seconds := PackedFloat32Array()
var _round_of := PackedInt32Array()

const F_ROOTED := 1
const F_HIT := 2
const F_RAY := 4
const F_CLEAR := 8
const F_LANE := 16

# ---- gauges sampled at 10 Hz: peaks matter, per-frame group scans would perturb the thing ----
var _peak := {"enemies":0,"zones":0,"beams":0,"hazards":0,"vfx":0,"transients":0,"labels":0,
	"projectiles":0,"nodes":0,"rewards":0,"objects":0,"orphans":0,"mem":0.0,"render_objects":0}
var _created := 0
var _removed := 0
var _prev := {}
var _prev_pq := 0
var _pq_total := 0
var _last_report_index := 0
var _peak_same_frame := 0

# ---- round bookkeeping -----------------------------------------------------------------------
var _rounds := 0
var _total_combat_s := 0.0
var _root_windows := 0
var _driver_roots := 0
var _driver_root_attempts := 0
var _amplified := 0
var _topped_up := 0
var _ordinary_requests := 0
var _elite_requests := 0
var _elite_promotions := 0
var _spawn_peak := {"requests":0,"geometry_rejected":0,"clearance_queries":0,"clearance_rejected":0,
	"path_checks":0,"path_queries":0,"path_cache_hits":0,"path_reachable":0,"path_rejected":0}

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for arg in OS.get_cmdline_args() + OS.get_cmdline_user_args():
		if arg.begins_with("--stress-stage="): stage = int(arg.substr(15))
		elif arg.begins_with("--stress-seconds="): seconds = int(arg.substr(17))
		elif arg.begins_with("--stress-scenario="): scenario = arg.substr(18)
		elif arg.begins_with("--stress-seed="): run_seed = int(arg.substr(14))
		elif arg.begins_with("--stress-lasers="): lasers = int(arg.substr(16))
		elif arg.begins_with("--stress-root="): root_period = float(arg.substr(14))
		elif arg.begins_with("--stress-park="): park = arg.substr(14) == "1"
		elif arg.begins_with("--stress-enemies="): enemies = int(arg.substr(17))
		elif arg.begins_with("--stress-barrage="): barrage = int(arg.substr(17))
		elif arg.begins_with("--stress-iso="): iso = arg.trim_prefix("--stress-iso=")
		elif arg.begins_with("--stress-label="): label = arg.substr(15)
		elif arg.begins_with("--stress-source="): source_variant = arg.substr(16)
		elif arg == "--stress-normal-hp": normal_hp = true
		elif arg.begins_with("--stress-measurement="): measurement = arg.substr(21)
		elif arg.begins_with("--stress-mode="): run_mode = arg.trim_prefix("--stress-mode=")
		elif arg == "--stress-no-spawn-cache": spawn_reachability_cache = false
		elif arg == "--stress-controlled-boss": controlled_boss = true
		elif arg.begins_with("--stress-camp-cycles="): camp_cycles = int(arg.substr(21))
		elif arg.begins_with("--stress-weapons="):
			for key in arg.substr(17).split(",",false):
				if Utils.weapon_list.has(str(int(key))): presentation_weapons.append(int(key))
	B11Probe.enabled = measurement == "detail"
	B11Probe.spawn_reachability_cache = spawn_reachability_cache
	_apply_iso()
	get_tree().node_added.connect(_count_added)
	get_tree().node_removed.connect(_count_removed)
	print("[stress] mode=on scenario=%s stage=%d seconds=%d seed=%d lasers=%d root=%.2f park=%s enemies=%d barrage=%d iso=%s label=%s" % [
		scenario,stage,seconds,run_seed,lasers,root_period,str(park),enemies,barrage,
		("none" if iso == "" else iso),label])
	run.call_deferred()

## B11.2 visual isolation. Test-only, and deliberately blunt: each name switches off exactly one
## purely-visual product and nothing else. Damage, collision, timing, AI, spawning and the essential
## telegraph footprint keep running, so a frame-cost difference can only come from the ink.
func _apply_iso() -> void:
	var parts := iso.split(",",false)
	B11Probe.iso_vfx = "vfx" in parts
	B11Probe.iso_labels = "labels" in parts
	B11Probe.iso_trails = "trails" in parts
	B11Probe.iso_fog_core = "fogcore" in parts
	B11Probe.iso_td_decor = "tddecor" in parts
	B11Probe.iso_particles = "particles" in parts
	if iso != "":
		print("[stress] iso vfx=%s labels=%s trails=%s fogcore=%s tddecor=%s particles=%s" % [
			str(B11Probe.iso_vfx),str(B11Probe.iso_labels),str(B11Probe.iso_trails),
			str(B11Probe.iso_fog_core),str(B11Probe.iso_td_decor),str(B11Probe.iso_particles)])

func _count_added(node: Node) -> void:
	_created += 1
	if node.get_script() == preload("res://game/monster/EnemyShot.gd"):
		if node.registered: _shots_admitted += 1
		node.tree_exiting.connect(_retire_shot.bind(node),CONNECT_ONE_SHOT)
	if "bodyink" in iso and node is BaseMonster:
		node.ready.connect(func(): node.get_node("body").hide(),CONNECT_ONE_SHOT)
	if "shotink" in iso and node.get_script() == preload("res://game/monster/EnemyShot.gd"):
		node.ready.connect(node.hide,CONNECT_ONE_SHOT)
	# node_added precedes _ready; ready is emitted after the production decision.
	if node.get_script() == preload("res://game/monster/TacticalEnemy.gd"):
		node.ready.connect(_fix_fixture_orbit.bind(node), CONNECT_ONE_SHOT)

func _fix_fixture_orbit(node: Node) -> void:
	node.tree_exiting.connect(_retire_source.bind(node),CONNECT_ONE_SHOT)
	_orbit_serial += 1
	var original: float = node.orbit_side
	node.orbit_side = 1.0 if _orbit_serial % 2 else -1.0
	_orbit_log.append({"serial":_orbit_serial,"role":node.role,"original":original,"fixture":node.orbit_side,"tick":_effective_tick})
func _retire_shot(node: Node) -> void:
	_retired_bounces += node.bounces_done

func _retire_source(node: Node) -> void:
	for key in node.actions:
		_retired_actions[key] = int(_retired_actions.get(key,0))+int(node.actions[key])

func _count_removed(_node: Node) -> void: _removed += 1

## The stress scenario is the whole point of the round, so it is stated once and named.
##
## B11.1 shaped A-D around the laser/root overlap, because that was the report at the time. B11.2's
## report is different in kind - "the whole picture is busy and it still hitches" - so the same four
## names now carry the four LOAD PROFILES the round has to separate. Everything that produces them
## is still a shipped actor on a shipped code path; the amplifiers only decide how many arrive.
##   A  normal Stage 39, exactly as shipped. The control.
##   B  dense enemies: real Stage 39 monsters topped up toward the stage's own cap, attacks normal.
##      Isolates "many bodies" from "many attacks".
##   C  dense attacks: the real laser/artillery/root/poison families held alive at once, population
##      normal. Isolates "many attacks" from "many bodies".
##   D  worst visual load: 80+ bodies AND the full attack mix AND the rooted/held position, with the
##      player firing. This is the "场上累积的各种特效和怪非常多" frame the human described.
func _apply_scenario() -> void:
	match scenario:
		"A": pass
		"B": enemies = maxi(enemies,60)
		"C": lasers = maxi(lasers,4); root_period = maxf(root_period,2.0); barrage = maxi(barrage,6)
		"D", "P":
			enemies = maxi(enemies,180 if scenario == "P" else 80); lasers = maxi(lasers,4); root_period = maxf(root_period,2.0)
			barrage = maxi(barrage,6); park = true
	if enemies > 0: enemies = mini(enemies,_stage_cap())
	print("[stress] effective scenario=%s lasers=%d root_period=%.2f park=%s enemies=%d/%d barrage=%d" % [
		scenario,lasers,root_period,str(park),enemies,_stage_cap(),barrage])

## The stage's own published simultaneous cap, read from the shipped encounter table. The amplifiers
## below can never take the population past it - that is the B11 contract and this round does not
## touch it.
func _stage_cap() -> int:
	var table: Dictionary = M5Content.encounters()
	if table.has(stage): return int(table[stage].get("cap",0))
	return 0

## The stage's own role list, so a top-up is drawn from the real composition instead of an invented
## one. Stage 39 is `E01 E02 E14 E02 E13 E01 E02 E15 E02 E10`.
func _stage_roles() -> Array:
	var table: Dictionary = M5Content.encounters()
	if table.has(stage): return table[stage].get("roles",[])
	return ["E01","E02"]

func _live_enemies() -> int:
	var count := 0
	for actor in get_tree().get_nodes_in_group("monsters"):
		if actor.is_die: continue
		count += 1
	return count

func run() -> void:
	await get_tree().create_timer(3.0).timeout
	Demo.test_mode = true
	_apply_scenario()
	await _boot_to_camp()
	# A Web launch restores `equipped` from the save but not the live gun, so the rig arms itself
	# the way a player would have to. Identical in the BEFORE and the AFTER build.
	if Utils.player != null and Utils.player.gun == null:
		PlayerData.add_weapon(Utils.weapon_list["0"].instantiate())
		PlayerData.changeWeapon(0,true)
	if label == "presentation-rng":
		# _boot_to_camp queued the initial panel for deletion. Let that complete
		# before open_panel checks Demo.ui; a queued-but-live panel is not reusable.
		await get_tree().process_frame
		await get_tree().process_frame
		# An explicit observer-only check of the complete production animation.
		# Run in both original and changed Web exports; never an acceptance load.
		seed(20260919)
		var sequence: Array = []
		for i in 9: sequence.append(randi())
		seed(20260919)
		Utils.player.gun._shootAnim()
		var observed: Array = []
		for i in 6: observed.append(randi())
		print("[presentation-rng] ",JSON.stringify({"sequence":sequence,"observed":observed,"matches_legacy":observed==sequence.slice(3,9),"animation_ran":Utils.player.gun.tier_muzzle.remaining>0}))
		Demo.open_panel()
		await get_tree().create_timer(0.1).timeout
		var camp_rows: Array = []
		for quality in [0,1,2,3,4,5]:
			Demo.ui.tier_filter = quality
			seed(20260919)
			var camp_sequence: Array = []
			for i in 16: camp_sequence.append(randi())
			seed(20260919)
			Demo.ui.render()
			var camp_observed: Array = []
			for i in 6: camp_observed.append(randi())
			# Pair these complete production-render sequences with the original export.
			# Standalone particle instantiation is not a substitute for that full path.
			camp_rows.append({"quality":quality,"draws":camp_sequence.find(camp_observed[0]),"observed":camp_observed,"tab":Demo.ui.tab,"rows":Demo.ui.detail_actions.size()})
		print("[presentation-camp-rng] ",JSON.stringify(camp_rows))
		_close_panels()
		return
	# The reward tree a Hell player owns. Without this the incoming-damage path scans an EMPTY
	# reward group and the harness would report that path as free.
	_grant_everything()
	if label.begins_with("b19-2-visual"):
		var visual = load("res://game/diag/B192Visual.gd").new()
		add_child(visual)
		await visual.run()
		await Demo.quit_game()
		return
	if not normal_hp:
		PlayerData.player_hp_max = 1000000.0
		PlayerData.player_hp = 1000000.0
	Utils.set_gameplay_mouse_mode()
	await get_tree().create_timer(0.6).timeout
	# Stage 39 is a 45 s survival round, so the requested window is accumulated over consecutive
	# rounds. The protocol is identical in the BEFORE and the AFTER build.
	while _total_combat_s < float(seconds) and _rounds < 1:
		await _one_round()
	Input.action_release("shoot")
	Utils.aim_override = null
	print("[stress] done scenario=%s rounds=%d frames=%d combat_s=%.1f" % [
		scenario,_rounds,_ms.size(),_total_combat_s])
	_dump()
	if camp_cycles > 0: await _check_camp_cycles()
	var b18_mode = false
	for arg in OS.get_cmdline_args()+OS.get_cmdline_user_args():
		if arg == "--b18": b18_mode = true
	if b18_mode:
		await Demo.quit_game()
		return
	await Demo.quit_game()

func _check_camp_cycles() -> void:
	for cycle in camp_cycles:
		LevelServer.return_to_camp()
		_close_panels()
		await get_tree().create_timer(0.8).timeout
		_camp_checks.append({"cycle":cycle+1,"nodes":get_tree().get_node_count(),"objects":Performance.get_monitor(Performance.OBJECT_COUNT),"resources":Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT),"orphans":Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT) if OS.is_debug_build() else null,"static_memory":Performance.get_monitor(Performance.MEMORY_STATIC) if OS.is_debug_build() else null,"enemies":get_tree().get_nodes_in_group("monsters").size(),"shots":preload("res://game/monster/EnemyShot.gd").live_count,"transients":get_tree().get_nodes_in_group("combat_transient").size(),"epoch":LevelServer.epoch})
		if cycle+1 < camp_cycles:
			LevelServer.town.depart(stage,true)
			await get_tree().create_timer(1.0).timeout
	print("[stress-convergence] ",JSON.stringify(_camp_checks))

func _boot_to_camp() -> void:
	if not Utils.is_game_start:
		Utils.gameStart()
		Demo.open_panel()
		await get_tree().create_timer(1.0).timeout
		_close_panels()
	var deadline := Time.get_ticks_msec() + 180000
	while Time.get_ticks_msec() < deadline:
		if Utils.is_game_start and LevelServer.state == "CAMP" and Demo.pause_stack.is_empty(): return
		await get_tree().create_timer(0.5).timeout

func _close_panels() -> void:
	for menu in Demo.pause_stack.duplicate():
		menu.queue_free()
		Demo.pop_pause(menu)

func _one_round() -> void:
	LevelServer.return_to_camp()
	var deadline := Time.get_ticks_msec() + 60000
	while Time.get_ticks_msec() < deadline and LevelServer.state != "CAMP":
		await get_tree().create_timer(0.25).timeout
	_close_panels()
	await get_tree().create_timer(0.6).timeout
	Utils.set_gameplay_mouse_mode()
	# Seeded here, after the previous round's reward draw and the camp refresh, so the random
	# stream a round consumes is the same in every run and in both builds.
	# Reuse the production camp departure preparation, with its separate timing.
	if is_instance_valid(Warmup):
		await Warmup.prepare_web_combat()
	seed(run_seed)
	_rounds += 1
	var depart_usec := Time.get_ticks_usec()
	var departed: bool = LevelServer.town.depart(stage,true)
	print("[stress] round=%d depart=%s state=%s" % [_rounds,str(departed),LevelServer.state])
	deadline = Time.get_ticks_msec() + 120000
	while Time.get_ticks_msec() < deadline and LevelServer.state != "COMBAT":
		await get_tree().create_timer(0.25).timeout
	_entry_samples.append({"round":_rounds,"depart_to_combat_ms":(Time.get_ticks_usec()-depart_usec)/1000.0,"state":LevelServer.state})
	if LevelServer.state != "COMBAT": return
	await _sample_round()

## The sampling loop. One pass per rendered frame; the cost of the observation itself is bounded
## to a handful of integer reads plus a few packed-array appends, because a harness that allocates
## per frame would end up measuring itself.
func _sample_round() -> void:
	if OS.has_feature("web"): JavaScriptBridge.eval("performance.mark('b194-combat-start')")
	_surface = {"window":str(get_window().size),"visible_rect":str(get_viewport().get_visible_rect()),"texture_size":str(get_viewport().get_texture().get_size()),"canvas_transform":str(get_viewport().get_canvas_transform()),"stretch_transform":str(get_viewport().get_stretch_transform()),"content_scale_size":str(get_window().content_scale_size),"vsync":DisplayServer.window_get_vsync_mode(),"max_fps":Engine.max_fps,"physics_hz":Engine.physics_ticks_per_second,"engine":Engine.get_version_info(),"renderer":RenderingServer.get_current_rendering_method(),"display_server":DisplayServer.get_name(),"public_release":OS.has_feature("public_release")}
	if OS.has_feature("web") and measurement == "detail": JavaScriptBridge.eval("performance.mark('b192-combat-start')")
	var round_index := _rounds
	_round_contexts.append({"round":round_index,"epoch":LevelServer.epoch,"scene":get_tree().current_scene.scene_file_path,"stage":stage,"scenario":scenario})
	var started := Time.get_ticks_msec()
	var previous_usec := Time.get_ticks_usec()
	_sample_tick_start = Engine.get_physics_frames()
	_effective_tick = 0
	_next_amp_tick = 1
	_next_root_tick = 1
	_driver_active = true
	_release_until_tick = 10
	_next_aim_tick = 0
	var next_report := started + 1000
	var next_gauge := 0
	var prev_rooted := false
	var ray_prev: int = B11Probe.raycasts
	var clear_prev: int = B11Probe.clear_line_calls
	var hit_prev: int = B11Probe.player_hits
	while LevelServer.state == "COMBAT" and is_instance_valid(Utils.player) and not Utils.player.is_dead:
		# The rig cannot die: a level-1 health bar would end the round before the peak.
		var now := Time.get_ticks_msec()
		var elapsed := float(now-started)/1000.0
		if elapsed > maxf(180.0 if stage == 40 else 90.0,seconds+45.0):
			measurement_timeout = true
			break
		if get_tree().paused:
			var pause_start := Time.get_ticks_usec()
			await get_tree().process_frame
			_pause_usec += Time.get_ticks_usec()-pause_start
			previous_usec = Time.get_ticks_usec()
			continue
		_observation_frames += 1
		if measurement == "off":
			await get_tree().process_frame
			continue
		# A root WINDOW, so a driver-applied root and a laser-applied one are both counted and the
		# split is reported beside the total.
		var rooted: bool = Utils.player.root_remaining > 0.0
		if rooted and not prev_rooted: _root_windows += 1
		prev_rooted = rooted
		var flags := 0
		if rooted: flags |= F_ROOTED
		if B11Probe.player_hits != hit_prev: flags |= F_HIT; hit_prev = B11Probe.player_hits
		if B11Probe.raycasts != ray_prev: flags |= F_RAY; ray_prev = B11Probe.raycasts
		if B11Probe.clear_line_calls != clear_prev: flags |= F_CLEAR; clear_prev = B11Probe.clear_line_calls
		var beams: int = B11Probe.beams_active
		if beams >= 1: flags |= F_LANE
		var current_usec := Time.get_ticks_usec()
		_ms.append(float(current_usec-previous_usec)/1000.0)
		_process_frames.append(Engine.get_process_frames())
		_absolute_ticks.append(Engine.get_physics_frames())
		_epochs.append(LevelServer.epoch)
		if _ms[-1] > 50.0:
			_long_frames.append({"index":_ms.size()-1,"ms":_ms[-1],"round":round_index,"wall_s":elapsed,"process_frame":Engine.get_process_frames(),"physics_tick":Engine.get_physics_frames(),"epoch":LevelServer.epoch,"preceding_load_sample":_load_samples.size()-1,"events_through":_events.size()})
		previous_usec = current_usec
		_engine_ms.append(get_process_delta_time()*1000.0)
		_ticks.append(_effective_tick)
		_phys.append(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)*1000.0)
		_proc.append(Performance.get_monitor(Performance.TIME_PROCESS)*1000.0)
		_draws.append(int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)))
		_flags.append(flags)
		_beams.append(beams)
		_combat_seconds.append(elapsed)
		_round_of.append(round_index)
		if now >= next_gauge:
			next_gauge = now + 100
			_sample_gauges()
		if measurement == "detail" and now >= next_report:
			next_report = now + 1000
			_report_second(round_index)
		await get_tree().process_frame
	if OS.has_feature("web") and measurement == "detail": JavaScriptBridge.eval("performance.mark('b192-combat-end')")
	_measured_wall_s += (Time.get_ticks_msec()-started)/1000.0
	if OS.has_feature("web"): JavaScriptBridge.eval("performance.mark('b194-combat-end')")
	_driver_active = false
	Input.action_release("shoot")
	for action in ["left","right","up","down"]: Input.action_release(action)
	var round_s := 0.0
	round_s = float(_effective_tick)/Engine.physics_ticks_per_second
	_total_combat_s += round_s
	print("[stress] round=%d end state=%s round_s=%.1f total_s=%.1f" % [
		round_index,LevelServer.state,round_s,_total_combat_s])

## Real Elite laser sentinels, spawned through the SAME production call the director uses
## (`Town.monsterCreate` -> `M5Content.spawn`), so they are ordinary actors with ordinary AI,
## ordinary telegraphs, ordinary damage and an ordinary root. Only the director's timing and its
## elite ceiling are bypassed, and that is exactly what makes the "many lanes at once" moment
## repeatable instead of luck.
##
## It is a TOP-UP, not a one-off volley: the player kills a sentinel in a few seconds, so a single
## volley decayed long before the dense window and the harness was measuring an ordinary round
## again. The amplifier restores the population on a cadence so the condition the human reported -
## several lanes live at the same time, repeatedly - is what the whole run is made of.
func _amplify_lasers() -> void:
	for i in lasers:
		_spawn_amplified("E14" if i % 2 == 0 else "E13","b11_amplified")

## B11.2 dense-attack mix. These are the same four Stage 39 families that carry the attack load the
## human described - the laser sentinel (`cross_beam`), the tremor shooter (`double_root`, the only
## source of purple projectiles), the marker artillery (`root_artillery`) and the poison carrier
## (`lingering_poison`) - held alive together. Their telegraphs, projectiles, hostile zones and
## impact VFX are all produced by the actors themselves, so nothing here fakes a load.
func _amplify_barrage() -> void:
	var pool := ["E14","E10","E13","E15"]
	var i := 0
	while _meta_alive("b11_barrage") < barrage and i < pool.size():
		_spawn_amplified(pool[i],"b11_barrage")
		i += 1

## B11.2 density amplifier, and the ONE amplifier that does not promote to elite: scenario B is
## "many bodies, ordinary attacks", so this tops the population up out of the stage's own role list
## with plain actors. Bounded by the stage's published cap, which it reads from the shipped table.
func _top_up_enemies() -> void:
	var town = LevelServer.town
	if not is_instance_valid(town): return
	var target := mini(enemies,_stage_cap())
	var roles := _stage_roles()
	if roles.is_empty(): return
	var guard := 0
	while _live_enemies() < target and guard < 48:
		guard += 1
		var role := str(roles[guard % roles.size()])
		var point: Vector2 = town.spawn_point(M5Content.radius_for(role))
		if point == Vector2.INF: continue
		_ordinary_requests += 1
		var actor: Node = M5Content.spawn(role,town.monster_root,point)
		if actor == null: continue
		actor.set_meta("b11_topped_up",true)
		_topped_up += 1

## Real actor through the SAME production call the director uses
## (`Town.monsterCreate` -> `M5Content.spawn`), so it has ordinary AI, an ordinary telegraph,
## ordinary damage and an ordinary root. Only the director's timing and its elite ceiling are
## bypassed, and that is exactly what makes the dense moment repeatable instead of luck.
func _spawn_amplified(role: String, meta_key: String) -> bool:
	_elite_requests += 1
	var town = LevelServer.town
	if not is_instance_valid(town): return false
	# Reuse a real eligible actor before asking the factory for another special.
	# The factory legitimately replaces requests when the four-special budget is full.
	var actor: Node = null
	for existing in get_tree().get_nodes_in_group("monsters"):
		if existing.is_die or existing.is_queued_for_deletion(): continue
		if str(existing.get_meta("content_id","")) != role: continue
		if existing.get_meta(meta_key,false): continue
		if existing.is_elite or M5Content.can_promote(existing):
			actor = existing; break
	if actor == null:
		var point: Vector2 = town.spawn_point(M5Content.radius_for(role))
		if point == Vector2.INF: return false
		actor = M5Content.spawn(role,town.monster_root,point)
	if actor == null or str(actor.get_meta("content_id","")) != role: return false
	var was_elite: bool = actor.is_elite
	M5Content.promote_elite(actor,M5Content.elite_modifier_for(role))
	if not actor.is_elite: return false
	if not was_elite: _elite_promotions += 1
	actor.set_meta(meta_key,true)
	if label.begins_with("b19-"):
		# Explicit HP-only load fixture; leaves AI, attacks and production admission intact.
		actor.HP = 1000000.0
		if actor.get("max_hp") != null: actor.max_hp = actor.HP
		actor.set_meta("b191_hp_fixture",true)
	_amplified += 1
	return true

func _meta_alive(key: String) -> int:
	var count := 0
	for actor in get_tree().get_nodes_in_group("monsters"):
		if actor.is_die: continue
		if actor.get_meta(key,false): count += 1
	return count

func _drive_movement(now: int) -> void:
	var step := ((now/700)%4)
	for pair in [["left",0],["right",1],["up",2],["down",3]]:
		if step == int(pair[1]): Input.action_press(pair[0])
		else: Input.action_release(pair[0])

func _observe_boss_tick() -> void:
	if stage == 40 and LevelServer.get_boss() != null and (label.begins_with("presentation") or label.begins_with("b19-")):
		# Optional full-phase observation uses the established test-only aim hook.
		# Real weapon fire and real boss AI still decide all HP and transitions.
		var boss = LevelServer.get_boss()
		if is_instance_valid(boss):
			var tier = "3" if boss.phase_three else ("2" if boss.phase_two else "1")
			var safe_now: bool = not get_tree().get_nodes_in_group("boss_ultimate").is_empty()
			var emitted := int(boss.actions.get("continuous_barrage_emitted",0))
			if safe_now != _safe_active:
				_events.append({"tick":_effective_tick,"event":"safe_window_start" if safe_now else "safe_window_end","phase":tier,"shots":preload("res://game/monster/EnemyShot.gd").live_count,"continuous_emitted":emitted,"peak_shots":_safe_peak_shots})
				_safe_active = safe_now
				if safe_now: _safe_peak_shots = 0
				elif tier == "3": _safe_phase3_finished_emitted = emitted
			if safe_now:
				_safe_peak_shots = maxi(_safe_peak_shots,preload("res://game/monster/EnemyShot.gd").live_count)
				if tier == "3": _safe_phase3_seen = true
			var key = str(_rounds)+":"+tier
			if key != presentation_boss_phase:
				_phase_satisfied_tick = -1
				presentation_boss_phase = key
				presentation_boss_entry = boss.actions.duplicate()
				presentation_boss_log.append({"frame":_ms.size(),"round":_rounds,"phase":tier,"actions":boss.actions.duplicate()})
			var required: Array = boss.BOSS_CYCLES[tier][boss.role]
			presentation_boss_hold = false
			for attack in required:
				if boss.actions.get(attack,0)-presentation_boss_entry.get(attack,0) < required.count(attack): presentation_boss_hold = true
			if not presentation_boss_hold and _phase_satisfied_tick < 0: _phase_satisfied_tick = _effective_tick
			var cycle_settled: bool = _phase_satisfied_tick >= 0 and _effective_tick-_phase_satisfied_tick >= 3*Engine.physics_ticks_per_second and boss.phase == "move"
			if cycle_settled and controlled_boss and tier != "3":
				# HP gate only: production _enter_phase handles cleanup and all AI.
				boss.HP = boss.max_hp*(0.69 if tier == "1" else 0.34)
				_boss_gate_phase = key
				_events.append({"tick":_effective_tick,"event":"controlled_hp_gate","from_phase":tier})
			if tier == "3" and not presentation_boss_hold:
				if _boss_ready_tick < 0: _boss_ready_tick = _effective_tick
				boss_complete = _effective_tick-_boss_ready_tick >= 8*Engine.physics_ticks_per_second and int(boss.actions.get("ultimate_activated",0)) > int(presentation_boss_entry.get("ultimate_activated",0)) and _safe_phase3_seen and _safe_phase3_finished_emitted >= 0 and emitted > _safe_phase3_finished_emitted and not safe_now
			if controlled_boss:
				# Keep normal active fire while observing: real damage/FX still run.
				# Explicit HP floor holds this phase until its full attack cycle ends.
				if _boss_gate_phase != key: boss.HP = maxf(boss.HP,boss.max_hp*{"1":0.71,"2":0.36,"3":0.20}[tier])
				presentation_boss_hold = false
			var ultimates = int(boss.actions.get("ultimate_activated",0))
			if ultimates != presentation_ultimate_count:
				presentation_ultimate_count = ultimates
				presentation_boss_log.append({"frame":_ms.size(),"round":_rounds,"phase":tier,"ultimate_activated":ultimates,"actions":boss.actions.duplicate()})

# Capacity-only rig: ordinary production projectiles, sweep/owner/expiry intact.
# Refill after physics retirement, from a visible ring; never extends shot lifetime.
func _capacity_tick() -> void:
	if not _driver_active or LevelServer.state != "COMBAT" or not is_instance_valid(Utils.player) or not is_instance_valid(LevelServer.town.arena): return
	var shots = preload("res://game/monster/EnemyShot.gd")
	var origin: Vector2 = Utils.player.global_position
	# Yield only slots already requested by real continuous sources. This rig
	# runs after their physics callbacks, so it cannot take a newly freed slot
	# before a production source can try it. At most 18 reserved = 90% cap.
	var reserved := 0
	for actor in get_tree().get_nodes_in_group("monsters"):
		var stream = actor.get_node_or_null("ContinuousBarrage")
		if is_instance_valid(stream) and stream.wave_pending: reserved += stream.count
	reserved = mini(reserved,18)
	var missing: int = maxi(0,shots.capacity_limit-reserved-shots.live_count)
	_capacity_planned += missing
	for i in missing:
		var angle := float(_capacity_sequence)*2.3999632297
		_capacity_sequence += 1
		var point := origin+Vector2.RIGHT.rotated(angle)*65.0
		if not LevelServer.town.arena.point_clear(point,4.0):
			_capacity_blocked += 1
			continue
		var pellet = shots.new()
		pellet.global_position = point
		pellet.velocity = Vector2.RIGHT.rotated(angle+1.2)*125.0
		pellet.damage = 0.16
		pellet.style = "ricochet" if _capacity_sequence%2 else "laser"
		pellet.bounces_left = 1 if _capacity_sequence%2 else 0
		get_tree().current_scene.add_child(pellet)
		_capacity_emitted += 1

func _sample_gauges() -> void:
	if "fogink" in iso:
		var fog = FogPierce.instance()
		if is_instance_valid(fog): fog.canvas.hide()
	var live := get_tree().get_nodes_in_group("monsters").filter(func(m): return not m.is_die).size()
	if live > int(_peak.enemies): _peak.enemies = live
	for spec in [["zones","hostile_zone"],["hazards",StageHazard.GROUP],["vfx","hostile_vfx"],
			["transients","combat_transient"],["labels","damage_labels"],
			["projectiles","enemy_projectiles"],["rewards","reward"]]:
		var size := get_tree().get_nodes_in_group(spec[1]).size()
		if size > int(_peak[spec[0]]): _peak[spec[0]] = size
	if B11Probe.beams_active > int(_peak.beams): _peak.beams = B11Probe.beams_active
	var nodes := get_tree().get_node_count()
	if nodes > int(_peak.nodes): _peak.nodes = nodes
	# B11.2 engine-level gauges. Sampled here rather than per frame because they are whole-engine
	# counters and the sampling cost has to stay common to both builds.
	var objects := int(Performance.get_monitor(Performance.OBJECT_COUNT))
	if objects > int(_peak.objects): _peak.objects = objects
	var orphans := int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	if orphans > int(_peak.orphans): _peak.orphans = orphans
	var mem := Performance.get_monitor(Performance.MEMORY_STATIC)
	if mem > float(_peak.mem): _peak.mem = mem
	var canvas_items := int(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME))
	if canvas_items > int(_peak.render_objects): _peak.render_objects = canvas_items
	var row := {"wall_s":_combat_seconds[-1],"tick":(_ticks[-1] if not _ticks.is_empty() else Engine.get_physics_frames()),"round":_rounds,"action_totals":_retired_actions.duplicate(),"ordinary":0,"elite":0,"boss":0,"giant":0,"tier1":0,"tier2":0,"visible":0,"visible_tier1":0,"visible_tier2":0,"sources":0,"continuous_emitted":0,"continuous_deferred":0,"shots_live":preload("res://game/monster/EnemyShot.gd").live_count,"shots_group":get_tree().get_nodes_in_group("enemy_projectiles").size(),"shots_visible":0,"shots_near":0,"shots_screen":0,"damage_events":Combat.damage_events,"kills":Combat.kill_events,"gold":PlayerData.gold,"status_walks":B11Probe.status_walks,"status_empty":B11Probe.status_walks_empty,"flame_draw_usec":0,"flame_draw_passes":0,"fire_released":Demo.fire_released,"weapon":Utils.player.gun.weapon_id if Utils.player.gun else -1,"continuous_planned":0,"continuous_cancelled":0}
	var view_rect := get_viewport().get_visible_rect()
	row.enemies_alive = 0
	row.enemies_drawing_enabled = 0
	row.enemies_on_screen = 0
	for actor in get_tree().get_nodes_in_group("monsters"):
		if actor.get("actions") != null:
			for key in actor.actions: row.action_totals[key] = int(row.action_totals.get(key,0))+int(actor.actions[key])
		if actor.is_die: continue
		row.enemies_alive += 1
		if actor.is_visible_in_tree(): row.enemies_drawing_enabled += 1
		row["boss" if actor.is_boss else ("elite" if actor.is_elite else "ordinary")] += 1
		if actor.get_meta("giant",false): row.giant += 1
		var tier := int(actor.get_meta("enchantment",0))
		if tier > 0: row["tier"+str(tier)] += 1
		if actor.is_visible_in_tree() and view_rect.has_point(actor.get_global_transform_with_canvas().origin):
			row.visible += 1
			row.enemies_on_screen += 1
			if tier > 0: row["visible_tier"+str(tier)] += 1
		var stream = actor.get_node_or_null("ContinuousBarrage")
		if is_instance_valid(stream):
			row.sources += 1
			row.continuous_planned += int(actor.actions.get("continuous_barrage_planned",0))
			row.continuous_cancelled += int(actor.actions.get("continuous_barrage_cancelled",0))
			row.continuous_emitted += int(actor.actions.get("continuous_barrage_emitted",0))
			row.continuous_deferred += int(actor.actions.get("continuous_barrage_deferred",0))
	for shot in get_tree().get_nodes_in_group("enemy_projectiles"):
		if shot.is_visible_in_tree(): row.shots_visible += 1
		if shot.global_position.distance_squared_to(Utils.player.global_position) < 14400: row.shots_near += 1
		if shot.is_visible_in_tree() and view_rect.has_point(shot.get_global_transform_with_canvas().origin): row.shots_screen += 1
	row.projectiles_alive = row.shots_live
	row.projectiles_drawing_enabled = row.shots_visible
	row.projectiles_on_screen = row.shots_screen
	row.simultaneous_180_alive = row.enemies_alive >= 180 and row.projectiles_alive >= 180
	row.simultaneous_180_drawing = row.enemies_drawing_enabled >= 180 and row.projectiles_drawing_enabled >= 180
	row.simultaneous_180_on_screen = row.enemies_on_screen >= 180 and row.projectiles_on_screen >= 180
	if scenario == "P":
		var pressure_floor := int(ceil(float(preload("res://game/monster/EnemyShot.gd").capacity_limit)*0.9))
		_pressure_samples += 1
		if int(row.shots_live) >= pressure_floor: _pressure_live_ge_90 += 1
		if int(row.shots_visible) >= pressure_floor: _pressure_visible_ge_90 += 1
		_pressure_live_min = int(row.shots_live) if _pressure_samples == 1 else mini(_pressure_live_min,int(row.shots_live))
		_pressure_live_max = maxi(_pressure_live_max,int(row.shots_live))
	var layer = LevelServer.town.monster_root.get_node_or_null("B19EnchantmentLayer")
	if is_instance_valid(layer):
		row.flame_draw_usec = layer.draw_usec
		row.flame_draw_passes = layer.draw_passes
	var variants = load("res://game/config/B18Variants.gd")
	row.births = {"ordinary_arrivals":variants.arrivals,"enchanted":variants.enchanted_arrivals,"tier2":variants.tier_two_arrivals}
	row.actual_bounces = _retired_bounces
	for shot in get_tree().get_nodes_in_group("enemy_projectiles"): row.actual_bounces += shot.bounces_done
	row.shots_admitted_total = _shots_admitted
	row.capacity_fixture_emitted = _capacity_emitted
	row.capacity_fixture_planned_attempts = _capacity_planned
	row.capacity_fixture_wall_rejected = _capacity_blocked
	row.physics_pairs = Performance.get_monitor(Performance.PHYSICS_2D_COLLISION_PAIRS)
	row.physics_active = Performance.get_monitor(Performance.PHYSICS_2D_ACTIVE_OBJECTS)
	_load_samples.append(row)
	if B11Probe.iso_particles: _silence_particles()

## B11.2 visual isolation for particles. There are real GPUParticles2D emitters on the rig and on
## several weapons, and `emitting` is the switch that removes them without touching anything that
## hurts. Re-applied on the gauge cadence because weapon switches create new emitters.
func _silence_particles() -> void:
	for node in get_tree().get_nodes_in_group("iso_particle_targets"):
		if node is GPUParticles2D: node.emitting = false
		elif node is CPUParticles2D: node.emitting = false

func _collect_particles() -> void:
	var root := get_tree().current_scene
	if root == null: return
	var stack: Array = [root]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if node is GPUParticles2D or node is CPUParticles2D:
			node.add_to_group("iso_particle_targets")
		for child in node.get_children(): stack.append(child)

## One line per second. It exists so a run can be read as a TIMELINE - which second the hitch was
## in - instead of as one number for the whole round.
func _report_second(round_index: int) -> void:
	if label.begins_with("b19-"):
		print("[stress] input tick=",Engine.get_physics_frames()-_sample_tick_start," released=",Demo.fire_released," shoot=",Input.is_action_pressed("shoot")," mouse=",Utils.is_gameplay_mouse_mode()," damage=",Combat.damage_events," kills=",Combat.kill_events," paused=",get_tree().paused)
	var from := _last_report_index
	var count := _ms.size()-from
	if count <= 0: return
	var stats: Dictionary = _stats(_ms.slice(from,_ms.size()))
	var worst := B11Probe.take_worst()
	var now: Dictionary = B11Probe.snapshot()
	var rates := {}
	for key in now:
		if not (now[key] is int or now[key] is float): continue
		rates[key] = int(now[key])-int(_prev.get(key,now[key]))
	_prev = now
	_peak_same_frame = maxi(_peak_same_frame,B11Probe.hits_in_frame_peak)
	print("[spike] r=%d t=%.1f n=%d avg=%.2f p95=%.2f p99=%.2f max=%.2f fps=%d over25=%d over33=%d over50=%d slow_run_ms=%.0f engine_window_physics_max_ms=%.2f engine_window_process_max_ms=%.2f draws=%d beams=%d zone_hits=%d hits=%d same_frame=%d rays=%d rays_sk=%d cl=%d labels=%d vfx=%d fog=%d reward_scans=%d rbuilt=%d rreuse=%d rnodes=%d rooted_frames=%d zone_usec=%d zone_worst_us=%d clear_usec=%d onhit_usec=%d onhit_worst_us=%d draw_usec=%d objects=%d orphans=%d mem_mb=%.2f pq=%d foglines=%d fogscans=%d shots=%d shotexc=%d td_draws=%d td_usec=%d hz_draws=%d hz_usec=%d swalk=%d swalk_empty=%d" % [
		round_index,_combat_seconds[_ms.size()-1],count,stats.avg,stats.p95,stats.p99,stats.max,
		Engine.get_frames_per_second(),stats.over25,stats.over33,stats.over50,stats.slow_run,
		Array(_phys.slice(from)).max(),Array(_proc.slice(from)).max(),_draws[_draws.size()-1],
		B11Probe.beams_active,int(rates.get("zone_hits",0)),int(rates.get("hits",0)),
		B11Probe.hits_in_frame_peak,int(rates.get("raycasts",0)),int(rates.get("raycasts_skipped",0)),
		int(rates.get("clear_line",0)),int(rates.get("labels",0)),int(rates.get("vfx",0)),
		int(rates.get("fog_pushes",0)),int(rates.get("reward_scans",0)),
		int(rates.get("reward_built",0)),int(rates.get("reward_reused",0)),B11Probe.reward_nodes_peak,
		_rooted_frames_in(from),
		int(rates.get("zone_step_usec",0)),int(worst[0]),int(rates.get("clear_line_usec",0)),
		int(rates.get("onhit_usec",0)),int(worst[1]),int(rates.get("zone_draw_usec",0)),
		int(Performance.get_monitor(Performance.OBJECT_COUNT)),
		int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)),
		Performance.get_monitor(Performance.MEMORY_STATIC)/1048576.0,
		_path_queries()-_prev_pq,
		int(rates.get("fog_push_lines",0)),int(rates.get("fog_ensure_scans",0)),
		int(rates.get("shot_created",0)),int(rates.get("shot_exceptions",0)),
		int(rates.get("telegraph_draws",0)),int(rates.get("telegraph_draw_usec",0)),
		int(rates.get("hazard_draws",0)),int(rates.get("hazard_draw_usec",0)),
		int(rates.get("status_walks",0)),int(rates.get("status_walks_empty",0))])
	_prev_pq = _path_queries()
	B11Probe.hits_in_frame_peak = 0
	B11Probe.beams_active_peak = B11Probe.beams_active
	_last_report_index = _ms.size()

## The arena owns the A* counter (`CombatArena.path_queries`), so it is read rather than duplicated.
## `_pq_total` remembers the high-water mark because the arena is freed with the round, and the
## final `[stress-load]` line is printed after the last round has already ended.
func _path_queries() -> int:
	_remember_spawn_stats()
	var town = LevelServer.town
	if is_instance_valid(town) and is_instance_valid(town.arena):
		var live := int(town.arena.path_queries)
		if live > _pq_total: _pq_total = live
	return _pq_total

func _remember_spawn_stats() -> void:
	var town = LevelServer.town
	if not is_instance_valid(town) or not is_instance_valid(town.arena): return
	var arena = town.arena
	var current := {
		"requests":int(arena.spawn_requests),
		"geometry_rejected":int(arena.spawn_geometry_rejected),
		"clearance_queries":int(arena.spawn_clearance_queries),
		"clearance_rejected":int(arena.spawn_clearance_rejected),
		"path_checks":int(arena.spawn_path_checks),
		"path_queries":int(arena.spawn_path_queries),
		"path_cache_hits":int(arena.spawn_path_cache_hits),
		"path_reachable":int(arena.spawn_path_reachable),
		"path_rejected":int(arena.spawn_path_rejected)}
	for key in current:
		_spawn_peak[key] = maxi(int(_spawn_peak.get(key,0)),int(current[key]))

func _rooted_frames_in(from: int) -> int:
	var count := 0
	for i in range(from,_ms.size()):
		if _flags[i] & F_ROOTED: count += 1
	return count

## Frame-time statistics for one slice. `slow_run` is the longest unbroken stretch of frames over
## 33 ms, in milliseconds: a hitch the player feels as "a freeze" is a RUN, not a single frame.
func _stats(values) -> Dictionary:
	var n: int = values.size()
	if n == 0:
		return {"n":0,"avg":0.0,"p50":0.0,"p95":0.0,"p99":0.0,"max":0.0,
			"over25":0,"over33":0,"over50":0,"slow_run":0.0}
	var sorted: Array = []
	for v in values: sorted.append(float(v))
	sorted.sort()
	var total := 0.0
	var over25 := 0
	var over33 := 0
	var over50 := 0
	for v in values:
		total += float(v)
		if v > 25.0: over25 += 1
		if v > 33.0: over33 += 1
		if v > 50.0: over50 += 1
	var run := 0.0
	var best := 0.0
	for v in values:
		if v > 33.0: run += float(v)
		else:
			if run > best: best = run
			run = 0.0
	if run > best: best = run
	return {"n":n,"avg":total/n,"p50":float(sorted[int(n*0.50)]),
		"p95":float(sorted[mini(n-1,int(n*0.95))]),"p99":float(sorted[mini(n-1,int(n*0.99))]),
		"max":float(sorted[n-1]),"over25":over25,"over33":over33,"over50":over50,"slow_run":best}

## The whole point of the run: the same frame pool split by WHAT WAS HAPPENING on each frame. If
## the stutter is a burst, the conditioned rows separate from the unconditioned ones here; if it is
## not, they do not - and that is the answer either way.
func _dump() -> void:
	_remember_spawn_stats()
	if not presentation_boss_log.is_empty(): print("[stress-boss] ",JSON.stringify(presentation_boss_log))
	# Optional post-run evidence only: no allocation/serialization in measured frames.
	# Retain the existing B11 summaries; consumers can derive an exact warm window.
	print("[stress-frames] ",JSON.stringify({"surface":_surface,"retired_actions":_retired_actions,"observation_frames":_observation_frames,"measured_wall_s":_measured_wall_s,"measurement":measurement,"mode":run_mode,"requested_seconds":seconds,"events":_events,"entry_samples":_entry_samples,"orbit_decisions":_orbit_log,"controlled_boss":controlled_boss,"boss_complete":boss_complete,"paused_ms":_pause_usec/1000.0,"shots_admitted_total":_shots_admitted,"retired_bounces":_retired_bounces,"capacity_fixture_emitted":_capacity_emitted,"capacity_fixture_planned_attempts":_capacity_planned,"capacity_fixture_wall_rejected":_capacity_blocked,"pressure_samples":_pressure_samples,"pressure_live_ge_90":_pressure_live_ge_90,"pressure_visible_ge_90":_pressure_visible_ge_90,"pressure_live_ratio":(float(_pressure_live_ge_90)/_pressure_samples if _pressure_samples else 0.0),"pressure_visible_ratio":(float(_pressure_visible_ge_90)/_pressure_samples if _pressure_samples else 0.0),"pressure_live_min":_pressure_live_min,"pressure_live_max":_pressure_live_max,"effective_sim_seconds":float(_effective_tick)/Engine.physics_ticks_per_second,"source_variant":source_variant,"workload_scenario":scenario,"measurement_timeout":measurement_timeout,"ms":Array(_ms),"engine_delta_ms":Array(_engine_ms),"physics_ticks":Array(_ticks),"process_frames":Array(_process_frames),"absolute_physics_ticks":Array(_absolute_ticks),"epochs":Array(_epochs),"round_contexts":_round_contexts,"long_frames":_long_frames,"physics_hz":Engine.physics_ticks_per_second,"engine_window_peak_monitor":{"physics_ms":Array(_phys),"process_ms":Array(_proc),"kind":"ENGINE_WINDOW_PEAK_MONITOR"},"draws":Array(_draws),"round":Array(_round_of),"combat_wall_seconds":Array(_combat_seconds),"load_samples":_load_samples,"memory_static_available":OS.is_debug_build(),"scoped_usec":B11Probe.scoped_usec,"scoped_calls":B11Probe.scoped_calls,"timing":"monotonic process-frame interval; NOT GPU present time; engine-window monitors are not per-frame CPU durations"}))
	var all: Dictionary = _stats(_ms)
	var total_s := _total_combat_s
	print("[stress-summary] scenario=%s stage=%d label=%s rounds=%d frames=%d combat_s=%.1f avg=%.2f p50=%.2f p95=%.2f p99=%.2f max=%.2f over25=%d over33=%d over50=%d slow_run_ms=%.0f root_windows=%d driver_roots=%d/%d amplified=%d" % [
		scenario,stage,label,_rounds,_ms.size(),total_s,all.avg,all.p50,all.p95,all.p99,all.max,
		all.over25,all.over33,all.over50,all.slow_run,_root_windows,_driver_roots,
		_driver_root_attempts,_amplified])
	print("[stress-cpu] kind=ENGINE_WINDOW_PEAK_MONITOR physics_max_ms=%.3f process_max_ms=%.3f draws_peak=%d" % [
		Array(_phys).max() if not _phys.is_empty() else 0.0,Array(_proc).max() if not _proc.is_empty() else 0.0,_draws_peak()])
	print("[stress-peak] enemies=%d zones=%d beams=%d hazards=%d vfx=%d transients=%d labels=%d projectiles=%d rewards=%d nodes=%d created=%d removed=%d raycasts=%d raycasts_skipped=%d clear_line=%d hits=%d zone_hits=%d same_frame=%d labels_created=%d vfx_created=%d fog_pushes=%d reward_scans=%d reward_built=%d reward_reused=%d reward_nodes=%d frames=%d" % [
		_peak.enemies,_peak.zones,_peak.beams,_peak.hazards,_peak.vfx,_peak.transients,_peak.labels,
		_peak.projectiles,_peak.rewards,_peak.nodes,_created,_removed,
		B11Probe.raycasts,B11Probe.raycasts_skipped,B11Probe.clear_line_calls,B11Probe.player_hits,
		B11Probe.zone_hits,_peak_same_frame,B11Probe.labels_created,B11Probe.vfx_created,
		B11Probe.fog_pushes,B11Probe.reward_scans,B11Probe.reward_fanouts_built,
		B11Probe.reward_fanouts_reused,B11Probe.reward_nodes_peak,_ms.size()])
	# Two bucket families over the SAME frames: one on the user-visible frame time, one on the
	# engine's own CPU cost for the frame. On a vsync-locked browser the first is coarse and the
	# second is the one that attributes. Both are reported, because a build that improves only one
	# of them has not answered the report.
	# B11.2: engine-level load, node churn and the redundancy counters, on their own lines so the
	# B11.1 report fields above keep working unchanged.
	var draws_avg := 0.0
	if _draws.size() > 0:
		var draw_acc := 0
		for v in _draws: draw_acc += v
		draws_avg = float(draw_acc)/float(_draws.size())
	var pq := _path_queries()
	var per_s := maxf(total_s,0.001)
	print("[stress-load] frames=%d combat_s=%.1f objects_peak=%d orphans_peak=%d canvas_items_peak=%d mem_static_peak_mb=%.1f draws_avg=%.1f draws_peak=%d path_queries=%d path_per_s=%.1f created=%d removed=%d created_per_s=%.1f removed_per_s=%.1f enemies_peak=%d projectiles_peak=%d hazards_peak=%d zones_peak=%d beams_peak=%d vfx_peak=%d labels_peak=%d transients_peak=%d rewards_peak=%d nodes_peak=%d topped_up=%d" % [
		_ms.size(),total_s,_peak.objects,_peak.orphans,_peak.render_objects,float(_peak.mem)/1048576.0,
		draws_avg,_draws_peak(),pq,float(pq)/per_s,_created,_removed,
		float(_created)/per_s,float(_removed)/per_s,
		_peak.enemies,_peak.projectiles,_peak.hazards,_peak.zones,_peak.beams,_peak.vfx,
		_peak.labels,_peak.transients,_peak.rewards,_peak.nodes,_topped_up])
	print("[stress-ink] fog_push_lines=%d fog_ensure_scans=%d fog_canvas_hits=%d fog_scans=%d fog_appended=%d fog_dropped=%d fog_draws=%d fog_entries_drawn=%d fog_draw_usec=%d fog_pushes=%d shoots=%d shot_exceptions=%d shot_fog_mirrors=%d vfx_created=%d vfx_draws=%d hazard_draws=%d hazard_draw_usec=%d telegraph_draws=%d telegraph_draw_usec=%d telegraph_cache_hits=%d telegraph_cache_rebuilds=%d status_walks=%d status_walks_empty=%d labels_created=%d label_tweens=%d clear_line=%d raycasts=%d raycasts_skipped=%d onhit_usec=%d zone_step_usec=%d zone_draw_usec=%d path_usec=%d" % [
		B11Probe.fog_push_lines,B11Probe.fog_ensure_scans,B11Probe.fog_canvas_hits,
		B11Probe.fog_scans,B11Probe.fog_entries_appended,B11Probe.fog_entries_dropped,
		B11Probe.fog_draws,B11Probe.fog_entries_drawn,B11Probe.fog_draw_usec,
		B11Probe.fog_pushes,
		B11Probe.shot_created,B11Probe.shot_exceptions,B11Probe.shot_fog_mirrors,
		B11Probe.vfx_created,B11Probe.vfx_draws,B11Probe.hazard_draws,B11Probe.hazard_draw_usec,
		B11Probe.telegraph_draws,B11Probe.telegraph_draw_usec,B11Probe.telegraph_cache_hits,
		B11Probe.telegraph_cache_rebuilds,B11Probe.status_walks,B11Probe.status_walks_empty,
		B11Probe.labels_created,B11Probe.label_tweens,B11Probe.clear_line_calls,B11Probe.raycasts,
		B11Probe.raycasts_skipped,B11Probe.onhit_usec,B11Probe.zone_step_usec,B11Probe.zone_draw_usec,
		B11Probe.path_usec])
	print("[stress-spawn] requests=%d ordinary_requests=%d ordinary_added=%d elite_requests=%d elite_promotions=%d geometry_rejected=%d clearance_queries=%d clearance_rejected=%d path_checks=%d path_queries=%d path_cache_hits=%d path_reachable=%d path_rejected=%d candidates=%d audit_rejected=%d arena_failed=%d spawn_prepare_usec=%d spawn_instantiate_usec=%d spawn_ready_usec=%d spawn_finalize_usec=%d spawn_prepare_calls=%d spawn_instantiate_calls=%d spawn_ready_calls=%d spawn_finalize_calls=%d enemies_peak=%d projectiles_peak=%d hazards_peak=%d zones_peak=%d nodes_peak=%d" % [
		int(_spawn_peak.requests),_ordinary_requests,_topped_up,_elite_requests,_elite_promotions,
		int(_spawn_peak.geometry_rejected),int(_spawn_peak.clearance_queries),int(_spawn_peak.clearance_rejected),
		int(_spawn_peak.path_checks),int(_spawn_peak.path_queries),int(_spawn_peak.path_cache_hits),
		int(_spawn_peak.path_reachable),int(_spawn_peak.path_rejected),M5Content.audit_candidates,
		M5Content.audit_rejected,M5Content.audit_arena_failed,
		int(B11Probe.scoped_usec.get("spawn_prepare",0)),int(B11Probe.scoped_usec.get("spawn_instantiate",0)),
		int(B11Probe.scoped_usec.get("spawn_ready",0)),int(B11Probe.scoped_usec.get("spawn_finalize",0)),
		int(B11Probe.scoped_calls.get("spawn_prepare",0)),int(B11Probe.scoped_calls.get("spawn_instantiate",0)),
		int(B11Probe.scoped_calls.get("spawn_ready",0)),int(B11Probe.scoped_calls.get("spawn_finalize",0)),
		_peak.enemies,_peak.projectiles,_peak.hazards,_peak.zones,_peak.nodes])
	_buckets("ms",_ms)

func _buckets(family: String, values) -> void:
	_bucket(family,"all",func(_f: int,_b: int) -> bool: return true,values)
	_bucket(family,"rooted",func(f: int,_b: int) -> bool: return (f & F_ROOTED) != 0,values)
	_bucket(family,"not_rooted",func(f: int,_b: int) -> bool: return (f & F_ROOTED) == 0,values)
	_bucket(family,"lane1",func(f: int,_b: int) -> bool: return (f & F_LANE) != 0,values)
	_bucket(family,"lane3plus",func(_f: int,b: int) -> bool: return b >= 3,values)
	_bucket(family,"lane6plus",func(_f: int,b: int) -> bool: return b >= 6,values)
	_bucket(family,"rooted_lane1",func(f: int,_b: int) -> bool: return (f & F_ROOTED) != 0 and (f & F_LANE) != 0,values)
	_bucket(family,"rooted_lane3plus",func(f: int,b: int) -> bool: return (f & F_ROOTED) != 0 and b >= 3,values)
	_bucket(family,"not_rooted_lane3plus",func(f: int,b: int) -> bool: return (f & F_ROOTED) == 0 and b >= 3,values)
	_bucket(family,"hit_frame",func(f: int,_b: int) -> bool: return (f & F_HIT) != 0,values)
	_bucket(family,"hit_frame_rooted",func(f: int,_b: int) -> bool: return (f & (F_HIT|F_ROOTED)) == (F_HIT|F_ROOTED),values)
	_bucket(family,"raycast_frame",func(f: int,_b: int) -> bool: return (f & F_RAY) != 0,values)
	_bucket(family,"no_raycast_frame",func(f: int,_b: int) -> bool: return (f & F_RAY) == 0,values)
	_bucket(family,"clear_line_frame",func(f: int,_b: int) -> bool: return (f & F_CLEAR) != 0,values)
	_bucket(family,"quiet_frame",func(f: int,_b: int) -> bool: return (f & (F_HIT|F_RAY|F_CLEAR)) == 0,values)

func _count_over(values, threshold: float) -> int:
	var count := 0
	for v in values:
		if float(v) > threshold: count += 1
	return count

func _draws_peak() -> int:
	var peak := 0
	for v in _draws:
		if v > peak: peak = v
	return peak

func _bucket(family: String, name: String, predicate: Callable, values) -> void:
	var picked := PackedFloat32Array()
	for i in _ms.size():
		if predicate.call(_flags[i],_beams[i]): picked.append(values[i])
	if picked.is_empty(): return
	var s: Dictionary = _stats(picked)
	print("[stress-bucket] family=%s name=%s n=%d share=%.3f avg=%.3f p50=%.3f p95=%.3f p99=%.3f max=%.3f over33=%d over50=%d slow_run_ms=%.0f" % [
		family,name,s.n,float(s.n)/float(_ms.size()),s.avg,s.p50,s.p95,s.p99,s.max,s.over33,
		s.over50,s.slow_run])
## Give the rig the profile a player who reached Hell would own. Touches no save file
## (`Demo.test_mode` is set by this driver).
func _grant_everything() -> void:
	if LevelServer.state != "CAMP":
		LevelServer.state = "CAMP"
	PlayerData.gold = 999999
	PlayerData.reward_point = 9999
	for id in Utils.am_dict:
		Demo.try_purchase("attachment", id)
	for id in Utils.weapon_list:
		Demo.try_purchase("weapon", id)
	for id in DemoConfig.TALENTS:
		var guard := 0
		while Demo.rank(id) < DemoConfig.TALENTS[id].max and guard < 12:
			Demo.try_purchase("talent", id, "points")
			guard += 1
	# The LEGACY set is the one that populates the `reward` group, and it is the reason this method
	# exists: `Hero.onHit` fans out to `get_nodes_in_group("reward")` four times per landed hit, so
	# a harness that only granted attachments and talents would measure that path at ZERO width and
	# report the exact cost the human report is about as free. `legacy` is the same purchase path
	# the camp shop uses, so the tree is assembled the way a real player's is. One copy of each
	# distinct reward is also the WIDEST the group can get: stacking a reward raises that node's
	# `count`, it does not add a node, so 23 is the real fan-out width and not an inflated one.
	for id in RewardServer.reward_list:
		var probe = RewardServer.reward_list[id].instantiate()
		var room := RewardServer.can_add(probe)
		probe.free()
		if room: Demo.try_purchase("legacy", id, "points")
	print("[stress] rewards_owned=%d talents=%d reward_group=%d" % [
		Utils.player.reward_root.get_child_count(),Demo.talents.size(),
		get_tree().get_nodes_in_group("reward").size()])
