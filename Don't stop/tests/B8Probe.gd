extends "res://tests/M8Runtime.gd"

## B8 measurement base: death-source telemetry and an escape-availability probe.
##
## Observation only. The driver (M8Runtime._process) is inherited UNCHANGED and is still the
## thing that plays the game: nothing here writes to the damage pipeline, moves an actor's HP,
## forces an attack, teleports the player or grants invulnerability. Every number below is read
## from state a real round produced, from the real weapon fire the driver issued.
##
## Why this needs a new signal rather than reading Hero.incoming_hit: a HostileZone, a
## StageHazard and an arena poison tick all hand their OWNER in as `attacker`, so the attacker
## alone cannot tell a beam from artillery from a ground hazard - and the whole point of B8 is
## to know WHICH mechanism is killing the player. Hero.damage_taken carries the mechanism tag
## the call site states, and nothing in the damage pipeline reads it back.
##
## Two independent questions are answered, and they must not be confused:
##   Q1 "is the bot bad?"        -> the damage ledger: what actually dealt the damage.
##   Q2 "is the design unfair?"  -> the escape probe: was there ANY reachable point that
##                                  stayed outside every damaging footprint, in time.

## Mechanism tag -> report category. Tags come from the call sites (see the note in Hero.gd).
## Categories are deliberately coarser than tags: the tag table keeps the game's own attack
## kinds, the category rollup answers the brief's "at least classify" list.
const ZONE_KINDS := ["circle","line","charge","cone","beam","artillery","tremor","cross",
	"cross_laser","band","fan_shot"]

## Escape probe sampling. The driver already runs at frame rate; 10 Hz keeps the probe's cost
## independent of the frame rate and matches the density audit's cadence.
const SAMPLE_HZ := 10.0
const PROBE_DIRECTIONS := 16
const PROBE_RADII := [30.0, 64.0, 112.0]
## The player's real movement speed is read from the build at boot; this is the fallback used
## only if it cannot be read. A probe point is only an escape if the player can reach it before
## the footprint that covers it opens.
const DEFAULT_TRAVEL := 100.0
## A single frame inside a fully-denied arena can be a physics artefact (an actor pressed into
## geometry, a zone freed on the same tick). Three consecutive samples - 0.3 s - is the same
## debounce convention tests/M10Density.gd uses for `unreachable_stuck`.
const DENIAL_CONFIRM := 3
## Ring buffer length for "the attack sequence in the last N seconds before a death".
const RING_SECONDS := 3.0
## Mirrors HostileZone.FAIR_VISIBLE / StageHazard.FAIR_VISIBLE. Kept as a copy because
## HostileZone has no class_name (so the constant cannot be reached by name) and reading a
## const off an instance is not something to bet the instrument on. tests/B8Contracts.gd
## asserts the two constants still agree, so the copy cannot silently rot.
const ZONE_FAIR_VISIBLE := 0.5

var travel_speed := DEFAULT_TRAVEL

# ---- damage ledger -------------------------------------------------------------------
var ledger := {}          # tag -> {"hits":int,"applied":float,"raw":float}
var categories := {}      # category -> {"hits":int,"applied":float}
var ring: Array = []      # {"at":float,"tag":String,"applied":float,"hp":float,"attacker":String,"rooted":bool}
var rooted_damage := 0.0
var rooted_hits := 0
var post_root_damage := 0.0   # landed inside the 1.2 s immunity window that follows a root
var post_root_hits := 0
var total_applied := 0.0
var total_hits := 0
var lethal: Dictionary = {}   # the event that took the player below 1 HP

# ---- per-run sampling ----------------------------------------------------------------
var run_start := 0
var sample_clock := 0.0
var samples := 0
var alive_sum := 0
var alive_peak := 0
var near80_peak := 0
var projectile_peak := 0
var zone_peak := 0
var hazard_peak := 0
var horde_overlap_peak := 0
var flank_arrivals := 0
var elite_peak := 0
var illegal_near_spawns := 0
var closest_spawn := 9999.0
var special_spawns := 0
var born := {}
var hp_min := 9999.0
var time_to_first_damage := -1.0
var death_at := -1.0
var death_snapshot: Dictionary = {}
var escape_peak_live := 0

# ---- escape probe -------------------------------------------------------------------
var probe_samples := 0
var denial_samples := 0
var denial_streak := 0
var denial_streak_peak := 0
var denial_events: Array = []
var denial_modes := {}
var geometric_denial_samples := 0
var geometric_streak := 0
var geometric_streak_peak := 0
var geometric_modes := {}
var strict_denial_samples := 0
var last_escape := {}

