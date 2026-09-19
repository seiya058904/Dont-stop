extends Node2D
# One owner-bound ultimate at a time; the percentage payload is never flat damage.
var owner_ref: WeakRef
var role = "B01"
var direction = Vector2.RIGHT
var warning = 1.6
var fraction = 0.30
var radius = 160.0
var elapsed = 0.0
var epoch = 0
var hit_once = false
var lengths = [300.0,300.0,300.0,300.0]
var projectile_origin = Vector2.ZERO
var activated = false

## B04's moving safe zone. The Abyss Core's ultimate denies the whole arena except one
## marked circle that drifts, so the answer is movement rather than standing still, and the
## circle is anchored inside the player's own lit radius so Hell can never hide the answer.
var safe_center = Vector2.ZERO
var safe_drift = Vector2.RIGHT
var safe_radius = 74.0

## Fog fairness, identical contract to HostileZone: a percentage payload may not land before
## its own warning has been readable from inside the player's light for long enough.
var visible_warning := 0.0
const FAIR_VISIBLE := 0.5
const FAIR_MAX_EXTENSION := 1.4

func _ready():
	epoch = LevelServer.epoch
	add_to_group("combat_transient"); add_to_group("boss_ultimate")
	z_index = 2
	if role == "B02": fraction = 0.28; radius = 18.0
	elif role == "B03": fraction = 0.33; warning = 1.5
	elif role == "B04":
		fraction = 0.30; warning = 1.9; radius = 300.0; safe_radius = 74.0
		safe_center = Utils.player.global_position
		safe_drift = Vector2.RIGHT.rotated(randf()*TAU)*24.0
	for i in 4:
		var ray = direction.rotated(i*PI/2)
		var query = PhysicsRayQueryParameters2D.create(global_position,global_position+ray*300,2147483648)
		var collision = get_world_2d().direct_space_state.intersect_ray(query)
		if not collision.is_empty(): lengths[i] = global_position.distance_to(collision.position)
	projectile_origin = global_position
	var label = Label.new()
	label.text = {"B01":"重压震荡","B02":"母巢巨卵","B03":"棱镜坍缩","B04":"深渊吞噬"}.get(role,"终极")
	label.position = Vector2(-22,-28); label.add_theme_font_size_override("font_size",8); add_child(label)

func _physics_process(delta):
	var boss = owner_ref.get_ref() if owner_ref else null
	if not is_instance_valid(boss) or boss.is_die or epoch != LevelServer.epoch or LevelServer.state != "COMBAT": queue_free(); return
	elapsed += delta; queue_redraw()
	if elapsed < warning:
		if role == "B04": _drift_safe_zone(delta)
		if ArenaVisibility.fog_active() and _footprint_visible(): visible_warning += delta
		return
	if not activated:
		# The warning stretches rather than landing an unreadable percentage hit.
		if ArenaVisibility.fog_active() and visible_warning < FAIR_VISIBLE and elapsed < warning+FAIR_MAX_EXTENSION:
			return
		activated = true; boss.remember("ultimate_activated")
	var player = Utils.player
	var inside = global_position.distance_to(player.global_position)<=radius
	if role == "B02":
		var previous = global_position
		var next = previous+direction*75*delta
		# Sweep the visible radius against walls, not just its center ray.
		var shape = CircleShape2D.new(); shape.radius = radius
		var query = PhysicsShapeQueryParameters2D.new(); query.shape = shape; query.collision_mask = 2147483648
		query.transform = Transform2D(0,previous); query.motion = next-previous
		var safe = get_world_2d().direct_space_state.cast_motion(query)
		global_position = previous+(next-previous)*safe[0]
		inside = Geometry2D.get_closest_point_to_segment(player.global_position,previous,global_position).distance_to(player.global_position)<=radius+6
		if safe[0]<1: queue_free()
	elif role == "B03":
		inside = false
		for i in 4:
			var end = global_position+direction.rotated(i*PI/2)*lengths[i]
			if Geometry2D.get_closest_point_to_segment(player.global_position,global_position,end).distance_to(player.global_position)<=18: inside = true
	elif role == "B04":
		# Everything except the marked circle is lethal. Standing still is not an answer.
		inside = player.global_position.distance_to(safe_center) > safe_radius
	if not hit_once and inside and Combat.clear_line(global_position,player.global_position):
		hit_once = true
		player.on_percentage_hit(fraction,boss,"boss_percentage")
		if role == "B02" and not player.is_dead: player.apply_root()
		boss.remember("ultimate_hit")
	if elapsed>=warning+(4.0 if role == "B02" else 0.3): queue_free()

