extends "res://game/monster/DemoEnemy.gd"

var summoned = false
var born_epoch = 0
var max_hp = 1.0
var armor = 0.0
var facing = Vector2.LEFT
var attack_index = 0
var actions: Dictionary = {}
## Kept by name: tests/M9Bosses.gd asserts `boss.phase_two`, and the HUD reads it.
var phase_two = false
## B批: bosses are 3-phase. Phase II at 70%, Phase III at 35%.
var phase_three = false
var heal_budget: Dictionary = {}
var children_ids: Array[int] = []
var owned_attacks: Array[WeakRef] = []
var summon_total = 0
var travelled = 0.0
var movement_clock = 0.0
var orbit_side = 1.0
var desired_point = Vector2.ZERO
var dash_speed = 300.0
var dash_seconds = 0.5
var dash_clock = 0.0
var phase_flash = 0.0
var ultimate_cooldown = 0.0
var attack_kind = ""
var phase_label: Label
var combo_queue: Array = []
var bulwark_spent = false

const PHASE_TWO_AT := 0.70
const PHASE_THREE_AT := 0.35
## Phase III scripts. Each entry is one whole boss turn, executed in order, which is what
## turns the last third into a set of linked problems instead of a faster first third.
const BOSS_CYCLES = {
	"1":{"B01":["charge","cleave","slam"],"B02":["brood","lockdown","pulse"],"B03":["dash","sweep","burst"],"B04":["dash","sweep","burst"]},
	"2":{"B01":["charge","cleave","slam"],"B02":["brood","lockdown","pulse"],"B03":["dash","sweep","burst"],"B04":["sweep","dash","cross","band"]},
	"3":{"B01":["charge","slam","shockwave"],"B02":["toxic_zone","root_shot","brood"],"B03":["cross_laser","sweep","burst"],"B04":["cross_laser","sweep","band"]}
}
## Attack kinds whose warning must be visible before they may connect. Used for the fog
## warning floor; the fog fairness gate inside HostileZone enforces the rest.
const DAMAGING_KINDS := ["detonate","cone","beam","artillery","tremor","cross","toxin","shockwave","cross_laser","root_shot","toxic_zone","band"]
## Extra mechanic per elite promotion. Only the MECHANISM lives here; the stat bump is a
## single bounded 1.5x HP applied by M5Content.promote_elite().
const ELITE_MODIFIERS = {
	"E01":"sprint","E02":"pack","E04":"double_charge","E05":"burst",
	"E03":"ram_shockwave","E06":"cluster","E07":"hive","E09":"bulwark",
	"E10":"root_artillery","E11":"fan","E12":"ember_field",
	"E13":"double_root","E14":"cross_beam","E15":"lingering_poison",
	"B01":"ram_shockwave","B02":"hive","B03":"cross_beam","B04":"ember_field"
}

func elite_modifier() -> String:
	return get_meta("elite_modifier","")

func _ready():
	super._ready()
	var d = M5Content.definition(role)
	HP = d.hp; max_hp = HP; SPEED = d.speed; armor = d.get("armor",0.0)
	born_epoch = LevelServer.epoch
	orbit_side = 1.0 if get_instance_id()%2 else -1.0
	is_boss = role.begins_with("B")
	sprite_body.scale = Vector2.ONE*(1.8 if is_boss else (1.15 if role in ["E03","E07","E09"] else 1.0))
	phase = "spawn"; phase_time = 0.3
	if is_boss:
		var hull = CircleShape2D.new(); hull.radius = 11 if role != "B04" else 13
		$CollisionShape2D.shape = hull; $CollisionShape2D.position = Vector2(0,-2)
		var title = Label.new(); phase_label = title
		title.text = d.name+" · PHASE I"; title.position = Vector2(-22,-47)
		title.add_theme_font_size_override("font_size",8); add_child(title)

func remember(action: String):
	actions[action] = actions.get(action,0)+1

func move_towards(point: Vector2, delta: float, multiplier = 1.0):
	path_refresh -= delta
	if path_refresh <= 0 or global_position.distance_to(cached_step) < 6:
		cached_step = LevelServer.town.path_step(global_position,point) if is_instance_valid(LevelServer.town) else point
		path_refresh = 0.2
	velocity = global_position.direction_to(cached_step)*SPEED*multiplier*(1.0-slow_amount if slow_time > 0 else 1.0)
	var previous = global_position; move_and_slide(); travelled += previous.distance_to(global_position)
	anim.play("run" if velocity.length() > 1 else "idle")

## Single factory for every warning footprint, so palette, fog piercing and the Hell warning
## floor cannot drift apart between attacks.
func zone(kind: String, point: Vector2, reach: float, delay: float, time = 0.12, style := "") -> Node2D:
	var node = load("res://game/monster/HostileZone.gd").new()
	node.mode = kind; node.radius = reach; node.length = reach
	node.warning = delay; node.duration = time; node.direction = locked_direction
	node.owner_ref = weakref(self)
	node.world_point = point
	node.style = style
	node.pierce = kind in ["line","charge"]
	if kind == "charge": node.width = 22 if is_boss else 18
	get_tree().current_scene.add_child(node)
	owned_attacks.append(weakref(node))
	# B10: a footprint laid down while the lock is still tracking re-aims with it. The anchor says
	# which half of the footprint follows: a ring created AT the lock point (the artillery and
	# poison circles) follows the point, while a lane created at this actor follows the direction.
	if lock_track > 0.0 and kind in TRACKED_KINDS:
		lock_zones.append({"ref":weakref(node),
			"anchor":("point" if point.distance_squared_to(locked_point) < 1.0 else "dir")})
	remember(kind)
	return node

## Registers a projectile the base class already created, so every projectile this actor
## fires is cleaned up when the actor dies or the phase changes.
func shot(dir: Vector2, speed_value = 100.0, damage_value = 1.0, muzzle_flash = true, style := "projectile", control := 0.0):
	var node = super.shot(dir,speed_value,damage_value,muzzle_flash,style,control)
	if node == null: return null
	owned_attacks.append(weakref(node))
	remember("shot")
	return node