# ---- run description -----------------------------------------------------------------
var meta: Dictionary = {}


# ======================================================================================
# Attribution
# ======================================================================================

func category_for(tag: String, attacker) -> String:
	var boss: bool = is_instance_valid(attacker) and attacker.get("is_boss") == true
	var elite: bool = is_instance_valid(attacker) and attacker.get("is_elite") == true
	if tag == "boss_percentage": return "boss_percentage"
	if tag.begins_with("hazard_"): return "arena_hazard"
	if tag == "contact":
		if boss: return "boss_contact"
		if elite: return "elite_contact"
		return "normal_contact"
	if tag == "detonate":
		# E06's self-destruct burst: a committed, telegraphed area denial, not body pressure.
		if elite: return "elite_self_destruct"
		return "self_destruct"
	if tag == "shot:projectile" or tag == "projectile": return "enemy_projectile"
	if tag.begins_with("shot:"): return "barrage_" + tag.substr(4)
	if tag in ["artillery","tremor"]: return "artillery"
	if tag in ["toxin","toxic_zone"]: return "poison_field"
	if tag in ZONE_KINDS: return "beam_or_hostile_zone"
	if tag == "" or tag == "percentage": return "other"
	return "other"

func _bucket(table: Dictionary, key: String) -> Dictionary:
	if not table.has(key): table[key] = {"hits":0,"applied":0.0,"raw":0.0}
	return table[key]

func _on_damage(raw: float, applied: float, tag: String, attacker) -> void:
	var now := _now()
	var player = Utils.player
	var rooted := false # Historical report columns; immobilization has been removed.
	var post := false
	var who := ""
	if is_instance_valid(attacker):
		who = str(attacker.get_meta("content_id", attacker.name))
		if attacker.get("is_elite") == true: who += "+elite"
		if attacker.get("is_boss") == true: who += "+boss"
	var entry = _bucket(ledger,tag)
	entry.hits += 1; entry.applied += applied; entry.raw += raw
	var cat = _bucket(categories,category_for(tag,attacker))
	cat.hits += 1; cat.applied += applied
	total_applied += applied; total_hits += 1
	ring.append({"at":now,"tag":tag,"applied":applied,"hp":float(PlayerData.player_hp),
		"attacker":who,"rooted":rooted,"post_root":post})
	if time_to_first_damage < 0.0: time_to_first_damage = now
	if rooted: rooted_hits += 1; rooted_damage += applied
	if post: post_root_hits += 1; post_root_damage += applied
	# The killing blow: the damage that takes the pool to zero or below. PlayerData.player_hp
	# is still pre-hit here because Hero emits before subtracting, which is what lets this be
	# attributed to the exact mechanism instead of guessed from the last sample.
	#
	# The death context is captured HERE rather than by the 10 Hz sampler. The sampler's first
	# look after a death can already be a tick too late - LevelServer._timeout() flips the round
	# to DEAD the moment the player dies, and half a second later return_to_camp() frees every
	# zone, hazard and projectile. At this instant the arena is provably still standing, so the
	# snapshot is the state that actually killed the player instead of whatever survived it. A
	# first B8 run lost every death snapshot to that race.
	if PlayerData.player_hp - applied <= 0.0 and lethal.is_empty():
		lethal = {"at":now,"tag":tag,"applied":applied,"attacker":who,"hp_before":float(PlayerData.player_hp)}
		lethal.category = category_for(tag,attacker)
		death_at = now
		death_snapshot = _snapshot(now)

func attach_telemetry() -> void:
	if not Utils.player.damage_taken.is_connected(_on_damage):
		Utils.player.damage_taken.connect(_on_damage)

func detach_telemetry() -> void:
	if Utils.player.damage_taken.is_connected(_on_damage):
		Utils.player.damage_taken.disconnect(_on_damage)