## The safe circle drifts, but never leaves the area the player can actually see: its centre
## is clamped to a fraction of the current fair radius. That is what keeps "where do I have
## to be" a readable question in the fog instead of a guess.
func _drift_safe_zone(delta: float) -> void:
	safe_center += safe_drift*delta
	var player = Utils.player
	if not is_instance_valid(player): return
	var limit = ArenaVisibility.fair_radius()*0.55
	var offset = safe_center-player.global_position
	if offset.length() > limit: safe_center = player.global_position+offset.normalized()*limit

func _footprint_visible() -> bool:
	var player = Utils.player
	if not is_instance_valid(player): return false
	var reach = ArenaVisibility.fair_radius()
	match role:
		"B03":
			for i in 4:
				var end = global_position+direction.rotated(i*PI/2)*lengths[i]
				if Geometry2D.get_closest_point_to_segment(player.global_position,global_position,end).distance_to(player.global_position) <= 18.0+reach: return true
			return false
		"B04":
			# Either the danger edge or the safe circle being in view is enough.
			if maxf(0.0,global_position.distance_to(player.global_position)-radius) <= reach: return true
			return maxf(0.0,safe_center.distance_to(player.global_position)-safe_radius) <= reach
	return maxf(0.0,global_position.distance_to(player.global_position)-radius) <= reach

func _draw():
	var active = activated
	var color = Color(1,0.36,0.64,0.8) if active else Color(1,0.73,0.25,0.9)
	if role=="B02": color=Color(0.85,0.45,1,1) if active else Color(0.65,0.8,1,1)
	if role=="B04": color=Color(0.72,0.38,1,0.95) if active else Color(0.86,0.62,1,0.95)
	if role == "B03":
		for i in 4:
			var end = direction.rotated(i*PI/2)*lengths[i]
			draw_line(Vector2.ZERO,end,Color(0.12,0.02,0.05,0.7),40)
			draw_line(Vector2.ZERO,end,Color(color,0.40 if active else 0.15),36)
			draw_line(Vector2.ZERO,end,color,3)
	elif role == "B04":
		_draw_abyss(color,active)
	elif role == "B02":
		if not active:
			draw_line(Vector2.ZERO,direction*lengths[0],Color(color,0.2),36)
			draw_line(Vector2.ZERO,direction*lengths[0],color,2)
		draw_circle(Vector2.ZERO,radius,Color(0.35,0.12,0.45,0.95))
		draw_arc(Vector2.ZERO,radius,0,TAU,32,color,3)
		draw_circle(Vector2(-5,-5),5,Color(1,0.8,0.9))
	else:
		draw_circle(Vector2.ZERO,radius,Color(color,0.15 if active else 0.06))
		draw_arc(Vector2.ZERO,radius,0,TAU,64,Color(0.1,0.03,0.02),5)
		draw_arc(Vector2.ZERO,radius,0,TAU,64,color,2)
		draw_arc(Vector2.ZERO,radius*clampf(elapsed/warning,0,1),0,TAU,64,color,2)

## The danger is drawn as the whole arena minus the safe circle, which is the only honest
## way to show "everywhere except there".
func _draw_abyss(color: Color, active: bool) -> void:
	var p = clampf(elapsed/warning,0,1)
	var local_safe = to_local(safe_center)
	draw_circle(Vector2.ZERO,radius,Color(0.16,0.04,0.30,0.16 if active else 0.05+0.10*p))
	for i in 3:
		draw_arc(Vector2.ZERO,radius*(0.45+i*0.28)+radius*0.12*sin(elapsed*3.0+i),0,TAU,64,Color(color.r,color.g,color.b,0.25+0.35*p),2,true)
	draw_arc(Vector2.ZERO,radius,0,TAU,64,Color(0.1,0.02,0.16),6)
	draw_arc(Vector2.ZERO,radius,0,TAU,64,color,3)
	# The safe circle: filled, ringed, and labelled by shape alone.
	draw_circle(local_safe,safe_radius,Color(0.25,0.95,0.7,0.20 if not active else 0.30))
	draw_arc(local_safe,safe_radius,0,TAU,40,Color(0.4,1,0.8,0.95),3,true)
	draw_arc(local_safe,safe_radius*clampf(p,0.12,1.0),0,TAU,40,Color(0.85,1,0.95,0.9),1.5,true)
	# Above the fog, so the answer is never hidden by the very thing this mode is about.
	preload("res://game/map/FogPierce.gd").push_circle(safe_center,safe_radius,Color(0.4,1,0.8,0.85),2.4)