func barrage(kind: String, count: int, waves: int, speed_value: float, spread_value = 0.85, style := "projectile", control := 0.0):
	var pattern = preload("res://game/monster/EnemyBarrage.gd").new()
	pattern.owner_ref = weakref(self); pattern.heading = locked_direction
	pattern.kind = kind; pattern.count = count; pattern.waves = waves
	pattern.speed = speed_value; pattern.spread = spread_value
	pattern.style = style; pattern.control = control
	pattern.shift = (0.24 if kind == "ring" else 0.18)*orbit_side
	get_tree().current_scene.add_child(pattern); owned_attacks.append(weakref(pattern))

func fan(count: int, spread: float, speed_value = 85.0, style := "projectile", control := 0.0):
	for i in count:
		shot(locked_direction.rotated(lerpf(-spread,spread,i/float(maxi(1,count-1)))),speed_value,1.0,true,style,control)

func summon(count: int, id = "E02"):
	children_ids = children_ids.filter(func(instance): return is_instance_id_valid(instance))
	if summoned: return
	var cap = (8 if is_boss else 3)+(2 if elite_modifier() == "hive" else 0)
	for i in count:
		if children_ids.size() >= cap or summon_total >= (24 if is_boss else 3): break
		if get_tree().get_nodes_in_group("monsters").filter(func(m): return not m.is_die).size() >= DemoConfig.ENCOUNTERS[LevelServer.level].cap: break
		var point = LevelServer.town.spawn_near(global_position,60.0,95.0,M5Content.radius_for(id))
		if point == Vector2.INF: continue
		var child = M5Content.spawn(id,get_parent(),point,true)
		if child:
			children_ids.append(child.get_instance_id()); summon_total += 1; remember("summon")

## Arena hazard owned by an actor rather than by the director (E15's sac, B02's toxic zone,
## elite E12's ember field). Shares the arena's live cap, coverage rule and "never under the
## player" rule, so a boss or a swarm cannot out-spam the stage rule or drop a field on the
## player's feet.
func release_field(kind: String, at: Vector2, warning_value: float, active: float, share: float, damage_value: float, radius_value: float) -> bool:
	var tree = get_tree()
	if tree.get_nodes_in_group(StageHazard.GROUP).size() >= 8: return false
	var player_at = Utils.player.global_position if is_instance_valid(Utils.player) else at
	if at.distance_to(player_at) < ArenaHazards.MIN_EDGE_DISTANCE+radius_value:
		remember("field_refused"); return false
	if is_instance_valid(LevelServer.town) and is_instance_valid(LevelServer.town.arena):
		var arena = LevelServer.town.arena
		if not arena.point_clear(at,radius_value*0.55+10.0): remember("field_refused"); return false
		if not arena.reachable_from_player(at): remember("field_refused"); return false
	var field = load("res://game/map/StageHazard.gd").new()
	field.kind = kind; field.at = at; field.owner_ref = weakref(self)
	field.warning = maxf(warning_value,ArenaHazards.WARNING_FLOOR if HellMode.is_hell(LevelServer.level) else 0.0)
	field.active_time = active; field.pulses = 1
	field.poison_share = share; field.damage = damage_value
	field.radius = radius_value; field.length = radius_value; field.width = radius_value
	tree.current_scene.add_child(field)
	owned_attacks.append(weakref(field))
	remember(kind)
	return true

func damage_pressure() -> float:
	return 1.0 if not HellMode.is_hell(LevelServer.level) else HellMode.damage_scale(LevelServer.level)

## ---- Attack scheduling --------------------------------------------------------------
##
## choose_attack() fills a queue for the turn instead of deciding one attack at a time, so a
## Phase III boss can script "charge, slam, shockwave, shockwave" as one problem.
func choose_attack():
	if is_boss and phase_two and ultimate_cooldown <= 0 and get_tree().get_nodes_in_group("boss_ultimate").is_empty():
		var ultimate = preload("res://game/monster/BossUltimate.gd").new()
		ultimate.role = role; ultimate.owner_ref = weakref(self)
		ultimate.position = global_position
		ultimate.direction = global_position.direction_to(Utils.player.global_position)
		get_tree().current_scene.add_child(ultimate); owned_attacks.append(weakref(ultimate))
		ultimate_cooldown = 15.0
		phase = "warn"; phase_time = ultimate.warning; attack_kind = "ultimate"
		remember("windup_ultimate"); return
	if combo_queue.is_empty():
		attack_index += 1
		locked_direction = global_position.direction_to(Utils.player.global_position)
		locked_point = Utils.player.global_position
		_schedule()
	if combo_queue.is_empty(): return
	_begin(combo_queue.pop_front())

func _schedule():
	if is_boss:
		var tier = "3" if phase_three else ("2" if phase_two else "1")
		var cycle: Array = BOSS_CYCLES[tier].get(role,BOSS_CYCLES[tier]["B03"])
		# Phases I and II keep the original three-attack rotation, so every authored base
		# attack still appears; Phase III walks its whole combo.
		combo_queue = cycle.duplicate() if phase_three else [cycle[(attack_index-1)%cycle.size()]]
		return
	match role:
		"E03","E11": combo_queue = ["charge"]
		"E06": combo_queue = ["detonate"]
		"E07": combo_queue = ["summon"]
		"E08": combo_queue = ["heal"]
		"E09","E12": combo_queue = ["cone"]
		"E10": combo_queue = ["beam"] if attack_index%2 else ["artillery"]
		# E13-E15: Hell-only mechanics.
		"E13": combo_queue = ["tremor"] if not is_elite else ["tremor","tremor"]
		"E14": combo_queue = ["beam"] if not is_elite else ["beam","cross"]
		"E15": combo_queue = ["toxin"]

## Combo pacing. A Phase III turn is a script (e.g. B03: cross laser, sweep, barrage, dash);
## without a gap between steps it lands as one unreadable burst, which is exactly the
## "difficulty from volume, not from mechanism" the batch must avoid. The gap gives the
## player a beat to reposition between problems.
const COMBO_GAP := 1.0