func reset_telemetry() -> void:
	ledger = {}; categories = {}; ring = []
	rooted_damage = 0.0; rooted_hits = 0; post_root_damage = 0.0; post_root_hits = 0
	total_applied = 0.0; total_hits = 0; lethal = {}
	run_start = Time.get_ticks_msec(); sample_clock = 0.0; samples = 0
	alive_sum = 0; alive_peak = 0; near80_peak = 0; projectile_peak = 0; zone_peak = 0
	hazard_peak = 0; horde_overlap_peak = 0; flank_arrivals = 0; elite_peak = 0
	illegal_near_spawns = 0; closest_spawn = 9999.0; special_spawns = 0; born = {}
	hp_min = 9999.0; time_to_first_damage = -1.0; death_at = -1.0; death_snapshot = {}
	escape_peak_live = 0; probe_samples = 0; denial_samples = 0; denial_streak = 0
	denial_streak_peak = 0; denial_events = []; denial_modes = {}; geometric_denial_samples = 0
	geometric_streak = 0; geometric_streak_peak = 0; geometric_modes = {}; strict_denial_samples = 0
	last_escape = {}
	reset_dodge_telemetry()
	travel_speed = maxf(60.0,float(Utils.player.SPEED)) if is_instance_valid(Utils.player) and Utils.player.SPEED > 0.0 else DEFAULT_TRAVEL

func _now() -> float:
	return (Time.get_ticks_msec()-run_start)/1000.0


# ======================================================================================
# Escape probe
# ======================================================================================

## Every live footprint that can damage the player, in a shape the probe can test.
##
## Poison is deliberately EXCLUDED from the denial set. StageHazard's own contract is that
## poison only ticks while the player stands inside it and stops on the next tick after leaving,
## so a poison field cannot make escape impossible - it prices standing still, it does not deny
## movement. Its damage is still fully attributed by the ledger above.
func _threats() -> Array:
	var out := []
	var fog := ArenaVisibility.fog_active()
	for zone in get_tree().get_nodes_in_group("hostile_zone"):
		if not is_instance_valid(zone): continue
		if float(zone.damage) <= 0.0: continue
		if not zone.friendly_context.is_empty(): continue
		var mode = str(zone.mode)
		var shape := "circle"
		if mode in ["line","charge"]: shape = "segment"
		elif mode == "cone": shape = "cone"
		# HostileZone has no `active` property: it has `activated` (has it opened at all) and
		# the elapsed/warning pair. The damaging phase is elapsed >= warning, which is the same
		# test step() itself uses.
		var is_active: bool = float(zone.elapsed) >= float(zone.warning)
		out.append({
			"mode":mode, "shape":shape, "at":zone.global_position,
			"dir":zone.direction, "len":float(zone.length), "w":float(zone.width),
			"r":float(zone.radius), "angle":float(zone.angle),
			"active":is_active,
			"eta":maxf(0.0,float(zone.warning)-float(zone.elapsed)),
			# A footprint the fog gate would not have let open yet cannot fairly be counted as
			# a denial: HostileZone refuses to activate until its footprint has been readable
			# from inside the player's light for FAIR_VISIBLE seconds. Outside Hell the gate is
			# off, so this is always true there and the two verdicts coincide.
			"fair":(not fog) or (not bool(zone.fair_gate)) or is_active or float(zone.visible_warning) >= ZONE_FAIR_VISIBLE
		})
	for hazard in get_tree().get_nodes_in_group(StageHazard.GROUP):
		if not is_instance_valid(hazard): continue
		if hazard.kind == "poison": continue
		if float(hazard.damage) <= 0.0: continue
		var seg = hazard.kind in ["laser","shock"]
		out.append({
			"mode":"hazard_"+str(hazard.kind), "shape":("segment" if seg else "circle"),
			"at":hazard.origin(), "dir":hazard.direction,
			"len":float(hazard.clipped), "w":float(hazard.width), "r":float(hazard.radius),
			"angle":0.0, "active":hazard.phase == "active",
			"eta":maxf(0.0,float(hazard.phase_time)) if hazard.phase != "active" else 0.0,
			"fair":(not fog) or hazard.phase == "active" or float(hazard.visible_warning) >= StageHazard.FAIR_VISIBLE
		})
	return out

## Geometry AND line of sight. A footprint only damages what it can actually reach - both
## HostileZone and StageHazard require Combat.clear_line() from the footprint's own origin - so
## a zone on the far side of an arena pillar denies nothing and must not be counted as a denial.
## Being generous here would manufacture balance defects out of walls.
func _covers(threat: Dictionary, point: Vector2) -> bool:
	var at: Vector2 = threat.at
	var offset := point-at
	var geometric := false
	match str(threat.shape):
		"segment":
			var tip := at+(threat.dir as Vector2)*float(threat.len)
			geometric = Geometry2D.get_closest_point_to_segment(point,at,tip).distance_to(point) <= float(threat.w)+6.0
		"cone":
			geometric = offset.length() <= float(threat.r)+6.0 and absf((threat.dir as Vector2).angle_to(offset)) <= float(threat.angle)
		_:
			geometric = offset.length() <= float(threat.r)+6.0
	if not geometric: return false
	return Combat.clear_line(at,point)

