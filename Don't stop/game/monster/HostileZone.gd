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
static var budget_frame = -1
static var full_detail = true

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

static func profile_snapshot():
	return profile_stats.duplicate()
func _ready():
	profiling = "--telegraph-profile" in OS.get_cmdline_user_args()
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
func _physics_process(delta):
	var started = Time.get_ticks_usec() if profiling else 0
	step(delta)
	if profiling:
		profile_stats.physics_calls += 1
		profile_stats.physics_usec += Time.get_ticks_usec()-started
func step(delta):
	if epoch != LevelServer.epoch or LevelServer.state != "COMBAT": queue_free(); return
	if owner_ref and (not is_instance_valid(owner_ref.get_ref()) or owner_ref.get_ref().is_die): queue_free(); return
	elapsed += delta
	if mode in ["line","charge"]:
		direction = initial_direction.rotated(clampf((elapsed-warning)/maxf(duration,0.01),0,1)*sweep)
		ray_clock -= delta
		# The warning is locked. Refresh moving origins immediately and retain full-rate
		# collision clipping on activation / throughout the actual attack and sweep.
		if ray_clock <= 0 or elapsed >= warning or global_position != last_ray_origin:
			var query = PhysicsRayQueryParameters2D.create(global_position,global_position+direction*maximum_length,2147483648)
			var hit = get_world_2d().direct_space_state.intersect_ray(query)
			if profiling: profile_stats.raycasts += 1
			length = global_position.distance_to(hit.position) if not hit.is_empty() else maximum_length
			last_ray_origin = global_position; ray_clock = 0.1
	visual_clock -= delta
	var active = elapsed >= warning
	# Only decorative warning motion is sampled at 30 Hz; the final 150 ms,
	# activation edge and damaging/sweeping geometry keep the physics cadence.
	if visual_clock <= 0 or active != previous_active or elapsed >= warning-0.15:
		queue_redraw(); visual_clock = 1.0/30.0
		if profiling: profile_stats.redraw_requests += 1
	previous_active = active
	if elapsed < warning:
		if fair_gate and damage > 0 and _footprint_visible(): visible_warning += delta
		return
	if not activated:
		# A footprint that has not been readable from inside the player's light for long
		# enough does not open: the warning stretches instead, bounded by FAIR_MAX_EXTENSION.
		if fair_gate and damage > 0 and visible_warning < FAIR_VISIBLE and elapsed < warning+FAIR_MAX_EXTENSION:
			return
		activated = true
		preload("res://game/effects/HostileVFX.gd").emit_at(get_tree().current_scene,global_position,radius if mode == "circle" else 18,direction)
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
				target.onHit(damage,owner_ref.get_ref() if owner_ref else null); hit_count += 1
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
	var frame = Engine.get_physics_frames()/6
	if budget_frame != frame:
		budget_frame = frame
		full_detail = get_tree().get_nodes_in_group("hostile_zone").size() <= 32
	# Under load omit only the redundant origin halo. Footprints, contrast edges,
	# timing rings, directional arrows and the summon symbol always remain.
	preload("res://game/effects/CombatTelegraph.gd").paint(self,mode,direction,radius,length,width,angle,elapsed/maxf(0.01,warning),elapsed>=warning,sweep,geometry_cache,full_detail,style)
	# A lane that starts beyond the light still has to announce its direction.
	if pierce and mode in ["line","charge"]:
		preload("res://game/map/FogPierce.gd").push_line(global_position,global_position+direction*length,Color(1,0.66,0.22,0.55 if not activated else 0.85),3.0 if activated else 2.0)
	if profiling:
		profile_stats.draw_calls += 1
		profile_stats.draw_usec += Time.get_ticks_usec()-started