## ---- B11: per-attack clearance, and which footprints follow the lock -------------------------
##
## The mechanism lives ONCE, in the base class (game/monster/DemoEnemy.gd): a short TRACK window,
## then a FREEZE, then a COMPUTED reaction interval, then FIRE at the frozen geometry. Read that
## block for the arithmetic. What this class decides is only:
##
##   * `clearance(kind)`: how far the player must get from the frozen damage footprint, which is
##     what the reaction interval is computed from. It mirrors `HostileZone`'s own damage test and
##     `EnemyShot`'s own hit radius, so the number the window is built from is the number that
##     hurts. An attack whose geometry can grow (a boss phase II ring) reports the LARGER one.
##   * `LEAD_WANTED`: how much of the player's motion this attack would like to predict. Every
##     value is clamped by `lead_cap()` in the base class, so a wrong number here cannot make an
##     attack unavoidable - it can only waste the safety margin.
##   * `TRACKED_KINDS`: which footprints re-aim while the aim is STILL TRACKING. Nothing re-aims
##     after the freeze; a static lane must not follow anybody.
##
## A footprint's OWN warning is bumped by `HostileZone._ready()` to `FAIR_WARNING` in Hell, so the
## warning passed here is already a floor - and the frozen geometry it describes is what fires.
const LEAD_WANTED := {
	"beam":0.16,"cross":0.16,"cross_laser":0.16,"artillery":0.24,"tremor":0.20,
	"charge":0.0,"cone":0.18,"detonate":0.16,"toxin":0.16,"shockwave":0.16,
	"root_shot":0.24,"toxic_zone":0.24,"band":0.20,
	"cleave":0.18,"slam":0.18,"brood":0.0,"lockdown":0.20,"pulse":0.18,
	"dash":0.0,"sweep":0.16,"burst":0.18,"summon":0.0,"heal":0.0,
}
## Attacks whose real payload is a PROJECTILE rather than a footprint. They want a lead of the
## round's own flight time instead of a fixed fraction of a second, still clamped by `lead_cap()`.
const PROJECTILE_KINDS := {"artillery":140.0,"root_shot":150.0,"toxic_zone":130.0}
## Only these footprints re-aim with the lock, and only WHILE IT IS TRACKING. A summon/brood
## marker is decoration and must not follow anybody, and nothing follows the aim once it is frozen.
const TRACKED_KINDS := ["line","charge","cone","circle","tremor","artillery","toxin"]

## Footprint half-widths, kept as named constants because the reaction window is DERIVED from them:
## an edit that widens a lane without widening its window is then a visible inconsistency instead of
## a silent unfairness. Every value here is the REAL number the corresponding `zone()` call ends up
## with, and `tests/B11Fairness.gd` compares the constant against the live footprint rather than
## against this comment.

## `HostileZone.width` defaults to 8 and `zone()` only overrides it for a charge, so a laser lane,
## a sweep and a tremor lane are all 8 wide. The damage test is `dist_to_segment <= width + 6`.
const LASER_WIDTH := 8.0
## The sliding band is a `shock` lane, which keeps the same 8. Its danger is its SWEEP, not a wider
## line, so its clearance is the same as a laser's.
const BAND_WIDTH := 8.0
## Reach of the ring an untargeted `zone("circle", ...)` covers, used for the window.
const ARTILLERY_REACH := 40.0
const SLAM_REACH := 72.0
const DETONATE_REACH := 58.0
const SHOCKWAVE_REACH := 100.0
## Warning floor for a non-fog stage. The shortest authored wind-up this build ships, so a stage
## without fog keeps the pacing it was tuned with while every attack still gets its interval.
const BASE_WINDUP := 0.8

## Distance the player must put between themselves and this attack's frozen damage footprint.
## Read off the real geometry of the `_begin()` branches below, and deliberately CONSERVATIVE:
## for a cone it uses the full reach rather than the cheaper sideways exit, so the window is always
## at least what the geometry needs. Mirrors `HostileZone.step()`'s own tests
## (`distance_to_segment <= width+6` for a lane, `distance <= radius` for a circle) and
## `EnemyShot`'s 12 px hit radius, so the number the window is built from is the number that hurts.
func clearance(kind: String) -> float:
	match kind:
		"beam","cross","cross_laser","sweep","tremor":
			return required_clearance("line",0.0,LASER_WIDTH)
		# A boss charge lays a WIDER lane than an ordinary one (HostileZone width 22 against 18), and the
		# window is computed from the width that will really hurt, so a boss's own charge and dash both use
		# the boss extent. Anything else would leave a six-pixel blind spot in a boss's reaction window.
		"charge","dash": return required_clearance("charge",0.0,BOSS_CHARGE_WIDTH if is_boss else CHARGE_WIDTH)
		"cone": return required_clearance("circle",60.0,0.0)
		"root_shot": return required_clearance("circle",150.0,0.0)
		"pulse": return required_clearance("circle",160.0,0.0)
		"cleave": return required_clearance("circle",125.0,0.0)
		"burst": return required_clearance("circle",240.0,0.0)
		"artillery": return required_clearance("circle",ARTILLERY_REACH,0.0)
		"lockdown": return required_clearance("circle",65.0,0.0)
		"slam": return required_clearance("circle",SLAM_REACH,0.0)
		"detonate": return required_clearance("circle",DETONATE_REACH,0.0)
		"toxin": return required_clearance("circle",78.0,0.0)
		"toxic_zone": return required_clearance("circle",96.0,0.0)
		"shockwave": return required_clearance("circle",SHOCKWAVE_REACH,0.0)
		"band": return required_clearance("line",0.0,BAND_WIDTH)
	# A pure utility turn (summon, brood, heal) hurts nobody, so it needs no reaction interval.
	return 0.0

## The warning this `kind` is entitled to ask for, given the interval its own footprint needs.
## It is a FLOOR, not a tuning knob: `begin_lock()` extends it again if an edit asks for less.
func warning_seconds(kind: String) -> float:
	return maxf(BASE_WINDUP,warning_for(clearance(kind)))

## The FROZEN part of the wind-up: how long a footprint created NOW must warn before it may damage.
## Every `zone()` call below is given a delay derived from here, so a footprint's own countdown can
## never be shorter than the lock's promise nor longer than the warning the player was shown.
func freeze_after() -> float:
	return maxf(0.05,phase_time-lock_track)