## LEVEL A: is there at least one reachable point outside every footprint that is damaging
## RIGHT NOW? False means the arena is currently fully denied.
##
## LEVEL B: is there at least one reachable point P such that no footprint covering P is active
## already or opens before the player could walk there? False means every reachable point is
## either covered now or covered by the time the player arrives - which is the brief's
## "warning overlap 导致理论上无法逃离" condition.
##
## Reachability uses the player's real collider against the real physics world (test_move), so a
## point behind a wall is not counted as an escape.
func escape_report() -> Dictionary:
	var player = Utils.player
	if not is_instance_valid(player): return {"reachable":0,"safe_now":0,"safe_timed":0,"modes":[]}
	var threats := _threats()
	var candidates: Array = [player.global_position]
	for i in PROBE_DIRECTIONS:
		var dir := Vector2.RIGHT.rotated(i*TAU/PROBE_DIRECTIONS)
		for radius in PROBE_RADII:
			if player.test_move(player.global_transform,dir*float(radius)): continue
			candidates.append(player.global_position+dir*float(radius))
	var safe_now := 0
	var safe_timed := 0
	var safe_fair := 0
	var modes := {}
	var fair_modes := {}
	for point in candidates:
		var blocked_now := false
		var blocked_timed := false
		var blocked_fair := false
		for threat in threats:
			if not _covers(threat,point): continue
			var travel: float = player.global_position.distance_to(point)/travel_speed
			if bool(threat.active):
				blocked_now = true; blocked_timed = true
				modes[str(threat.mode)] = true
				if bool(threat.fair): blocked_fair = true; fair_modes[str(threat.mode)] = true
			elif float(threat.eta) <= travel:
				# The footprint opens before the player can stand there, so this point is not
				# an escape either - but it was never safe to be there, so it does not deny.
				blocked_timed = true
				modes[str(threat.mode)] = true
				if bool(threat.fair): blocked_fair = true; fair_modes[str(threat.mode)] = true
			elif bool(threat.fair):
				# Opens after arrival and would still be legal for it to open: the point is
				# safe to reach but not safe to hold.
				blocked_fair = true; fair_modes[str(threat.mode)] = true
			else:
				fair_modes[str(threat.mode)] = true
		if not blocked_now: safe_now += 1
		if not blocked_timed: safe_timed += 1
		if not blocked_fair: safe_fair += 1
	var out := {"reachable":candidates.size(),"safe_now":safe_now,"safe_timed":safe_timed,
		"safe_fair":safe_fair,"modes":modes.keys(),"fair_modes":fair_modes.keys(),
		"threats":threats.size()}
	return out


# ======================================================================================
# Sampling
# ======================================================================================

func _process(delta: float) -> void:
	super._process(delta)
	if run_start == 0: return
	sample_clock -= delta
	if sample_clock > 0.0: return
	sample_clock = 1.0/SAMPLE_HZ
	_sample()

