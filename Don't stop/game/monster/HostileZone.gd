extends Node2D
# One epoch-bound warning/attack; all essential geometry remains visible.
var mode = "circle"
var radius = 38.0
var length = 210.0
var width = 8.0
var direction = Vector2.RIGHT
var angle = 0.7
var warning = 0.8
var duration = 0.12
var tick = 0.2
var damage = 1.0
## Optional control payload in seconds, routed through Hero.apply_root() so the game keeps
## exactly ONE stun system: the root window, the 1.2 s immunity and the epoch reset are all
## unchanged, and the player can still aim, fire and reload while rooted.
var control = 0.0
var owner_ref: WeakRef
var epoch = -1
var elapsed = 0.0
var active_clock = 0.0
var hit_count = 0
var friendly_context: Dictionary = {}
var resolved = false
var sweep = 0.0
var initial_direction = Vector2.RIGHT
var maximum_length = 210.0
var activated = false
static var profile_stats = {"physics_calls":0,"physics_usec":0,"raycasts":0,"draw_calls":0,"draw_usec":0,"redraw_requests":0}
var profiling = false
var geometry_cache: Dictionary = {}
var visual_clock = 0.0
var ray_clock = 0.0
var previous_active = false
var last_ray_origin = Vector2.INF
## B11.2 repaint gate state: the detail budget this zone was last DRAWN with, and the origin it was
## last drawn at. Both are compared against the live values to decide whether a frozen footprint's
## ink could still differ from what is already on screen. No product behaviour reads either.
var previous_detail := true
var last_draw_origin := Vector2.INF
## `full_detail` decides whether the redundant origin halo is drawn. It used to be recomputed from
## `get_nodes_in_group("hostile_zone").size()` once per DRAWN ZONE per frame, which is a group scan of
## every live telegraph multiplied by the number of live telegraphs. It is a presentation budget, so
## it is now sampled once per zone every six frames from a static counter: the same decision, at a
## sixth of the cost, and still shared by every zone alive in that window.
static var budget_frame = -1
static var full_detail = true
static var budget_live := 0

## B11.1 test-only gauges (see game/diag/B11Probe.gd). `probe_firing` is this zone's own edge
## flag so the shared "how many lanes are actually firing right now" gauge is adjusted exactly
## once per zone, including when a zone is freed mid-window. No product behaviour reads it.
var probe_firing := false

## B批 attack-UI formalisation. `style` picks the palette family (see CombatTelegraph) and
## `pierce` mirrors long lanes onto FogPierce so a Hell beam's direction stays readable
## even where the lit radius ends. Neither touches collision, timing or damage.
var style := ""
var pierce := false

## The WARNING footprint is placed at a world point. Callers used to assign `position`, which
## is parent local: correct while every zone hung off get_tree().current_scene (identity
## transform), silently 10000s of pixels wrong the moment a zone is parented to the arena.
## Setting world_point instead makes placement parent independent.
var world_point := Vector2.INF

## Fog fairness. Only armed while Hell darkness is actually applied, so Stage 1-30 keeps
## its exact previous timing. `visible_warning` accumulates the seconds during which this
## footprint overlapped the player's lit radius; a damaging zone may not fire before that
## reaches FAIR_VISIBLE, and the wait is capped so nothing can be stalled forever.
var fair_gate := false
var visible_warning := 0.0
var active_elapsed := 0.0
const FAIR_VISIBLE := 0.5
const FAIR_WARNING := 0.6
const FAIR_MAX_EXTENSION := 1.4

## Above this many live telegraphs the redundant origin halo is dropped. Every footprint, contrast
## edge, timing ring, directional arrow and summon symbol stays.
const DETAIL_BUDGET := 32

static func profile_snapshot():
	return profile_stats.duplicate()
func _ready():
	# `--telegraph-profile` keeps its original meaning (the headless M8/M9/M10 perf tests). The
	# B11.1 stress driver arms the same per-instance timers, so a browser run reports the same
	# numbers those tests report instead of a second, differently shaped instrument.
	profiling = "--telegraph-profile" in OS.get_cmdline_user_args() or B11Probe.enabled
	if B11Probe.enabled: B11Probe.note_zone_added()
	epoch = LevelServer.epoch
	# Parent-independent placement: see world_point.
	if world_point.is_finite(): global_position = world_point
	initial_direction = direction
	maximum_length = length
	add_to_group("combat_transient")
	add_to_group("hostile_zone")
	z_index = -1
	if style == "": style = preload("res://game/effects/CombatTelegraph.gd").style_for(mode)
	fair_gate = ArenaVisibility.fog_active()
	# In Hell a damaging footprint always gets a real warning, even for a phase-II charge
	# that used to warn for only half a second.
	if fair_gate and damage > 0: warning = maxf(warning,FAIR_WARNING)

