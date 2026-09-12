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
func _ready():
	epoch = LevelServer.epoch
	initial_direction = direction
	maximum_length = length
	add_to_group("combat_transient")
	add_to_group("hostile_zone")
	z_index = 7
func _physics_process(delta):
	if epoch != LevelServer.epoch or LevelServer.state != "COMBAT": queue_free(); return
	if owner_ref and (not is_instance_valid(owner_ref.get_ref()) or owner_ref.get_ref().is_die): queue_free(); return
	elapsed += delta
	if mode == "line":
		direction = initial_direction.rotated(clampf((elapsed-warning)/maxf(duration,0.01),0,1)*sweep)
		var query = PhysicsRayQueryParameters2D.create(global_position,global_position+direction*maximum_length,2147483648)
		var hit = get_world_2d().direct_space_state.intersect_ray(query)
		length = global_position.distance_to(hit.position) if not hit.is_empty() else maximum_length
	queue_redraw()
	if elapsed < warning: return
	if not friendly_context.is_empty():
		if not resolved: resolved = true; Combat.explosion_context(global_position,radius,friendly_context)
	elif active_clock <= 0:
		active_clock += tick
		var target = Utils.player
		if is_instance_valid(target) and not target.is_dead:
			var offset = target.global_position-global_position
			var inside = offset.length() <= radius
			if mode == "line": inside = Geometry2D.get_closest_point_to_segment(target.global_position,global_position,global_position+direction*length).distance_to(target.global_position) <= width+6
			elif mode == "cone": inside = offset.length() <= radius and absf(direction.angle_to(offset)) <= angle
			if damage > 0 and inside and Combat.clear_line(global_position,target.global_position): target.onHit(damage,owner_ref.get_ref() if owner_ref else null); hit_count += 1
	active_clock -= delta
	if elapsed >= warning+duration: queue_free()
func _draw():
	var color = Color(1,0.57,0.13,0.85) if elapsed < warning else Color(1,0.16,0.12,0.95)
	if not friendly_context.is_empty(): color = Color(0.3,0.9,1,0.8)
	if mode == "line":
		if elapsed < warning and sweep != 0: draw_line(Vector2.ZERO,initial_direction.rotated(sweep)*length,Color(1,0.7,0.2,0.55),1)
		draw_line(Vector2.ZERO,direction*length,Color(0.12,0.05,0.03),width*2+3)
		draw_line(Vector2.ZERO,direction*length,color,2.0 if elapsed < warning else width*2)
	elif mode == "cone":
		var points = PackedVector2Array([Vector2.ZERO])
		for i in 17: points.append(direction.rotated(lerpf(-angle,angle,i/16.0))*radius)
		points.append(Vector2.ZERO); draw_polyline(points,Color(0.1,0.04,0.02),4); draw_polyline(points,color,2)
	else:
		draw_arc(Vector2.ZERO,radius,0,TAU,40,Color(0.1,0.04,0.02),4)
		draw_arc(Vector2.ZERO,radius,0,TAU,40,color,2)
		draw_circle(Vector2.ZERO,3,color)
