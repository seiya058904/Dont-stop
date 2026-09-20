extends Node2D

## Owns every arena hazard for one round.
##
## It exists so that no single hazard kind, and no per-map special case, is written into
## Town.gd: the director reads ArenaHazards.plan(stage), places hazards on validated
## anchors, enforces the coverage budget and ticks poison once for the whole arena.
##
## Bound to LevelServer.epoch and LevelServer.level. When the epoch advances (return to
## camp, death, next departure) the director frees itself and every hazard it made, so a
## live hazard can never survive a round - which is also why it registers in
## `combat_transient` rather than relying on Town.gd's cleanup list.
const GROUP := "hazard_director"
const POISON_WINDOW := 0.5

var epoch := -1
var stage := 0
var plan: Dictionary = {}
var arena: Node2D
var spawn_clock := 0.0
var poison_clock := 0.0
var rng := RandomNumberGenerator.new()
var live_peak := 0
var coverage_peak := 0.0
var poison_ticks := 0
var meteor_wait := 0.0
var round_time := 0.0
var meteor_spawned := 0

## Fixed-seed support for tests: when non-zero the director reproduces its hazard sequence
## exactly, so a Hazard audit can assert the same run twice.
static var fixed_seed := 0
static var last_director: WeakRef

static func audit_snapshot() -> Dictionary:
	return {
		"spawned":StageHazard.audit_spawned,
		"rejected":StageHazard.audit_rejected,
		"skipped_anchor":StageHazard.audit_skipped_anchor,
		"peak_live":StageHazard.audit_peak_live,
		"peak_coverage":StageHazard.audit_peak_coverage,
		"poison_ticks":StageHazard.audit_poison_ticks,
		"poison_capped":StageHazard.audit_poison_capped
	}

static func reset_audit() -> void:
	StageHazard.audit_spawned = 0
	StageHazard.audit_rejected = 0
	StageHazard.audit_skipped_anchor = 0
	StageHazard.audit_peak_live = 0
	StageHazard.audit_peak_coverage = 0.0
	StageHazard.audit_poison_ticks = 0
	StageHazard.audit_poison_capped = 0

static func live_count(tree: SceneTree) -> int:
	if tree == null: return 0
	return tree.get_nodes_in_group(StageHazard.GROUP).size()

func _ready() -> void:
	epoch = LevelServer.epoch
	stage = LevelServer.level
	plan = ArenaHazards.plan(stage)
	add_to_group(GROUP)
	add_to_group("combat_transient")
	last_director = weakref(self)
	rng.seed = fixed_seed if fixed_seed != 0 else hash([stage,epoch,808])
	# First hazard is spaced out so the round opens with the roster, not with terrain.
	spawn_clock = plan.get("interval",9.0)*0.6
	# Deliberately NOT freed when the plan is empty. The director is also the arena's poison
	# coordinator, and an ACTOR can put a field on the ground on a stage whose terrain plan is
	# empty - B02's Phase III toxic zone on Stage 20 is exactly that case. Without a director
	# those fields would be drawn and never ticked.

func _physics_process(delta: float) -> void:
	if epoch != LevelServer.epoch or LevelServer.state != "COMBAT":
		queue_free(); return
	# Poison is coordinated for the whole arena, whatever put the field there.
	_tick_poison(delta)
	if plan.is_empty() or not is_instance_valid(arena): return
	round_time += delta
	meteor_wait += delta
	spawn_clock -= delta
	if spawn_clock <= 0.0:
		spawn_clock = float(plan.interval)
		_spawn()
	_track()

func _track() -> void:
	var live = get_tree().get_nodes_in_group(StageHazard.GROUP).size()
	live_peak = maxi(live_peak,live)
	StageHazard.audit_peak_live = maxi(StageHazard.audit_peak_live,live)
	var coverage = coverage_share()
	coverage_peak = maxf(coverage_peak,coverage)
	StageHazard.audit_peak_coverage = maxf(StageHazard.audit_peak_coverage,coverage)