## B11.1: release this zone's gauge slots. Both counters are neighbours of a single edge, so a
## zone freed mid-window (epoch change, owner death, or its own end) cannot leave a lane counted
## as still firing. No product behaviour reads either of them.
func _exit_tree():
	if not B11Probe.enabled: return
	B11Probe.note_zone_removed()
	if probe_firing:
		probe_firing = false
		B11Probe.note_beam_active(false)

func _physics_process(delta):
	var started = Time.get_ticks_usec() if profiling else 0
	step(delta)
	if profiling:
		profile_stats.physics_calls += 1
		var cost = Time.get_ticks_usec()-started
		profile_stats.physics_usec += cost
		if B11Probe.enabled:
			B11Probe.zone_step_usec += cost
			if cost > B11Probe.zone_step_usec_worst: B11Probe.zone_step_usec_worst = cost
func step(delta):
	if epoch != LevelServer.epoch or LevelServer.state != "COMBAT": queue_free(); return
	if owner_ref and (not is_instance_valid(owner_ref.get_ref()) or owner_ref.get_ref().is_die): queue_free(); return
	elapsed += delta
	# `sweep_t` is hoisted out of the branch below because the repaint gate further down also needs
	# it: a lane that is still TURNING changes its ink every tick and must keep the full cadence.
	var sweep_t := 0.0
	if mode in ["line","charge"]:
		sweep_t = clampf((elapsed-warning)/maxf(duration,0.01),0,1)
		direction = initial_direction.rotated(sweep_t*sweep)
		ray_clock -= delta
		# The clip answer is a pure function of (origin, direction, maximum length) against STATIC
		# level geometry, so it only has to be recomputed when one of those actually moves. Before
		# the warning the direction cannot move (the sweep clamp is 0), and during the sweep it
		# moves every tick; the origin is covered by `last_ray_origin`, and `ray_clock` keeps the
		# 0.1 s safety refresh. The old condition ALSO treated `elapsed >= warning` as a reason by
		# itself - and that becomes true FOREVER at the instant a lane fires, so a lane that never
		# turns re-raycast the same frozen segment on every physics frame of its entire active
		# window for an answer that provably could not change. Full-rate clipping is retained where
		# it means something: the activation edge, a turning lane, and a moving origin.
		var turning := sweep != 0.0 and sweep_t > 0.0 and sweep_t < 1.0
		var activation_edge: bool = elapsed >= warning and elapsed-delta < warning
		if ray_clock <= 0 or turning or activation_edge or global_position != last_ray_origin:
			var query = PhysicsRayQueryParameters2D.create(global_position,global_position+direction*maximum_length,2147483648)
			var hit = get_world_2d().direct_space_state.intersect_ray(query)
			if profiling: profile_stats.raycasts += 1
			if B11Probe.enabled: B11Probe.raycasts += 1
			length = global_position.distance_to(hit.position) if not hit.is_empty() else maximum_length
			last_ray_origin = global_position; ray_clock = 0.1
		elif B11Probe.enabled and elapsed >= warning:
			B11Probe.raycasts_skipped += 1
	# The detail budget is a presentation decision shared by the repaint gate below and by the
	# painter, so it is resolved once here - same six-physics-frame cadence, same static counter it
	# has always used - instead of inside `_draw()`, which can no longer be reached every frame.
	var budget: int = Engine.get_physics_frames()/6
	if budget_frame != budget:
		budget_frame = budget
		budget_live = get_tree().get_nodes_in_group("hostile_zone").size()
	full_detail = budget_live <= DETAIL_BUDGET
	visual_clock -= delta
	var active: bool = activated
	var sweeping := sweep != 0.0 and sweep_t > 0.0 and sweep_t < 1.0
	# Only decorative warning motion is sampled at 30 Hz; the final 150 ms, activation edge and
	# damaging/sweeping geometry keep the physics cadence.
	#
	# B11.2: an ACTIVE footprint that is not turning has ink that is a pure function of frozen
	# inputs - `progress` is clamped to 1, `active` overwrites BOTH palette entries, the geometry
	# cache is keyed by values that cannot change, and the detail budget is compared right here - so
	# its draw commands are already on screen and re-running `_draw()` would reproduce them exactly.
	# The old condition kept repainting it at the PHYSICS cadence for its whole active window,
	# because `elapsed >= warning-0.15` becomes true FOREVER at the instant a zone fires: the same
	# "permanently true" defect the clipping above already avoids. A lane still turning, a footprint
	# whose origin moved, and a detail-budget flip all DO change the ink and keep the full cadence.
	# Everything else stops repainting until it changes or is freed, and because the ink is retained
	# the player still sees it.
	var frozen: bool = elapsed >= warning and active == previous_active and not sweeping and full_detail == previous_detail and global_position == last_draw_origin
	if not frozen and (visual_clock <= 0 or active != previous_active or elapsed >= warning-0.15):
		queue_redraw(); visual_clock = 1.0/30.0
		if profiling: profile_stats.redraw_requests += 1
	previous_active = active
	previous_detail = full_detail
	last_draw_origin = global_position
	# A lane that starts beyond the light still has to announce its direction. That is a per-tick
	# piece of INFORMATION, not ink, so it is emitted here on every physics tick instead of from
	# `_draw()`: keeping it in `_draw()` tied it to the repaint cadence, and a frozen lane's mirrored
	# direction would then vanish on every frame it did not repaint, because FogPierceCanvas clears
	# its entries each time it is drawn.
	if pierce and mode in ["line","charge"]:
		preload("res://game/map/FogPierce.gd").push_line(global_position,global_position+direction*length,Color(1,0.66,0.22,0.55 if not activated else 0.85),3.0 if activated else 2.0)
	if elapsed < warning:
		if fair_gate and damage > 0 and _footprint_visible(): visible_warning += delta
		return
	if not activated:
		# A footprint that has not been readable from inside the player's light for long
		# enough does not open: the warning stretches instead, bounded by FAIR_MAX_EXTENSION.
		if fair_gate and damage > 0 and visible_warning < FAIR_VISIBLE and elapsed < warning+FAIR_MAX_EXTENSION:
			return
		activated = true
		# The fairness gate, not the nominal timer, owns the visible firing edge.
		queue_redraw()
		# This queued draw already uses the activated palette. A frozen footprint
		# must not schedule the same activation edge again on the next physics tick.
		previous_active = true
		if profiling: profile_stats.redraw_requests += 1
		probe_firing = B11Probe.enabled
		if probe_firing: B11Probe.note_beam_active(true)
		preload("res://game/effects/HostileVFX.gd").emit_at(get_tree().current_scene,global_position,radius if mode == "circle" else 18,direction,style)
		if mode=="line" and length<maximum_length-0.5:
			preload("res://game/effects/HostileVFX.gd").emit_at(get_tree().current_scene,global_position+direction*length,9,-direction,style)
	active_elapsed += delta
	if not friendly_context.is_empty():
		if not resolved: resolved = true; Combat.explosion_context(global_position,radius,friendly_context)
	elif active_clock <= 0:
		active_clock += tick
		var target = Utils.player
		if is_instance_valid(target) and not target.is_dead:
			var offset = target.global_position-global_position
			var inside = offset.length() <= radius
			if mode in ["line","charge"]: inside = Geometry2D.get_closest_point_to_segment(target.global_position,global_position,global_position+direction*length).distance_to(target.global_position) <= width+6
			elif mode == "cone": inside = offset.length() <= radius and absf(direction.angle_to(offset)) <= angle
			if damage > 0 and inside and Combat.clear_line(global_position,target.global_position):
				target.onHit(damage,owner_ref.get_ref() if owner_ref else null,1.0,mode); hit_count += 1
				if B11Probe.enabled: B11Probe.zone_hits += 1
				# Applied after the damage so a root can never swallow the hit's feedback,
				# and apply_root() itself refuses while the player is immune or already rooted.
				if control > 0.0: target.apply_root(control)
	active_clock -= delta
	if active_elapsed >= duration: queue_free()