func _begin(kind: String) -> void:
	attack_kind = kind
	var windup = warning_seconds(kind)
	if phase_three: windup *= 0.9
	if ArenaVisibility.fog_active() and kind in DAMAGING_KINDS: windup = maxf(windup,0.6)
	phase = "warn"
	lock_zones.clear()
	# The lock is taken BEFORE any footprint exists, so every footprint created below is registered
	# against a lock that is still tracking - and the freeze, when it comes, carries all of them to
	# the frozen geometry in ONE call and then stops for good.
	var lead := 0.0
	if PROJECTILE_KINDS.has(kind):
		lead = projectile_lead(float(PROJECTILE_KINDS[kind]),warning_for(clearance(kind)))
	else:
		lead = float(LEAD_WANTED.get(kind,0.16))
	# `phase_time` is the WHOLE wind-up, because that is what the actor loop counts down and what the
	# player is shown. `begin_lock()` is still called for its two real effects - it arms the tracking
	# window and it CLAMPS the lead - and the warning it would insist on is already satisfied here:
	# `windup` came from `warning_seconds()`, which is exactly `TRACK_SECONDS + reaction`, and no
	# later adjustment may cut into that. Where the later adjustment is one of the fog gate's, the
	# check below keeps the promise by restoring this kind's own floor.
	var promise: float = warning_for(clearance(kind))
	begin_lock(windup,lead,clearance(kind))
	phase_time = maxf(windup,promise)
	# From here down, `delay` ALWAYS means "seconds from now until the freeze", never "the whole
	# warning". A footprint whose own warning was the whole wind-up kept damaging after the actor had
	# already moved on, which is how a telegraph and a hit could disagree.
	var distance = global_position.distance_to(locked_point)
	var boost = damage_pressure()
	var delay = freeze_after()
	match kind:
		"charge":
			dash_speed = 265 if role == "E03" else (310 if role == "E11" else 290)
			if role == "B01": dash_speed = 330 if phase_two else 290
			if phase_three: dash_speed *= 1.08
			dash_seconds = clampf((distance+25)/dash_speed,0.25,0.9)
			# The lane damages ON CONTACT along its frozen length, which is exactly the region the
			# warning drew - the actor does not re-test distance and cannot catch anyone off-lane.
			zone("charge",global_position,dash_speed*dash_seconds,delay,0.12,"charge").damage = contact_damage()
		"detonate":
			# Self-destruct: a readable fuse, then a blast at the actor's own feet.
			var reach = DETONATE_REACH if elite_modifier() == "cluster" else 42
			var fuse = warning_for(clearance("detonate"))
			zone("circle",global_position,reach,fuse,0.12,"detonate").damage = 0
			if elite_modifier() == "cluster":
				zone("circle",global_position,34,fuse+0.4,0.12,"detonate").damage = 0
			phase_time = fuse
		"summon","heal": pass
		"cone":
			# Breath attack: its own reach sets the window, so the footprint and the interval match.
			var breath = maxf(delay,warning_for(clearance("cone")))
			zone("cone",global_position,60,breath,0.12,"detonate").angle = 1.25 if elite_modifier() == "bulwark" else 0.7
		"beam":
			# E14 is the long-range sentinel: a longer lane, the same readable freeze, and a lane
			# that pierces the fog so its direction survives the darkness it is fired through.
			var lane = 360.0 if role == "E14" else 280.0
			var burn = 0.35 if role == "E14" else 0.3
			var beam = zone("line",global_position,lane,maxf(delay,warning_for(clearance("beam"))),burn,"laser")
			beam.damage = boost*0.6
			beam.pierce = true
			# A bounded sweep, only for a promoted sentinel. The warning draws the whole arc it will
			# cover, so "it turned while I was standing there" is never a surprise.
			if role == "E14" and (is_elite or elite_modifier() == "double_beam"):
				beam.sweep = orbit_side*0.42
		"artillery":
			var strike = maxf(delay,warning_for(clearance("artillery")))
			zone("circle",locked_point,ARTILLERY_REACH,strike,0.12,"artillery")
			# A promoted bombardier marks a SECOND area, spread SIDEWAYS across the player's own line
			# of travel. Two areas, not a carpet, and no prediction: both sit where the frozen lock
			# point is, so both are where the warning is drawn.
			if is_elite:
				zone("circle",locked_point+locked_direction.orthogonal()*72.0*orbit_side,36,strike+0.2,0.12,"artillery")
			phase_time = strike
		"tremor":
			# Low direct damage; the payload is the root, routed through Hero.apply_root().
			var quake = maxf(delay,warning_for(clearance("tremor")))
			zone("line",global_position,240,quake,0.22,"root").damage = boost*0.3
			phase_time = quake
		"cross":
			locked_direction = global_position.direction_to(locked_point)
			var star = maxf(delay,warning_for(clearance("cross")))
			for i in 4:
				var lane = zone("line",global_position,320,star,0.22,"laser")
				lane.direction = locked_direction.rotated(i*PI/2)
				lane.initial_direction = lane.direction
				lane.damage = boost*0.5
				lane.pierce = true
			phase_time = star
		"toxin":
			# The sac swells visibly before it drops, so the field is never a surprise.
			zone("circle",global_position,78,maxf(delay,warning_for(clearance("toxin"))),0.12,"poison").damage = 0
		"shockwave":
			# Ground pound, sized to its own wind-up. The old version stacked a 140 ring and a 100
			# ring 0.5 s apart, which nobody could leave from the centre: the inner blast landed
			# inside the outer one's own reaction interval, so the pair was not dodgeable as a pair.
			# One ring, one commitment, and the window its radius actually needs.
			var pound = maxf(delay,warning_for(clearance("shockwave")))
			zone("circle",global_position,SHOCKWAVE_REACH,pound,0.12,"detonate")
			phase_time = pound
		"cross_laser":
			locked_direction = global_position.direction_to(locked_point)
			# Four lanes with a long bright warning and a short burn: the pattern is the problem to
			# solve, not a long tick window to stand inside.
			var grid = maxf(delay,warning_for(clearance("cross_laser")))
			for i in 4:
				var lance = zone("line",global_position,360,grid,0.35,"laser")
				lance.direction = locked_direction.rotated(i*PI/2+PI/4)
				lance.initial_direction = lance.direction
				lance.damage = boost*0.5
				lance.pierce = true
			phase_time = grid
		"root_shot":
			var bind = zone("cone",global_position,150,maxf(delay,warning_for(clearance("root_shot"))),0.12,"root")
			bind.angle = 0.85; bind.damage = boost*0.3; bind.control = 0.45
		"toxic_zone":
			var field = maxf(delay,warning_for(clearance("toxic_zone")))
			var spot = locked_point+Vector2.RIGHT.rotated(randf()*TAU)*130.0
			if not release_field("poison",spot,1.1,4.5,0.014,1.0,96.0):
				zone("circle",locked_point,70,field,0.12,"poison").damage = boost*0.8
			phase_time = field
		"band":
			# A moving danger band: it warns in place, then slides sideways, so standing still is what
			# kills rather than standing in one marked circle. The warning draws the swept path and
			# the damage follows the same rotation, so the two cannot disagree.
			var slide = maxf(delay,warning_for(clearance("band")))
			var side = Vector2.RIGHT.rotated(locked_direction.angle()+PI/2)*orbit_side
			var band = zone("line",global_position-side*220.0,320,slide,1.2,"shock")
			band.direction = side
			band.initial_direction = side
			band.sweep = orbit_side*0.9
			band.damage = boost*0.6
			phase_time = slide
		# ---- base attacks ---------------------------------------------------------------------
		"slam": zone("circle",global_position,SLAM_REACH,maxf(delay,warning_for(clearance("slam"))),0.12,"artillery")
		"brood": zone("summon",global_position,42 if phase_two else 34,delay,0.12,"summon").damage = 0
		"lockdown":
			# Three marks, each with its own full warning, so leaving the first is a real answer and
			# the later ones are separate problems rather than a stacked unavoidable hit.
			var mark = maxf(delay,warning_for(clearance("lockdown")))
			zone("circle",locked_point,65,mark,0.12,"artillery")
			zone("circle",locked_point+locked_direction.orthogonal()*80.0,48,mark+0.25,0.12,"artillery")
			if phase_two:
				zone("circle",locked_point-locked_direction.orthogonal()*80.0,45,mark+0.5,0.12,"artillery")
			phase_time = mark
		"pulse": zone("cone",global_position,160,maxf(delay,warning_for(clearance("pulse"))),0.12,"detonate").angle = 0.9
		"dash":
			dash_speed = 440*(1.08 if phase_three else (1.0 if phase_two else 0.95))
			dash_seconds = clampf(global_position.distance_to(locked_point)/dash_speed,0.24,0.7)
			var rush = maxf(delay,warning_for(clearance("dash")))
			zone("charge",global_position,dash_speed*dash_seconds,rush,0.12,"charge").damage = contact_damage()
			phase_time = rush
		"sweep":
			locked_direction = locked_direction.rotated(-orbit_side*0.25)
			var rate = (1.3 if phase_two else 1.0)*(1.15 if phase_three else 1.0)
			var swath = maxf(delay,warning_for(clearance("sweep")))
			zone("line",global_position,330,swath,0.85,"sweep").sweep = orbit_side*rate
			phase_time = swath
		"burst": zone("cone",global_position,240,maxf(delay,warning_for(clearance("burst"))),0.12,"projectile").damage = 0
	remember("windup_"+attack_kind)