func walkable_area() -> float:
	if is_instance_valid(arena) and arena.has_method("walkable_area"): return arena.walkable_area()
	return 880.0*660.0

## Share of the walkable arena currently covered by a damaging hazard footprint.
func coverage_share() -> float:
	var total = 0.0
	for hazard in get_tree().get_nodes_in_group(StageHazard.GROUP):
		total += ArenaHazards.footprint_area(hazard.kind)
	return total/maxf(1.0,walkable_area())

func _tick_poison(delta: float) -> void:
	poison_clock -= delta
	if poison_clock > 0.0: return
	poison_clock += POISON_WINDOW
	var player = Utils.player
	if not is_instance_valid(player) or player.is_dead: return
	var best := 0.0
	var source = null
	var overlapping := 0
	for hazard in get_tree().get_nodes_in_group(StageHazard.GROUP):
		if hazard.kind != "poison" or not hazard.contains_player(): continue
		overlapping += 1
		if hazard.poison_share > best:
			best = hazard.poison_share
			var ref = hazard.owner_ref
			source = ref.get_ref() if ref else null
	if best <= 0.0: return
	# One tick per window for the whole arena, at the strongest single field's share.
	# Overlapping fields therefore cannot multiply the damage - they only widen the area.
	if overlapping > 1: StageHazard.audit_poison_capped += 1
	poison_ticks += 1
	StageHazard.audit_poison_ticks += 1
	player.on_percentage_hit(best,source,"hazard_poison")

func _spawn() -> void:
	if not is_instance_valid(arena): return
	var kinds: Array = plan.kinds
	if kinds.is_empty(): return
	var kind = "meteor" if "meteor" in kinds and meteor_wait >= 6.5 else kinds[rng.randi()%kinds.size()]
	audit_event("selected",kind)
	if kind == "meteor" and get_tree().get_nodes_in_group("boss_ultimate").any(func(u): return u.role=="B04"):
		audit_event("b04_suppressed",kind); spawn_clock = minf(spawn_clock,1.0); return
	if kind == "meteor" and get_tree().get_nodes_in_group(StageHazard.GROUP).filter(func(h): return h.kind=="meteor").size()>=3:
		audit_event("meteor_cap",kind); return
	var live = get_tree().get_nodes_in_group(StageHazard.GROUP).size()
	if live >= int(plan.live_cap):
		audit_event("live_cap",kind)
		StageHazard.audit_rejected += 1
		return
	# Coverage is a hard ceiling, checked before placement so a rejected hazard is never
	# drawn for a frame and then removed.
	var projected = coverage_share()+ArenaHazards.footprint_area(kind)/maxf(1.0,walkable_area())
	if projected > float(plan.coverage):
		audit_event("coverage_cap",kind)
		StageHazard.audit_rejected += 1
		return
	var spec = ArenaHazards.shape(kind)
	var extent = float(spec.max_extent)
	var point = _pick_visible_meteor(extent) if kind == "meteor" else _pick_point(extent)
	if point == Vector2.INF:
		audit_event("no_legal_visible_point",kind)
		if kind == "meteor": spawn_clock = minf(spawn_clock,1.0)
		StageHazard.audit_rejected += 1
		return
	var hazard = load("res://game/map/StageHazard.gd").new()
	hazard.kind = kind
	hazard.at = point
	hazard.director_ref = weakref(self)
	hazard.warning = float(plan.warning)
	hazard.active_time = float(plan.active)
	hazard.pulses = int(plan.pulses)
	hazard.poison_share = float(plan.poison_share)
	hazard.damage = float(plan.flat_damage)
	hazard.radius = float(spec.get("radius",70.0))
	hazard.length = float(spec.get("length",300.0))
	hazard.width = float(spec.get("width",30.0))
	# Line hazards are laid across the arena rather than aimed at the player's feet, so the
	# warning has to travel into view before it can connect. The `laser` sweeps (radians
	# per second), the `shock` band slides sideways (world px per second).
	if kind in ["laser","shock"]:
		hazard.direction = Vector2.RIGHT.rotated(rng.randf()*TAU)
		var sign = 1.0 if rng.randi()%2 == 0 else -1.0
		hazard.sweep = sign*(0.7 if kind == "laser" else 46.0)
	if kind == "meteor":
		hazard.warning = maxf(1.5,hazard.warning)
		hazard.active_time = 0.35
		hazard.pulses = 1
		hazard.damage = 2.0
	arena.add_child(hazard)
	if kind == "meteor":
		meteor_wait = 0.0; meteor_spawned += 1
	audit_event("spawned",kind,point)
	StageHazard.audit_spawned += 1

