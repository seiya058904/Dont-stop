extends Node2D
class_name StageHazard

## One ground hazard in the arena. Owned and placed by ArenaHazardDirector; never by
## Town.gd directly.
##
## Contracts, all of them asserted by tests/B3Hazards.gd:
##  - epoch bound: a hazard dies the moment LevelServer.epoch advances, so returning to
##    camp or departing again can never leave a live hazard behind;
##  - stage bound: it belongs to the stage it was created for;
##  - a player-damaging hazard always warns first and can never be created under the
##    player (the director enforces the edge distance);
##  - in Hell, damage additionally requires that the footprint has been inside the
##    player's lit radius for long enough (the same fog fairness gate HostileZone uses);
##  - poison only ever ticks while the player is standing inside it, and overlapping
##    poison is capped by the director to a single tick per window, so piling zones up
##    cannot multiply the damage;
##  - leaving a poison field stops the damage on the next tick, immediately.

const GROUP := "stage_hazard"

var owner_ref: WeakRef
var director_ref: WeakRef
var epoch := -1
var stage := 0
var kind := "poison"
var at := Vector2.ZERO
var direction := Vector2.RIGHT
var sweep := 0.0
var radius := 96.0
var length := 340.0
var width := 22.0
var warning := 1.0
var active_time := 4.8
var rest := 0.5
var pulses := 1
var damage := 1.0
var poison_share := 0.015
var slick_seconds := 2.6

var phase := "warning"
var phase_time := 1.0
var elapsed := 0.0
var pulse := 0
var active_clock := 0.0
var hit_this_pulse := false
var visible_warning := 0.0
var offset := Vector2.ZERO
var initial_direction := Vector2.RIGHT
var slick_remaining := 0.0
var activated := false
## Wall-clipped reach for the line kinds. Identical rule to HostileZone: ask the physics world,
## never assume the nominal length is what the beam actually covers.
##
## B11.1: the answer is a pure function of (origin, direction, length) against STATIC level
## geometry, so it only has to be recomputed when one of those actually moves. `sweep == 0` means
## neither does - `_advance()` shifts `offset` only for a sweeping shock and turns `direction` only
## for a sweeping laser - so for a static band the same question was being asked and answered on
## every single physics tick. It is now asked once and re-used. This is the same defect HostileZone
## carried, in the sibling implementation, and it sits inside the same physics budget.
## `clip_origin` covers a hazard whose own `global_position` moves under it, so a moving band can
## never be left with a stale reach.
var clipped := 0.0
var clip_valid := false
var clip_origin := Vector2.INF

## Minimum seconds of visible warning before a Hell hazard may damage. Matches
## HostileZone's gate so the two systems cannot disagree about what is fair.
const FAIR_VISIBLE := 0.5
const FAIR_MAX_EXTENSION := 1.4

func _ready() -> void:
	epoch = LevelServer.epoch
	stage = LevelServer.level
	initial_direction = direction
	add_to_group(GROUP)
	add_to_group("combat_transient")
	# Below every telegraph and every actor: a ground hazard is terrain first.
	z_index = -2
	var spec = ArenaHazards.shape(kind)
	if kind in ["poison","vent","frost","meteor"]: radius = spec.radius
	elif kind == "laser": length = spec.length; width = spec.width
	elif kind == "shock": length = spec.length; width = spec.width
	if HellMode.is_hell(stage):
		warning = maxf(warning,ArenaHazards.WARNING_FLOOR)
	clipped = length
	phase = "warning"; phase_time = warning
	# `at` is a WORLD point. Hazard parents differ (the arena is at (10000+N*1000,-6000),
	# get_tree().current_scene is not), so assigning `position` here would have placed every
	# arena-owned hazard ~32000 px off the map. global_position is parent independent.
	global_position = at
	if kind == "meteor":
		var foreground = CanvasLayer.new()
		foreground.layer = 1
		foreground.follow_viewport_enabled = true
		add_child(foreground)
		var body = load("res://game/effects/MeteorBody.gd").new()
		body.hazard = weakref(self)
		foreground.add_child(body)