func _sample() -> void:
	var player = Utils.player
	if not is_instance_valid(player): return
	# Death is checked BEFORE the round-state gate. LevelServer flips to DEAD as soon as the
	# player dies, and return_to_camp() after that frees the arena, so gating on COMBAT here
	# would throw the death context away. This is the fallback path; the primary capture is in
	# the damage handler, where the arena is provably still alive.
	if player.is_dead:
		if death_at < 0.0:
			death_at = _now()
			death_snapshot = _snapshot(death_at)
		return
	if LevelServer.state != "COMBAT": return
	var now := _now()
	var actors = get_tree().get_nodes_in_group("monsters").filter(func(n): return not n.is_die and not n.training)
	var alive = actors.size()
	samples += 1
	alive_sum += alive; alive_peak = maxi(alive_peak,alive)
	projectile_peak = maxi(projectile_peak,get_tree().get_nodes_in_group("enemy_projectiles").size())
	zone_peak = maxi(zone_peak,get_tree().get_nodes_in_group("hostile_zone").size())
	hazard_peak = maxi(hazard_peak,get_tree().get_nodes_in_group(StageHazard.GROUP).size())
	horde_overlap_peak = maxi(horde_overlap_peak,LevelServer.horde_overlap_peak)
	flank_arrivals = maxi(flank_arrivals,LevelServer.flank_used)
	hp_min = minf(hp_min,float(PlayerData.player_hp))
	var near := 0
	var elites := 0
	for actor in actors:
		var distance = actor.global_position.distance_to(player.global_position)
		if distance < 80.0: near += 1
		if actor.get("is_elite") == true: elites += 1
		if not born.has(actor.get_instance_id()):
			born[actor.get_instance_id()] = actor.get_meta("content_id","")
			if actor.get_meta("content_id","") not in ["E01","E02"]: special_spawns += 1
			if not actor.get_meta("summoned",false):
				closest_spawn = minf(closest_spawn,distance)
				if Time.get_ticks_msec()-int(actor.get_meta("born_ms",0)) < 150 and distance < 60.0:
					illegal_near_spawns += 1
	near80_peak = maxi(near80_peak,near)
	elite_peak = maxi(elite_peak,elites)
	# Escape probe. The run's own verdict is sampled as well as the death snapshot's, so a
	# denial that the bot survived still shows up rather than being defined away by "it lived".
	last_escape = escape_report()
	probe_samples += 1
	escape_peak_live = maxi(escape_peak_live,int(last_escape.get("threats",0)))
	var modes := {}
	for mode in last_escape.get("modes",[]): modes[str(mode)] = true
	if int(last_escape.get("safe_now",0)) == 0:
		geometric_denial_samples += 1
		geometric_streak += 1
		geometric_streak_peak = maxi(geometric_streak_peak,geometric_streak)
		for mode in modes: geometric_modes[mode] = true
	else:
		geometric_streak = 0
	# The reported verdict is the FAIR one: a footprint the fog gate would not have let open
	# yet is not a denial, because HostileZone and StageHazard both refuse to activate before
	# their footprint has been readable from inside the player's light. Outside Hell the gate is
	# off everywhere, the two verdicts coincide, and `strict_*` is the diagnostic that proves
	# the distinction never changed a Normal-stage number.
	if int(last_escape.get("safe_fair",0)) == 0:
		denial_samples += 1
		denial_streak += 1
		for mode in last_escape.get("fair_modes",[]): denial_modes[str(mode)] = true
		denial_streak_peak = maxi(denial_streak_peak,denial_streak)
		if denial_streak == DENIAL_CONFIRM:
			denial_events.append({"at":now,"modes":last_escape.get("fair_modes",[]).duplicate()})
	else:
		denial_streak = 0
	if int(last_escape.get("safe_timed",0)) == 0: strict_denial_samples += 1
	if player.is_dead and death_at < 0.0:
		death_at = now
		death_snapshot = _snapshot(now)
	# Keep the ring bounded. It is trimmed on a timer rather than on every event so a burst of
	# pellets in one frame cannot thrash it.
	if ring.size() > 4 and now-float(ring[0].at) > RING_SECONDS+1.0:
		ring = ring.filter(func(e): return now-float(e.at) <= RING_SECONDS+1.0)

func _snapshot(now: float) -> Dictionary:
	var boss = instance_from_id(LevelServer.boss_instance) if LevelServer.boss_instance else null
	var recent := []
	for event in ring:
		if now-float(event.at) <= RING_SECONDS: recent.append(event)
	var modes := {}
	for zone in get_tree().get_nodes_in_group("hostile_zone"):
		if is_instance_valid(zone) and float(zone.damage) > 0.0:
			modes[str(zone.mode)] = int(modes.get(str(zone.mode),0))+1
	var hazards := {}
	for hazard in get_tree().get_nodes_in_group(StageHazard.GROUP):
		if is_instance_valid(hazard):
			hazards[str(hazard.kind)] = int(hazards.get(str(hazard.kind),0))+1
	return {
		"at":now,
		"lethal":lethal.duplicate(),
		"sequence":recent,
		"phase":("3" if boss != null and boss.get("phase_three") == true else ("2" if boss != null and boss.get("phase_two") == true else ("1" if boss != null else ""))),
		"boss_action":(str(boss.phase)+":"+str(boss.attack_kind)) if boss != null else "",
		"zones":modes,
		"hazards":hazards,
		"projectiles":get_tree().get_nodes_in_group("enemy_projectiles").size(),
		"fog":ArenaVisibility.fog_active(),
		"alive":get_tree().get_nodes_in_group("monsters").filter(func(n): return not n.is_die).size(),
		"escape":last_escape.duplicate()
	}