## Has any part of this footprint been inside the player's lit radius yet? Normal mode
## reports a huge radius, so this is a no-op outside Hell.
func _footprint_visible() -> bool:
	var target = Utils.player
	if not is_instance_valid(target): return false
	var reach = ArenaVisibility.fair_radius()
	var here = global_position
	match mode:
		"line","charge":
			return Geometry2D.get_closest_point_to_segment(target.global_position,here,here+direction*length).distance_to(target.global_position) <= width+reach
		"cone":
			return maxf(0.0,here.distance_to(target.global_position)-radius) <= reach
	return maxf(0.0,here.distance_to(target.global_position)-radius) <= reach
func _draw():
	var started = Time.get_ticks_usec() if profiling else 0
	# Ink only. The detail budget and the pierce fog mirror are per-physics-tick decisions and now
	# live in `step()`; with both gone from here, a frozen footprint can stop repainting without
	# losing either its presentation budget or its mirrored direction.
	preload("res://game/effects/CombatTelegraph.gd").paint(self,mode,direction,radius,length,width,angle,elapsed/maxf(0.01,warning),activated,sweep,geometry_cache,full_detail,style)
	if profiling:
		var draw_cost = Time.get_ticks_usec()-started
		profile_stats.draw_calls += 1
		profile_stats.draw_usec += draw_cost
		if B11Probe.enabled: B11Probe.zone_draw_usec += draw_cost