## Diagnostics for tests/B3Hazards.gd. Counters only, no behaviour change.
static var audit_spawned := 0
static var audit_rejected := 0
static var audit_skipped_anchor := 0
static var audit_peak_live := 0
static var audit_peak_coverage := 0.0
static var audit_poison_ticks := 0
static var audit_poison_capped := 0

func _physics_process(delta: float) -> void:
	if epoch != LevelServer.epoch or LevelServer.state != "COMBAT":
		if kind == "meteor": meteor_event("cancel_epoch_or_combat")
		queue_free(); return
	elapsed += delta
	phase_time -= delta
	if kind in ["laser","shock"]:
		var here := origin()
		if (sweep != 0.0 and phase != "active") or not clip_valid or here != clip_origin:
			clip_origin = here; clip_valid = true
			_clip()
	queue_redraw()
	match phase:
		"warning": _warning(delta)
		"active": _active(delta)
		"rest":
			if phase_time <= 0.0: _begin_pulse()

func _begin_pulse() -> void:
	if pulse >= pulses:
		queue_free(); return
	phase = "warning"; phase_time = warning
	activated = false; hit_this_pulse = false; visible_warning = 0.0

func _warning(delta: float) -> void:
	if _footprint_visible():
		visible_warning += delta
	if phase_time > 0.0: return
	if kind == "meteor" and ArenaVisibility.fog_active() and visible_warning < FAIR_VISIBLE:
		meteor_event("cancel_unseen")
		queue_free(); return
	# Fog fairness: never open the damaging phase before the warning has actually been
	# readable from inside the player's light, and never extend forever.
	if ArenaVisibility.fog_active() and visible_warning < FAIR_VISIBLE and elapsed < warning+FAIR_MAX_EXTENSION:
		phase_time = 0.05
		return
	phase = "active"; phase_time = active_time; active_clock = 0.0
	if kind == "meteor":
		meteor_event("impact")
		hit_this_pulse = true
		if _player_inside() and Combat.clear_line(origin(),Utils.player.global_position): Utils.player.onHit(damage,null,1.0,"hazard_meteor")
		Combat.sound(load("res://audio/bullet/EXPLDsgn_Explosion Impact_10.wav"),origin())
	if not activated:
		activated = true
		preload("res://game/effects/HostileVFX.gd").emit_at(get_tree().current_scene,global_position,radius if radius > 0.0 else width*2.0,direction,kind)

func _active(delta: float) -> void:
	_advance(delta)
	if kind in ["laser","shock"] and sweep != 0.0: _clip()
	active_clock -= delta
	if active_clock <= 0.0:
		active_clock += tick_interval()
		_apply(delta)
	if phase_time <= 0.0:
		pulse += 1
		if kind == "poison" and pulses <= 1:
			queue_free(); return
		phase = "rest"; phase_time = rest
		if pulse >= pulses: queue_free()

## The moving band for `shock`, the sweep for `laser`, and the slick countdown for
## `frost` all advance here so the damaging geometry and the drawn geometry cannot drift.
func _advance(delta: float) -> void:
	if kind == "shock" and sweep != 0.0:
		var step = sweep*delta
		offset += direction.orthogonal()*step
	if kind == "laser" and sweep != 0.0:
		direction = initial_direction.rotated(sweep*elapsed)
	if kind == "frost" and slick_remaining > 0.0:
		slick_remaining = maxf(0.0,slick_remaining-delta)

func tick_interval() -> float:
	match kind:
		"poison": return 0.5
		"laser","shock": return 0.35
		"frost": return 4.0
	return active_time+1.0

func origin() -> Vector2:
	return global_position+offset

## Wall-clipped damaging reach. Identical rule to HostileZone: ask the physics world, never
## assume the nominal length is what the beam actually covers.
func _clip() -> void:
	var space := get_world_2d().direct_space_state
	if space == null: clipped = length; return
	var query = PhysicsRayQueryParameters2D.create(origin(),origin()+direction*length,2147483648)
	var hit = space.intersect_ray(query)
	clipped = origin().distance_to(hit.position) if not hit.is_empty() else length