# ======================================================================================
# Reporting
# ======================================================================================

## Damage the player took, split by mechanism tag and by the brief's category list. The tag
## table is kept because "artillery" and "beam" are different design questions.
func damage_rows() -> Array:
	var rows := []
	for tag in ledger:
		var entry = ledger[tag]
		rows.append({"tag":tag,"hits":entry.hits,"applied":entry.applied,"raw":entry.raw,
			"category":category_for(tag,null)})
	rows.sort_custom(func(a,b): return float(a.applied) > float(b.applied))
	return rows

func category_rows() -> Array:
	var rows := []
	for key in categories:
		var entry = categories[key]
		rows.append({"category":key,"hits":entry.hits,"applied":entry.applied,
			"share":entry.applied/maxf(0.001,total_applied)})
	rows.sort_custom(func(a,b): return float(a.applied) > float(b.applied))
	return rows

func share_of(predicate: Callable) -> float:
	var total := 0.0
	for tag in ledger:
		if predicate.call(tag): total += float(ledger[tag].applied)
	return total/maxf(0.001,total_applied)

## Outcome of one run, in the shape the batch report quotes.
func row(outcome: String) -> Dictionary:
	var out := meta.duplicate()
	out["outcome"] = outcome
	out["clear"] = LevelServer.state == "CAMP" and not Utils.player.is_dead
	out["death"] = Utils.player.is_dead
	out["seconds"] = _now()
	out["death_at"] = death_at
	out["time_to_first_damage"] = time_to_first_damage
	out["hp_min"] = hp_min
	out["samples"] = samples
	out["alive_mean"] = float(alive_sum)/maxi(1,samples)
	out["alive_peak"] = alive_peak
	out["near80_peak"] = near80_peak
	out["elite_peak"] = elite_peak
	out["projectile_peak"] = projectile_peak
	out["hostile_zone_peak"] = zone_peak
	out["hazard_peak"] = hazard_peak
	out["horde_overlap_peak"] = horde_overlap_peak
	out["flank_arrivals"] = flank_arrivals
	out["spawns"] = born.size()
	out["special_spawns"] = special_spawns
	out["special_ratio"] = float(special_spawns)/maxi(1,born.size())
	out["illegal_near_spawns"] = illegal_near_spawns
	out["closest_spawn"] = closest_spawn
	out["movement"] = movement
	out["shots"] = shots_fired
	out["damage_total"] = total_applied
	out["hits_total"] = total_hits
	out["damage_by_tag"] = damage_rows()
	out["damage_by_category"] = category_rows()
	out["rooted_hits"] = rooted_hits
	out["rooted_damage"] = rooted_damage
	out["post_root_hits"] = post_root_hits
	out["post_root_damage"] = post_root_damage
	out["probe_samples"] = probe_samples
	out["denial_samples"] = denial_samples
	out["denial_streak_peak"] = denial_streak_peak
	out["denial_events"] = denial_events
	out["denial_modes"] = denial_modes.keys()
	out["strict_denial_samples"] = strict_denial_samples
	out["geometric_denial_samples"] = geometric_denial_samples
	out["geometric_streak_peak"] = geometric_streak_peak
	out["geometric_modes"] = geometric_modes.keys()
	out["escape_peak_live_footprints"] = escape_peak_live
	out["death_snapshot"] = death_snapshot
	out["travel_speed"] = travel_speed
	# B9 dodge telemetry: what the shared safe-movement core actually did this round. Every key
	# is namespaced `dodge_` and a key that a measurement field already owns is never replaced,
	# so this can add evidence but cannot overwrite a measurement.
	var dodge := dodge_report()
	for key in dodge:
		if not out.has(key): out[key] = dodge[key]
	return out

func write_json(path: String, data) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file = FileAccess.open(path,FileAccess.WRITE)
	if file == null: push_error("B8 cannot write "+path); return
	file.store_string(JSON.stringify(data,"\t")); file.close()

static func user_arg(prefix: String, fallback: String) -> String:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with(prefix): return arg.substr(prefix.length())
	return fallback

static func user_int(prefix: String, fallback: int) -> int:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with(prefix): return int(arg.substr(prefix.length()))
	return fallback

static func user_seeds(fallback: Array) -> Array:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("seeds="):
			var out := []
			for piece in arg.substr(6).split(",",false): out.append(int(piece))
			if not out.is_empty(): return out
	return fallback