## Authored anchors first, then any legal walkable cell. Every candidate must be clear of
## the real collider set for this hazard's extent, keep its EDGE outside the player's
## personal space, and be reachable from the player.
func _pick_point(extent: float) -> Vector2:
	var anchors: Array = ArenaHazards.ANCHORS.get(plan.region,[])
	var order := []
	for i in anchors.size(): order.append(i)
	order.shuffle()
	var player_at = Utils.player.global_position if is_instance_valid(Utils.player) else Vector2.ZERO
	for index in order:
		var candidate = arena.to_global(anchors[index])
		if not _legal(candidate,extent,player_at,true): continue
		return candidate
	for attempt in 24:
		var candidate = arena.hazard_point(extent)
		if not _legal(candidate,extent,player_at,false): continue
		return candidate
	return Vector2.INF

func _legal(candidate: Vector2, extent: float, player_at: Vector2, authored: bool) -> bool:
	if not candidate.is_finite(): return false
	for ultimate in get_tree().get_nodes_in_group("boss_ultimate"):
		if ultimate.get_script()==load("res://game/monster/BossUltimate.gd") and ultimate.role=="B04":
			if candidate.distance_to(ultimate.safe_center)<ultimate.safe_radius+extent+90: return false
	if not arena.point_clear(candidate,extent*0.55+10.0):
		if authored: StageHazard.audit_skipped_anchor += 1
		return false
	# Hard rule: a damaging hazard may never appear under the player. The EDGE, not the
	# centre, must stay clear, so standing still can never be an instant hit.
	if candidate.distance_to(player_at) < ArenaHazards.MIN_EDGE_DISTANCE+extent:
		if authored: StageHazard.audit_skipped_anchor += 1
		return false
	if not arena.reachable_from_player(candidate):
		if authored: StageHazard.audit_skipped_anchor += 1
		return false
	return true

func audit_event(event: String, kind: String, point = Vector2.ZERO):
	if Demo.test_mode or Smoke.probe:
		print("B16_HAZARD ",JSON.stringify({"stage":stage,"seed":rng.seed,"time":round_time,"event":event,"kind":kind,"x":point.x,"y":point.y}))

func _pick_visible_meteor(extent: float) -> Vector2:
	if not is_instance_valid(Utils.player): return Vector2.INF
	var player_at = Utils.player.global_position
	var view = Utils.player.get_viewport()
	var screen = view.get_visible_rect().grow(-12.0)
	var transform = view.get_canvas_transform()
	var rotation_offset = rng.randf()*TAU
	var rejected = {"offscreen":0,"fog":0,"unsafe":0,"wall":0}
	var nearest = extent+ArenaHazards.MIN_EDGE_DISTANCE+8.0
	for distance in [nearest,nearest+16.0,nearest+32.0]:
		for i in 24:
			var candidate = player_at+Vector2.RIGHT.rotated(rotation_offset+i*TAU/24)*distance
			if not screen.has_point(transform*candidate): rejected.offscreen += 1; continue
			if candidate.distance_to(player_at)-extent > ArenaVisibility.fair_radius(): rejected.fog += 1; continue
			if not _legal(candidate,extent,player_at,false): rejected.unsafe += 1; continue
			if not Combat.clear_line(player_at,candidate): rejected.wall += 1; continue
			return candidate
	if Demo.test_mode or Smoke.probe: print("B16_PLACEMENT ",rejected," player_screen=",transform*player_at," screen=",screen)
	return Vector2.INF