func _apply(_delta: float) -> void:
	var player = Utils.player
	if not is_instance_valid(player) or player.is_dead: return
	match kind:
		"poison":
			# Damage itself is ticked by the director so overlapping fields cannot stack.
			pass
		"vent":
			if hit_this_pulse: return
			if _player_inside():
				hit_this_pulse = true
				player.onHit(damage,owner_ref.get_ref() if owner_ref else null,1.0,"hazard_"+kind)
		"frost":
			if not _player_inside() and not _player_on_slick(): return
			if slick_remaining <= 0.0:
				slick_remaining = slick_seconds
				if _player_inside(): player.onHit(damage,owner_ref.get_ref() if owner_ref else null,1.0,"hazard_"+kind)
			# Bounded control effect, never a movement rewrite: at most a 20% slow, and
			# only while the player keeps standing on the slick.
			if _player_inside() or _player_on_slick(): player.apply_slow(0.2,0.6)
		"laser","shock":
			if Geometry2D.get_closest_point_to_segment(player.global_position,origin(),origin()+direction*clipped).distance_to(player.global_position) <= width+6.0:
				if Combat.clear_line(origin(),player.global_position):
					player.onHit(damage,owner_ref.get_ref() if owner_ref else null,1.0,"hazard_"+kind)

func _player_inside() -> bool:
	var player = Utils.player
	return is_instance_valid(player) and origin().distance_to(player.global_position) <= radius

func _player_on_slick() -> bool:
	var player = Utils.player
	if not is_instance_valid(player) or slick_remaining <= 0.0: return false
	return origin().distance_to(player.global_position) <= radius+14.0

func contains_player() -> bool:
	return kind == "poison" and phase == "active" and _player_inside()

## Shared with HostileZone: has any part of the damaging footprint been inside the
## player's lit radius yet? Normal mode reports a huge radius, so this is free outside
## Hell and the 1-30 behaviour is untouched.
func _footprint_visible() -> bool:
	var player = Utils.player
	if not is_instance_valid(player): return false
	var reach = ArenaVisibility.fair_radius()
	var here = origin()
	match kind:
		"laser","shock":
			return Geometry2D.get_closest_point_to_segment(player.global_position,here,here+direction*clipped).distance_to(player.global_position) <= width+reach
		"poison":
			return maxf(0.0,here.distance_to(player.global_position)-radius) <= reach
	return maxf(0.0,here.distance_to(player.global_position)-radius) <= reach

## Each hazard carries its own short description for the HUD and the audits.
func describe() -> String:
	return "%s@%s r=%.0f l=%.0f w=%.0f warn=%.2f pulses=%d" % [kind,str(at.round()),radius,length,width,warning,pulses]

func _draw() -> void:
	var t0 := 0
	if B11Probe.enabled:
		B11Probe.hazard_draws += 1
		t0 = Time.get_ticks_usec()
	var progress = clampf(1.0-phase_time/maxf(0.01,warning),0.0,1.0)
	var live = phase == "active"
	match kind:
		"meteor": _draw_meteor(live,progress)
		"poison": _draw_poison(live,progress)
		"vent": _draw_vent(live,progress)
		"frost": _draw_frost(live,progress)
		"laser": _draw_band("laser",live,progress)
		"shock": _draw_band("shock",live,progress)
	if B11Probe.enabled: B11Probe.hazard_draw_usec += Time.get_ticks_usec()-t0

