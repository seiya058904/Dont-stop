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

# ---- per-frame samples (parallel packed arrays: no per-frame allocation) ---------------------
var _ms := PackedFloat32Array()
## The engine's own CPU cost for this frame's physics step and idle step, in milliseconds. These
## are the readings that survive a vsync lock: the browser build is capped at 60 Hz here, so a frame
## that costs 8 ms and one that costs 16.6 ms are both reported as 16.67 ms. `_phys` and `_proc`
## show the cost itself, which is what a slower player machine actually feels.
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
	"projectiles":0,"nodes":0,"rewards":0}
var _created := 0
var _removed := 0
var _prev := {}
var _last_report_index := 0
var _peak_same_frame := 0

# ---- round bookkeeping -----------------------------------------------------------------------
var _rounds := 0
var _total_combat_s := 0.0
var _root_windows := 0
var _driver_roots := 0
var _driver_root_attempts := 0
var _amplified := 0

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
		elif arg.begins_with("--stress-label="): label = arg.substr(15)
	B11Probe.enabled = true
	get_tree().node_added.connect(_count_added)
	get_tree().node_removed.connect(_count_removed)
	print("[stress] mode=on scenario=%s stage=%d seconds=%d seed=%d lasers=%d root=%.2f park=%s label=%s" % [
		scenario,stage,seconds,run_seed,lasers,root_period,str(park),label])
	run.call_deferred()

func _count_added(_node: Node) -> void: _created += 1
func _count_removed(_node: Node) -> void: _removed += 1

## The stress scenario is the whole point of the round, so it is stated once and named.
##   A  the real Stage 39 exactly as shipped
##   B  A + real Elite laser sentinels, so several lanes are genuinely live at once
##   C  B + the real root applied on a fixed cadence, so the player is pinned inside them
##   D  C, with the player holding position: the "rooted while covered" frame
func _apply_scenario() -> void:
	match scenario:
		"A": pass
		"B": lasers = maxi(lasers,4)
		"C": lasers = maxi(lasers,4); root_period = maxf(root_period,2.0)
		"D": lasers = maxi(lasers,4); root_period = maxf(root_period,2.0); park = true
	print("[stress] effective scenario=%s lasers=%d root_period=%.2f park=%s" % [
		scenario,lasers,root_period,str(park)])

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
	# The reward tree a Hell player owns. Without this the incoming-damage path scans an EMPTY
	# reward group and the harness would report that path as free.
	_grant_everything()
	PlayerData.player_hp_max = 1000000.0
	PlayerData.player_hp = 1000000.0
	Utils.set_gameplay_mouse_mode()
	await get_tree().create_timer(0.6).timeout
	# Stage 39 is a 45 s survival round, so the requested window is accumulated over consecutive
	# rounds. The protocol is identical in the BEFORE and the AFTER build.
	while _total_combat_s < float(seconds) and _rounds < 8:
		await _one_round()
	Input.action_release("shoot")
	print("[stress] done scenario=%s rounds=%d frames=%d combat_s=%.1f" % [
		scenario,_rounds,_ms.size(),_total_combat_s])
	_dump()
	get_tree().quit(0)

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
	seed(run_seed)
	_rounds += 1
	var departed: bool = LevelServer.town.depart(stage,true)
	print("[stress] round=%d depart=%s state=%s" % [_rounds,str(departed),LevelServer.state])
	deadline = Time.get_ticks_msec() + 120000
	while Time.get_ticks_msec() < deadline and LevelServer.state != "COMBAT":
		await get_tree().create_timer(0.25).timeout
	if LevelServer.state != "COMBAT": return
	await _sample_round()

## The sampling loop. One pass per rendered frame; the cost of the observation itself is bounded
## to a handful of integer reads plus a few packed-array appends, because a harness that allocates
## per frame would end up measuring itself.
func _sample_round() -> void:
	var round_index := _rounds
	var started := Time.get_ticks_msec()
	var next_report := started + 1000
	var next_gauge := 0
	var next_root := 0.0
	var prev_rooted := false
	var ray_prev: int = B11Probe.raycasts
	var clear_prev: int = B11Probe.clear_line_calls
	var hit_prev: int = B11Probe.player_hits
	if lasers > 0: _amplify_lasers()
	Input.action_press("shoot")
	var next_amp := 4.0
	while LevelServer.state == "COMBAT" and is_instance_valid(Utils.player) and not Utils.player.is_dead:
		# The rig cannot die: a level-1 health bar would end the round before the peak.
		PlayerData.player_hp = PlayerData.player_hp_max
		var now := Time.get_ticks_msec()
		var elapsed := float(now-started)/1000.0
		if lasers > 0 and elapsed >= next_amp:
			next_amp += 4.0
			if _amplified_alive() < lasers: _amplify_lasers()
		if root_period > 0.0 and elapsed >= next_root:
			next_root += root_period
			_driver_root_attempts += 1
			if Utils.player.apply_root(0.45): _driver_roots += 1
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
		_ms.append(get_process_delta_time()*1000.0)
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
		if now >= next_report:
			next_report = now + 1000
			_report_second(round_index)
		if not park: _drive_movement(now)
		await get_tree().process_frame
	Input.action_release("shoot")
	for action in ["left","right","up","down"]: Input.action_release(action)
	var round_s := 0.0
	if _combat_seconds.size() > 0: round_s = _combat_seconds[_combat_seconds.size()-1]
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
	var town = LevelServer.town
	if not is_instance_valid(town): return
	for i in lasers:
		var role := "E14" if i % 2 == 0 else "E13"
		var point: Vector2 = town.spawn_point(M5Content.radius_for(role))
		if point == Vector2.INF: continue
		var actor: Node = M5Content.spawn(role,town.monster_root,point)
		if actor == null: continue
		actor.set_meta("b11_amplified",true)
		M5Content.promote_elite(actor,M5Content.elite_modifier_for(role))
		_amplified += 1