## Footprints already on the ground that travel with the lock: {"ref":WeakRef, "anchor":"point"|"dir"}.
var lock_zones: Array = []

## Carries every live warning footprint along with the lock, and is called ONLY from step_lock()
## while the aim is still tracking. A ring created AT the lock point (the artillery and poison
## circles) follows the point; a lane created at this actor follows the direction. After the
## freeze the base class never calls this again, so every footprint ends up on the frozen geometry.
func refresh_zones() -> void:
	lock_zones = lock_zones.filter(func(entry): return is_instance_valid(entry.ref.get_ref()))
	for entry in lock_zones:
		var node = entry.ref.get_ref()
		if not is_instance_valid(node): continue
		if entry.anchor == "point": node.global_position = locked_point
		node.direction = locked_direction
		node.initial_direction = locked_direction

func perform_attack():
	remember("attack"); remember(attack_kind)
	# E14's zone can extend its warning for visibility. Only that zone's real
	# activation may flash its laser source; the actor timer is not proof of firing.
	if role!="E14":
		preload("res://game/effects/HostileVFX.gd").emit_at(get_tree().current_scene,global_position,24 if is_boss else 12,locked_direction,"charge" if attack_kind == "charge" else "projectile")
	# Phase II starts earlier (70%) than the original 50%, so its per-attack pacing is a
	# little GENTLER than the original to keep the total pressure curve rising instead of
	# spiking. Phase III is the fast one, and only by a small step.
	phase = "recover"; phase_time = 0.75 if not phase_two else (0.48 if phase_three else 0.56)
	# A scripted Phase III turn leaves a beat between its steps instead of chaining them into
	# one unreadable burst.
	if not combo_queue.is_empty(): phase_time = maxf(phase_time,COMBO_GAP)
	var boost = damage_pressure()
	match role:
		"E03","E11":
			phase = "dash"; phase_time = dash_seconds
			if role == "E11" and is_elite: barrage("fan",10,1,120,0.9)
		"E06":
			# Self-destruct is a percentage-free burst, but its radius now scales with the
			# elite modifier rather than only with the telegraph.
			var reach = 58 if elite_modifier() == "cluster" else 42
			if global_position.distance_to(Utils.player.global_position)<=reach and Combat.clear_line(global_position,Utils.player.global_position):
				Utils.player.onHit(boost*contact_damage(),self,1.0,"detonate")
			last_context = {"depth":1}; onDie()
		"E07": summon(2 if elite_modifier() == "hive" else 1); phase_time = 2.0
		"E08":
			var healed = 0
			for other in get_tree().get_nodes_in_group("monsters"):
				if other == self or other.is_die or other.is_boss or other.get_meta("content_id","") == "E08": continue
				var id = other.get_instance_id()
				if global_position.distance_to(other.global_position)>155 or not Combat.clear_line(global_position,other.global_position): continue
				var maximum = M5Content.definition(other.get_meta("content_id","E01")).get("hp",2.0)
				var amount = minf(1.0,minf(maximum-other.HP,3.0-heal_budget.get(id,0.0)))
				if amount<=0: continue
				other.HP += amount; heal_budget[id] = heal_budget.get(id,0.0)+amount; remember("heal")
				Combat.trace([global_position,other.global_position],Color(0.3,1,0.6)); healed += 1
				if healed == 2: break
			phase_time = 1.7
		"E10":
			phase_time = 0.9
			if attack_kind == "artillery":
				var root = elite_modifier() == "root_artillery"
				# B10: 115 -> 140. Still slower than the player's own speed, so the pattern stays
				# readable and walking out of it still works - but no longer so slow that a single
				# constant strafe is a complete answer. The centre pellet leads because the lock
				# itself now carries a bounded lead.
				barrage("fan",12 if is_elite else 6,1,140,0.9,"root" if root else "projectile",0.4 if root else 0.0)
		"E13":
			# Tremor shooter: one control shot, or two when promoted. Low direct damage; the
			# payload is the root, and Hero's 1.2 s immunity still governs its real uptime.
			phase_time = 1.4
			var shots = 2 if elite_modifier() == "double_root" else 1
			for i in shots:
				var spread = 0.0 if shots == 1 else lerpf(-0.25,0.25,i/float(shots-1))
				# B10: 130 -> 150, and the lock's bounded lead aims the shot where the player is
				# going. Still far short of a hitscan, and the purple root round stays visually
				# distinct from plain damage so the control threat is never read as just a hit.
				shot(locked_direction.rotated(spread),150,boost*0.35,true,"root",0.45)
		"E14":
			phase_time = 2.2
			remember("beam_fired")
		"E15":
			phase_time = 1.6
			var bigger = elite_modifier() == "lingering_poison"
			if not release_field("poison",global_position,0.85,5.2 if bigger else 3.4,0.012 if not bigger else 0.016,1.0,92.0 if bigger else 78.0):
				remember("toxin_refused")
		"B01":
			if attack_kind == "charge":
				phase = "dash"; phase_time = dash_seconds
			elif attack_kind == "slam":
				barrage("ring",23 if phase_two else 19,2 if phase_two else 1,115,0.85,"artillery")
			elif attack_kind == "shockwave":
				barrage("ring",25,2,120,0.85,"detonate")
		"B02":
			if attack_kind == "brood":
				summon(3,"E06" if phase_two else "E02")
				barrage("ring",28 if phase_two else 24,3 if phase_two else 2,115,0.85)
			elif attack_kind == "pulse":
				barrage("fan",23 if phase_two else 17,3 if phase_two else 2,130,1.3)
			elif attack_kind == "root_shot":
				barrage("fan",9,2,120,1.0,"root",0.45)
			phase_time = 1.0 if not phase_two else 0.65
		"B03":
			if attack_kind == "dash":
				phase = "dash"; phase_time = dash_seconds
			elif attack_kind == "burst":
				barrage("fan",17 if phase_two else 13,3 if phase_two else 2,160,1.0)
		"B04":
			if attack_kind == "dash":
				phase = "dash"; phase_time = dash_seconds
			elif attack_kind == "burst":
				barrage("fan",19 if phase_three else 15,3 if phase_three else 2,150,1.15)
			elif attack_kind == "cross":
				barrage("ring",26,2,120,0.85,"laser")
			phase_time = 0.95 if not phase_two else 0.6

