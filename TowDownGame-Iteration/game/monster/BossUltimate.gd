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
func _ready():
	epoch = LevelServer.epoch
	add_to_group("combat_transient"); add_to_group("boss_ultimate")
	z_index = 2
	if role == "B02": fraction = 0.28; radius = 18.0
	elif role == "B03": fraction = 0.33; warning = 1.5
	for i in 4:
		var ray = direction.rotated(i*PI/2)
		var query = PhysicsRayQueryParameters2D.create(global_position,global_position+ray*300,2147483648)
		var collision = get_world_2d().direct_space_state.intersect_ray(query)
		if not collision.is_empty(): lengths[i] = global_position.distance_to(collision.position)
	projectile_origin = global_position
	var label = Label.new(); label.text = {"B01":"重压震荡","B02":"母巢巨卵","B03":"棱镜坍缩"}[role]
	label.position = Vector2(-22,-28); label.add_theme_font_size_override("font_size",8); add_child(label)
func _physics_process(delta):
	var boss = owner_ref.get_ref() if owner_ref else null
	if not is_instance_valid(boss) or boss.is_die or epoch != LevelServer.epoch or LevelServer.state != "COMBAT": queue_free(); return
	elapsed += delta; queue_redraw()
	if elapsed < warning: return
	if not activated:
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
	if not hit_once and inside and Combat.clear_line(global_position,player.global_position):
		hit_once = true
		player.on_percentage_hit(fraction,boss)
		if role == "B02" and not player.is_dead: player.apply_root()
		boss.remember("ultimate_hit")
	if elapsed>=warning+(4.0 if role == "B02" else 0.3): queue_free()
func _draw():
	var active = elapsed>=warning
	var color = Color(1,0.36,0.64,0.8) if active else Color(1,0.73,0.25,0.9)
	if role == "B03":
		for i in 4:
			var end = direction.rotated(i*PI/2)*lengths[i]
			draw_line(Vector2.ZERO,end,Color(0.12,0.02,0.05,0.7),40)
			draw_line(Vector2.ZERO,end,Color(color,0.40 if active else 0.15),36)
			draw_line(Vector2.ZERO,end,color,3)
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