func _draw_poison(live: bool, progress: float) -> void:
	var pulse = 0.5+0.5*sin(elapsed*3.4)
	var edge = Color(0.42,1,0.62,0.55+0.35*progress)
	var core = Color(0.10,0.42,0.24,0.30 if live else 0.12+0.12*progress)
	draw_circle(Vector2.ZERO,radius,core)
	draw_arc(Vector2.ZERO,radius,0,TAU,64,edge,2)
	# Unstable edge: two out-of-phase lobes read as "seeping", not as a UI circle.
	var wobble = PackedVector2Array()
	for i in 48:
		var a = TAU*i/48.0
		var r = radius*(1.0+0.05*sin(a*5.0+elapsed*2.2)+0.03*sin(a*9.0-elapsed*1.4))
		wobble.append(Vector2.RIGHT.rotated(a)*r)
	draw_polyline(wobble,Color(0.06,0.2,0.12,0.85),4,true)
	draw_polyline(wobble,edge,1.8,true)
	# Spore bubbles rise and pop on their own clocks so the field looks alive.
	for i in 9:
		var seed_angle = i*TAU/9.0+elapsed*0.55
		var distance = radius*(0.25+0.62*fposmod(i*0.37+elapsed*0.22,1.0))
		var point = Vector2.RIGHT.rotated(seed_angle)*distance
		draw_circle(point,2.0+2.6*fposmod(i*0.53+elapsed*0.9,1.0),Color(0.62,1,0.72,0.35+0.3*pulse))
	if not live:
		draw_arc(Vector2.ZERO,radius+6,-PI/2,-PI/2+TAU*progress,48,edge,2.5,true)
	else:
		draw_arc(Vector2.ZERO,radius+6,-PI/2,-PI/2+TAU*clampf(phase_time/maxf(0.01,active_time),0,1),48,Color(0.75,1,0.85,0.85),2,true)
	# Fog must not hide the edge of the field the player is standing next to.
	FogPierce.push_circle(global_position,radius,Color(0.42,1,0.62,0.5),2.0)

func _draw_vent(live: bool, progress: float) -> void:
	var hot = Color(1,0.55+0.3*progress,0.16,0.75)
	var inner = Color(1,0.30,0.05,0.14+0.28*progress)
	draw_circle(Vector2.ZERO,radius,inner)
	for i in 4:
		draw_arc(Vector2.ZERO,radius*(0.3+i*0.23),0,TAU,40,Color(hot.r,hot.g,hot.b,0.18+0.4*progress),2,true)
	# Ground cracks flare before the eruption, which is the readable "this will pop" cue.
	for i in 7:
		var a = i*TAU/7.0+0.4
		var reach = radius*(0.35+0.6*progress)
		draw_polyline(PackedVector2Array([Vector2.ZERO,Vector2.RIGHT.rotated(a)*reach,Vector2.RIGHT.rotated(a+0.16)*reach*1.05]),Color(1,0.72,0.28,0.35+0.5*progress),2,true)
	draw_arc(Vector2.ZERO,radius+4,-PI/2,-PI/2+TAU*progress,40,hot,2.5,true)
	if live:
		var burst = clampf(1.0-phase_time/maxf(0.01,active_time),0,1)
		draw_circle(Vector2.ZERO,radius*(0.35+0.75*burst),Color(1,0.85,0.45,0.45*(1.0-burst)))
		draw_arc(Vector2.ZERO,radius*(0.35+0.75*burst),0,TAU,40,Color(1,0.95,0.7,0.9*(1.0-burst)),3,true)

func _draw_frost(live: bool, progress: float) -> void:
	var edge = Color(0.66,0.95,1,0.6+0.35*progress)
	draw_circle(Vector2.ZERO,radius,Color(0.16,0.36,0.46,0.22 if live else 0.10+0.10*progress))
	for i in 10:
		var a = i*TAU/10.0+0.25
		var reach = radius*(0.4+0.55*progress)
		draw_line(Vector2.ZERO,Vector2.RIGHT.rotated(a)*reach,Color(0.85,0.98,1,0.30+0.45*progress),1.5,true)
	draw_polyline(PackedVector2Array([Vector2(radius,0),Vector2(0,radius),Vector2(-radius,0),Vector2(0,-radius),Vector2(radius,0)]),Color(0.08,0.14,0.2,0.8),4,true)
	draw_polyline(PackedVector2Array([Vector2(radius,0),Vector2(0,radius),Vector2(-radius,0),Vector2(0,-radius),Vector2(radius,0)]),edge,2,true)
	if slick_remaining > 0.0:
		draw_arc(Vector2.ZERO,radius+14,0,TAU,40,Color(0.7,0.95,1,0.55*clampf(slick_remaining/slick_seconds,0,1)),2,true)