func _physics_process(delta):
	if is_die: return
	if born_epoch != LevelServer.epoch: queue_free(); return
	if LevelServer.state != "COMBAT" or not is_instance_valid(Utils.player) or Utils.player.is_dead: velocity = Vector2.ZERO; return
	ultimate_cooldown = maxf(0,ultimate_cooldown-delta)
	phase_time -= delta; contact_cooldown = maxf(0,contact_cooldown-delta)
	phase_flash = maxf(0,phase_flash-delta); queue_redraw()
	if state_array.has(Utils.STATE_TYPE.STUN): return
	if hit: move_and_slide(); return
	# B11.1: `filter()` allocates a new array (and re-converts the untyped result back to
	# `Array[WeakRef]`) on EVERY physics frame of EVERY live monster, for a list that is empty most
	# of the time. Filtering an empty array can only return an empty array, so the empty case is
	# skipped outright. Identical contents either way.
	if not owned_attacks.is_empty():
		owned_attacks = owned_attacks.filter(func(ref): return is_instance_valid(ref.get_ref()))
	if is_boss and not phase_two and HP<=max_hp*PHASE_TWO_AT: _enter_phase(2)
	if is_boss and phase_two and not phase_three and HP<=max_hp*PHASE_THREE_AT: _enter_phase(3)
	if phase == "spawn" or phase == "transition":
		if phase == "spawn": move_towards(Utils.player.global_position,delta,0.8)
		if phase_time<=0: phase = "move"; phase_time = 0.3
		return
	if phase == "warn":
		velocity = Vector2.ZERO
		# B10: the aim keeps following the player for the first part of the warning, then freezes
		# with a bounded lead. See LOCK_TRACK_SHARE.
		step_lock(delta)
		if phase_time<=0: perform_attack()
		return
	if phase == "dash":
		var previous = global_position; velocity = locked_direction*dash_speed; move_and_slide()
		travelled += previous.distance_to(global_position)
		dash_clock += delta
		if dash_clock>0.08:
			dash_clock = 0
			preload("res://game/effects/HostileVFX.gd").emit_at(get_tree().current_scene,previous,10,locked_direction,"charge")
		contact(24)
		if phase_time<=0 or get_slide_collision_count()>0:
			phase = "recover"; phase_time = 0.5 if not phase_three else 0.42; remember("dash_end"); orbit_side *= -1
			if role == "B03" and phase_two:
				locked_direction = -locked_direction; barrage("fan",9,1,140,0.8)
			if role == "E03" and elite_modifier() == "ram_shockwave":
				# Elite E03: the dash leaves a real hazard behind instead of just a bump.
				zone("circle",global_position,72,0.5,0.12,"detonate")
				barrage("fan",6,1,120,0.9)
			if role == "B01" and phase_three:
				locked_direction = global_position.direction_to(Utils.player.global_position)
		return
	var distance = global_position.distance_to(Utils.player.global_position)
	facing = facing.rotated(clampf(facing.angle_to(global_position.direction_to(Utils.player.global_position)),-delta*2.8,delta*2.8))
	movement_clock -= delta
	if movement_clock<=0:
		movement_clock = 0.25; desired_point = movement_target(distance)
	var multiplier = 1.0
	# Baseline pacing, deliberately unchanged: Phase pressure comes from the new combos and
	# from hazards, not from a compounding speed multiplier on top of the existing one.
	if is_boss and (phase_two or distance>190): multiplier = 1.15
	move_towards(desired_point,delta,multiplier)
	if role not in ["E08","E10","E13","E14"]: contact(24 if is_boss else 19)
	if phase == "recover":
		if phase_time<=0: phase = "move"; phase_time = 0.15
		return
	if role == "E07" and summoned: return
	var reach = 240.0
	if role in ["E09","E12"]: reach = 55
	elif role == "E06": reach = 34
	elif role == "E11": reach = 125
	elif role == "E13": reach = 255
	elif role == "E14": reach = 350
	elif role == "E15": reach = 68
	elif role == "B01": reach = 260 if (phase_three or (attack_index+1)%3==1) else 95
	elif role == "B02": reach = 240 if (phase_three or (attack_index+1)%3!=0) else 145
	elif role == "B04": reach = 300 if phase_three else 265
	if distance<reach and phase_time<=0 and Combat.clear_line(global_position,Utils.player.global_position): choose_attack()

