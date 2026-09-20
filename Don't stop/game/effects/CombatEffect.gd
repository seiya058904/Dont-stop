extends Node2D
var radius = 0.0
var points: Array[Vector2] = []
var life = 0.0
var color = Color(0.4,0.85,1)
var width = 2.0
var footprint = PackedVector2Array()
var footprint_edge = PackedVector2Array()
var trace_polygon = PackedVector2Array()
var closed_trace := false
var epoch := -1
var detail_slot := false
static var detail_slots := 0
const DETAIL_LIMIT := 64 # + existing hostile burst cap 32 = 96 optional burst slots.
func _ready():
	add_to_group("combat_transient")
	z_index = 3
	epoch = LevelServer.epoch
	detail_slot = detail_slots < DETAIL_LIMIT
	if detail_slot: detail_slots += 1
	cache_geometry()
func _exit_tree():
	if detail_slot: detail_slots -= 1
func cache_geometry():
	footprint_edge = footprint.duplicate()
	if not footprint_edge.is_empty(): footprint_edge.append(footprint_edge[0])
	closed_trace = points.size() > 2 and points[0].is_equal_approx(points[-1])
	trace_polygon = PackedVector2Array(points) if closed_trace else PackedVector2Array()
func refresh_cone(resolved_points: Array, tint: Color):
	points.assign(resolved_points)
	color = tint
	width = 1.0
	life = 0.0
	cache_geometry()
	queue_redraw()
func _process(delta):
	if epoch != LevelServer.epoch: queue_free(); return
	life += delta
	if life > 0.24: queue_free()
	queue_redraw()
func _draw():
	var opacity = clampf(1.0-life/0.24,0,1)
	if radius > 0:
		var expansion = clampf(life/0.14,0,1)
		if not footprint.is_empty():
			var wave = PackedVector2Array()
			for p in footprint: wave.append(p*expansion)
			draw_colored_polygon(wave,Color(0.35,0.85,0.65,opacity*0.32))
			draw_circle(Vector2.ZERO,radius*0.2*opacity,Color(0.9,1,0.65,opacity*(0.3 if Combat.reduced_flash else 0.7)))
			for i in 8:
				var p = footprint[(i*footprint.size())/8]*expansion
				draw_rect(Rect2(p.round(),Vector2(3,2)),Color(0.8,1,0.6,opacity))
		if not footprint.is_empty():
			draw_colored_polygon(footprint,Color(0.3,1.0,0.8,opacity*0.12))
			draw_polyline(footprint_edge,Color(0.3,1.0,0.8,opacity),2)
		else: draw_arc(Vector2.ZERO,radius,0,TAU,32,Color(0.3,1.0,0.8,opacity),2)
		if life < 0.06 and not Combat.reduced_flash: draw_circle(Vector2.ZERO,radius*0.3,Color(1,0.9,0.5,opacity*0.5))
	else:
		# The essential resolved outline is never subject to the decoration budget.
		if closed_trace and detail_slot:
			draw_colored_polygon(trace_polygon,Color(color,opacity*(0.025 if Combat.reduced_flash else 0.055)))
		for i in range(1,points.size()):
			var a = points[i-1]
			var b = points[i]
			draw_line(a,b,Color(color,opacity),width)
			if i == points.size()-1 and not closed_trace:
				draw_circle(b,2,Color(1,1,0.7,opacity))
				if detail_slot:
					# Two bounded contact points, using only the already resolved endpoint.
					var normal = (b-a).normalized().orthogonal()*2
					draw_line(b-normal,b+normal,Color(color,opacity*0.65),1)