func _draw_band(_style: String, live: bool, progress: float) -> void:
	draw_set_transform(offset)
	var laser = kind == "laser"
	var edge = Color(0.45,0.92,1,0.7) if laser else Color(0.72,0.5,1,0.7)
	var core = Color(0.25,0.85,1,0.30) if laser else Color(0.5,0.3,0.95,0.3)
	if not live:
		# Warning is a thin line, and the last quarter second brightens hard - the same
		# convention CombatTelegraph uses for a beam.
		var near = progress > 0.75
		var hot = Color(1,1,1,0.85) if near else edge
		draw_line(Vector2.ZERO,direction*clipped,Color(0.02,0.05,0.09,0.7),5,true)
		draw_line(Vector2.ZERO,direction*clipped,hot,1.4+(2.2 if near else 0.0),true)
		draw_arc(Vector2.ZERO,clipped*progress,direction.angle()-0.5,direction.angle()+0.5,24,edge,2,true)
		FogPierce.push_line(origin(),origin()+direction*clipped,edge,2.4)
		draw_set_transform(Vector2.ZERO)
		return
	var normal = direction.orthogonal()*width
	draw_colored_polygon(PackedVector2Array([-normal,direction*clipped-normal,direction*clipped+normal,normal]),core)
	draw_multiline(PackedVector2Array([-normal,direction*clipped-normal,normal,direction*clipped+normal]),Color(0.02,0.04,0.08,0.7),5,true)
	draw_line(Vector2.ZERO,direction*clipped,edge,3.2,true)
	draw_line(Vector2.ZERO,direction*clipped,Color(1,1,1,0.9),width*0.5,true)
	for i in int(clipped/34.0):
		var distance = fmod(i*34.0+elapsed*85.0,maxf(1,clipped))
		var point = direction*distance
		var side = direction.orthogonal()
		# Moving broken facets give the live beam a material distinct from its warning.
		for sign_value in [-1,1]:
			var facet=point+side*sign_value*width*0.65
			draw_line(facet,facet+direction*minf(11,clipped-distance),Color(edge,0.75),2)
		draw_line(point,point+direction*minf(7,clipped-distance),Color(1,1,1,0.8),2)
	draw_arc(Vector2.ZERO,9,0,TAU,12,edge,2)
	draw_circle(direction*clipped,4,Color(0.85,1,1,0.85))
	FogPierce.push_line(origin(),origin()+direction*clipped,edge,width*2)
	draw_set_transform(Vector2.ZERO)

func _draw_meteor(live: bool, progress: float):
	var red = Color(1,0.18,0.1,0.9)
	if not live:
		draw_circle(Vector2.ZERO,radius,Color(0.65,0.02,0.01,0.18))
		draw_arc(Vector2.ZERO,radius,0,TAU,48,Color(0.12,0.02,0.02),4)
		draw_arc(Vector2.ZERO,radius,0,TAU,48,red,2)
		draw_arc(Vector2.ZERO,radius+4,-PI/2,-PI/2+TAU*progress,48,Color(1,0.65,0.3),2)
		for side in [-1,1]: draw_line(Vector2(side*9,-9),Vector2(-side*9,9),red,2)
		draw_string(ThemeDB.fallback_font,Vector2(-9,22),"%.1fs"%maxf(0,phase_time),HORIZONTAL_ALIGNMENT_LEFT,-1,9,red)
		draw_circle(Vector2.ZERO,8+progress*9,Color(0.02,0.01,0.01,0.6))
		FogPierce.push_circle(origin(),radius,red,3)
	else:
		var fade = clampf(phase_time/active_time,0,1)
		draw_circle(Vector2.ZERO,radius*(1-fade*0.7),Color(1,0.3,0.06,fade*0.35))
		draw_arc(Vector2.ZERO,radius*(1-fade*0.5),0,TAU,40,Color(1,0.65,0.25,fade),3)

func meteor_event(event: String):
	if Demo.test_mode or Smoke.probe:
		print("B16_METEOR ",JSON.stringify({"event":event,"stage":stage,"elapsed":elapsed,"visible_warning":visible_warning,"phase":phase,"x":at.x,"y":at.y}))