## A phase transition is the boss's own safe window: owned attacks are cleared, the boss
## stops attacking for 1.1 s and flashes, so a phase change can never be a free hit on the
## player, and the player never loses HP during the switch either.
func _enter_phase(tier: int):
	if tier == 2: phase_two = true
	else: phase_three = true
	ultimate_cooldown = 3.0 if tier == 2 else 5.0
	phase = "transition"; phase_time = 1.4; phase_flash = 1.0
	remember("phase_" + ("two" if tier == 2 else "three"))
	if phase_label:
		phase_label.text = M5Content.definition(role).name+" · PHASE "+("II" if tier == 2 else "III")
	for ref in owned_attacks:
		if is_instance_valid(ref.get_ref()): ref.get_ref().queue_free()
	owned_attacks.clear()
	combo_queue.clear()
	orbit_side *= -1
	preload("res://game/effects/HostileVFX.gd").emit_at(get_tree().current_scene,global_position,60,Vector2.RIGHT,"detonate")
	preload("res://game/effects/HostileVFX.gd").emit_at(get_tree().current_scene,global_position,44,Vector2.UP,"sweep")
	if tier == 2 and role == "B01": summon(2,"E09")
	if tier == 3:
		# Phase III identity: the late bosses narrow the fight, and Hell's final boss narrows
		# the vision as well. Bounded, and cleared when the boss dies or the epoch advances.
		if role == "B03": ArenaVisibility.tighten_phase(0.9)
		if role == "B04": ArenaVisibility.tighten_phase(0.82)
		if role == "B02": release_field("poison",global_position,1.2,6.0,0.016,1.0,110.0)

func contact(reach: float):
	if global_position.distance_to(Utils.player.global_position)<reach and contact_cooldown<=0:
		Utils.player.onHit(contact_damage(),self,1.0,"contact")
		contact_cooldown = 0.85; remember("contact")

func movement_target(distance: float) -> Vector2:
	var player = Utils.player.global_position
	var radial = player.direction_to(global_position)
	if role == "E08":
		var ally = null; var best = 240.0
		for other in get_tree().get_nodes_in_group("monsters"):
			if other == self or other.is_die or other.get_meta("content_id","") in ["E08","E10"]: continue
			var d = other.global_position.distance_to(player)
			if d<best: best = d; ally = other
		if ally and distance>65: return ally.global_position+radial*40+radial.orthogonal()*orbit_side*25
		return player+radial.rotated(orbit_side*0.65)*90
	if role in ["E10","E13"]:
		# Both stop and shoot, but the tremor shooter holds a longer line.
		var keep = 145.0 if role == "E10" else 205.0
		return player+radial.rotated(orbit_side*0.6)*keep if distance<keep+45 else player
	if role == "E14":
		return player+radial.rotated(orbit_side*0.35)*275.0 if distance<310 else player
	if role == "E07":
		return player+radial.rotated(orbit_side*0.6)*70 if not summoned and distance<130 else player
	if role in ["E11","B03","B04"]:
		if distance>145 or not Combat.clear_line(global_position,player): return player
		return player+radial.rotated(orbit_side*0.9)*(45 if phase_two or role == "E11" else 70)
	if role == "B02":
		return player if attack_index%3 == 2 or phase_two else player+radial.rotated(orbit_side*0.7)*95
	if role == "B01":
		return player if distance>120 or phase_three else player+radial.rotated(orbit_side*0.45)*90
	if role == "E09":
		# A broad pushing front with alternating sides instead of a single-file queue.
		return player+radial.orthogonal()*orbit_side*minf(32,distance*0.15)
	return player

func receive_damage(amount: float, critical: bool, context: Dictionary):
	if armor > 0:
		var source = context.get("impact_origin",Utils.player.global_position)
		var protected = role != "E09" or absf(facing.angle_to(global_position.direction_to(source))) < 1.05
		if protected:
			armor = maxf(0,armor-amount); amount *= 0.45; remember("armor_hit")
			if armor == 0:
				remember("armor_break"); flash_time = 0.15
				# Elite E09: the shield reforms exactly once, so the frontal window has to be
				# earned rather than merely waited out.
				if role == "E09" and elite_modifier() == "bulwark" and not bulwark_spent and is_instance_valid(Utils.player):
					bulwark_spent = true; armor = M5Content.definition(role).get("armor",7.0)
					preload("res://game/effects/HostileVFX.gd").emit_at(get_tree().current_scene,global_position,40,facing,"shock")
					remember("armor_reform")
	super.receive_damage(amount,critical,context)