func _amplified_alive() -> int:
	var count := 0
	for actor in get_tree().get_nodes_in_group("monsters"):
		if actor.is_die: continue
		if actor.get_meta("b11_amplified",false): count += 1
	return count

func _drive_movement(now: int) -> void:
	var step := ((now/700)%4)
	for pair in [["left",0],["right",1],["up",2],["down",3]]:
		if step == int(pair[1]): Input.action_press(pair[0])
		else: Input.action_release(pair[0])

func _sample_gauges() -> void:
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

## One line per second. It exists so a run can be read as a TIMELINE - which second the hitch was
## in - instead of as one number for the whole round.
func _report_second(round_index: int) -> void:
	var from := _last_report_index
	var count := _ms.size()-from
	if count <= 0: return
	var stats: Dictionary = _stats(_ms.slice(from,_ms.size()))
	var cpu := _stats(_phys.slice(from,_phys.size()))
	var worst := B11Probe.take_worst()
	var now: Dictionary = B11Probe.snapshot()
	var rates := {}
	for key in now:
		rates[key] = int(now[key])-int(_prev.get(key,now[key]))
	_prev = now
	_peak_same_frame = maxi(_peak_same_frame,B11Probe.hits_in_frame_peak)
	print("[spike] r=%d t=%.1f n=%d avg=%.2f p95=%.2f p99=%.2f max=%.2f fps=%d over25=%d over33=%d over50=%d slow_run_ms=%.0f phys_avg=%.2f phys_p95=%.2f phys_max=%.2f proc_avg=%.2f draws=%d beams=%d zone_hits=%d hits=%d same_frame=%d rays=%d rays_sk=%d cl=%d labels=%d vfx=%d fog=%d reward_scans=%d rbuilt=%d rreuse=%d rnodes=%d rooted_frames=%d zone_usec=%d zone_worst_us=%d clear_usec=%d onhit_usec=%d onhit_worst_us=%d draw_usec=%d" % [
		round_index,_combat_seconds[_ms.size()-1],count,stats.avg,stats.p95,stats.p99,stats.max,
		Engine.get_frames_per_second(),stats.over25,stats.over33,stats.over50,stats.slow_run,
		cpu.avg,cpu.p95,cpu.max,_stats(_proc.slice(from,_proc.size())).avg,_draws[_draws.size()-1],
		B11Probe.beams_active,int(rates.get("zone_hits",0)),int(rates.get("hits",0)),
		B11Probe.hits_in_frame_peak,int(rates.get("raycasts",0)),int(rates.get("raycasts_skipped",0)),
		int(rates.get("clear_line",0)),int(rates.get("labels",0)),int(rates.get("vfx",0)),
		int(rates.get("fog_pushes",0)),int(rates.get("reward_scans",0)),
		int(rates.get("reward_built",0)),int(rates.get("reward_reused",0)),B11Probe.reward_nodes_peak,
		_rooted_frames_in(from),
		int(rates.get("zone_step_usec",0)),int(worst[0]),int(rates.get("clear_line_usec",0)),
		int(rates.get("onhit_usec",0)),int(worst[1]),int(rates.get("zone_draw_usec",0))])
	B11Probe.hits_in_frame_peak = 0
	B11Probe.beams_active_peak = B11Probe.beams_active
	_last_report_index = _ms.size()

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
	var all: Dictionary = _stats(_ms)
	var phys: Dictionary = _stats(_phys)
	var proc: Dictionary = _stats(_proc)
	var total_s := _total_combat_s
	print("[stress-summary] scenario=%s stage=%d label=%s rounds=%d frames=%d combat_s=%.1f avg=%.2f p50=%.2f p95=%.2f p99=%.2f max=%.2f over25=%d over33=%d over50=%d slow_run_ms=%.0f root_windows=%d driver_roots=%d/%d amplified=%d" % [
		scenario,stage,label,_rounds,_ms.size(),total_s,all.avg,all.p50,all.p95,all.p99,all.max,
		all.over25,all.over33,all.over50,all.slow_run,_root_windows,_driver_roots,
		_driver_root_attempts,_amplified])
	print("[stress-cpu] frames=%d combat_s=%.1f phys_avg=%.3f phys_p50=%.3f phys_p95=%.3f phys_p99=%.3f phys_max=%.3f proc_avg=%.3f proc_max=%.3f phys_over8=%d phys_over12=%d draws_peak=%d zone_step_usec=%d zone_draw_usec=%d clear_line_usec=%d onhit_usec=%d" % [
		_ms.size(),total_s,phys.avg,phys.p50,phys.p95,phys.p99,phys.max,proc.avg,proc.max,
		_count_over(_phys,8.0),_count_over(_phys,12.0),_draws_peak(),
		B11Probe.zone_step_usec,B11Probe.zone_draw_usec,B11Probe.clear_line_usec,B11Probe.onhit_usec])
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
	_buckets("ms",_ms)
	_buckets("phys",_phys)

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