func onDie(effects = true):
	if is_die: return
	for ref in owned_attacks:
		if is_instance_valid(ref.get_ref()): ref.get_ref().queue_free()
	if LevelServer.state == "COMBAT" and born_epoch == LevelServer.epoch:
		if role == "E07" and not summoned: summon(2)
		if role == "E12" and last_context.get("depth",0) < DemoConfig.MAX_DERIVATION:
			var blast = load("res://game/monster/HostileZone.gd").new()
			blast.radius = 58; blast.warning = 0.08; blast.world_point = global_position; blast.style = "shock"
			blast.friendly_context = {"damage":4.0,"depth":last_context.get("depth",0)+1,"epoch":born_epoch}
			get_tree().current_scene.add_child(blast)
			if elite_modifier() == "ember_field":
				# Hostile counterpart, so a promoted carrier denies ground as it dies.
				release_field("vent",global_position,0.8,1.2,0.0,1.0,70.0)
		if role == "E15":
			# The carrier's death drops one short field. The live cap, the coverage rule and
			# the "never under the player" rule are all enforced inside release_field().
			var bigger = elite_modifier() == "lingering_poison"
			release_field("poison",global_position,0.85,5.2 if bigger else 3.4,0.016 if bigger else 0.012,1.0,92.0 if bigger else 78.0)
	if is_boss:
		ArenaVisibility.clear_phase_tighten()
		for id in children_ids:
			var child = instance_from_id(id)
			if is_instance_valid(child): child.queue_free()
	super.onDie(effects)
	if is_boss: LevelServer.boss_defeated.call_deferred(born_epoch)

func _draw():
	super._draw()
	if is_die: return
	# Source-only charge brackets use the actual tracking/frozen state. The
	# footprint still owns the firing edge (including the fog fairness extension).
	if phase=="warn" and attack_kind!="ultimate":
		var ink=Color(0.95,0.78,0.35) if not lock_frozen else Color(0.9,0.98,1)
		var extent=16.0 if lock_frozen else 21.0
		var center=Vector2(0,-8)
		for i in 4:
			var dir=Vector2.RIGHT.rotated(PI/4+i*PI/2)
			var point=center+dir*extent
			draw_line(point,point-dir.rotated(-0.65)*5,ink,1.5,true)
			draw_line(point,point-dir.rotated(0.65)*5,ink,1.5,true)
	var color = Color(0.4,0.9,1) if armor <= 0 else Color(1,0.8,0.3)
	if role in ["E03","E09","B01"]:
		var dir = facing.angle(); draw_arc(Vector2(0,-7),28 if is_boss else 18,dir-1.05,dir+1.05,12,color,3)
	if role == "E08": draw_line(Vector2(-5,-26),Vector2(5,-26),Color(0.3,1,0.6),2); draw_line(Vector2(0,-31),Vector2(0,-21),Color(0.3,1,0.6),2)
	if role == "E07": draw_arc(Vector2(0,-18),9,0,TAU,6,Color(0.6,0.8,1),2)
	if role == "E06": draw_circle(Vector2(0,-22),4,Color(1,0.3+0.2*sin(phase_time*25),0.1))
	if role == "E10": draw_line(Vector2(0,-18),facing*17+Vector2(0,-18),Color(1,0.7,0.3),2)
	if role == "E11": draw_polyline(PackedVector2Array([Vector2(-10,-20),Vector2(0,-27),Vector2(10,-20)]),Color(0.8,0.4,1),2)
	if role == "E12": draw_circle(Vector2(0,-20),5,Color(0.2,0.9,1))
	# E13-E15 silhouettes: a control emitter, a long barrel, and a swollen sac.
	if role == "E13":
		draw_arc(Vector2(0,-20),7,0,TAU,10,Color(0.8,0.45,1),2)
		draw_line(Vector2(-6,-14),Vector2(-6,-26),Color(0.8,0.45,1),1.5)
		draw_line(Vector2(6,-14),Vector2(6,-26),Color(0.8,0.45,1),1.5)
	if role == "E14":
		draw_line(Vector2(0,-18),facing*26+Vector2(0,-18),Color(0.45,0.95,1),2)
		draw_circle(Vector2(0,-18),4,Color(0.3,0.85,1))
	if role == "E15":
		draw_circle(Vector2(0,-21),6,Color(0.35,0.95,0.5))
		draw_arc(Vector2(0,-21),8,0,TAU,12,Color(0.6,1,0.7),1.5)
	if role == "B04":
		# Abyss core identity: a fractured rotating ring, unmistakably not a recoloured B03.
		for i in 4:
			var a = fmod(Time.get_ticks_msec()*0.0012,TAU)+i*PI/2
			draw_arc(Vector2(0,-8),34,a-0.5,a+0.5,10,Color(0.55,0.35,1,0.85),3)
		draw_circle(Vector2(0,-8),10,Color(0.2,0.05,0.4,0.9))
		draw_arc(Vector2(0,-8),13,0,TAU,20,Color(0.75,0.5,1),2)
	if is_boss:
		draw_rect(Rect2(-27,-37,54,4),Color(0.1,0.1,0.1))
		draw_rect(Rect2(-27,-37,54*maxf(0,HP/max_hp),4),Color(0.85,0.4,1) if phase_three else (Color(1,0.4,0.2) if phase_two else Color(0.9,0.8,0.3)))
		draw_line(Vector2(0,-38),Vector2(0,-32),Color(0.05,0.04,0.02),2)
		# Health-bar dividers at the real thresholds, so 70% and 35% are readable on the boss.
		for mark in [PHASE_TWO_AT,PHASE_THREE_AT]:
			draw_line(Vector2(-27+54*mark,-38),Vector2(-27+54*mark,-32),Color(0.05,0.04,0.02),2)
		if phase_two: draw_arc(Vector2(0,-8),30,0,TAU,36,Color(1,0.4,0.12,0.65),2,true)
		if phase_three: draw_arc(Vector2(0,-8),30,0,TAU,36,Color(0.8,0.3,1,0.8),3,true)
