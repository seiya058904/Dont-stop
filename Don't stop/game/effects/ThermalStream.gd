extends Node2D
var points := PackedVector2Array()
var clock := 0.0
var remaining := 0.16
var epoch := -1
func _ready():
	epoch = LevelServer.epoch
	add_to_group("combat_transient")
	z_index = 2
func refresh_cone(resolved: Array, _tint: Color):
	# Arena coordinates reach tens of thousands. Triangulate in muzzle-local space,
	# so tiny tongue areas do not lose precision through large absolute coordinates.
	global_position = resolved[0]
	points.clear()
	for p in resolved: points.append(p-global_position)
	if points.size()>1 and points[-1].is_equal_approx(points[0]): points.remove_at(points.size()-1)
	remaining = 0.16
func _process(delta):
	clock += delta
	remaining -= delta
	if remaining <= 0 or epoch != LevelServer.epoch: queue_free(); return
	queue_redraw()
func _draw():
	if points.size()<4: return
	var alpha = minf(1,remaining/0.06)*(0.65 if Combat.reduced_flash else 1.0)
	var muzzle = points[0]
	draw_colored_polygon(points,Color(0.7,0.13,0.025,alpha*0.35))
	# Each tongue stays inside the already wall-clipped radial footprint.
	for i in range(1,points.size()-1):
		var tip = points[i]
		var next = points[i+1]
		# A muzzle at a wall can collapse adjacent clipped rays to zero area.
		if absf((tip-muzzle).cross(next-muzzle))<0.01: continue
		var phase = fmod(clock*2.7+i*0.17,1.0)
		var reach = 0.65+phase*0.35
		var shape = PackedVector2Array([muzzle.lerp(tip,0.08),muzzle.lerp(tip,reach),muzzle.lerp(next,reach*0.85),muzzle.lerp(next,0.12)])
		draw_colored_polygon(shape,Color(1,0.28+phase*0.25,0.05,alpha*0.7))
		var ember = muzzle.lerp(tip,phase)
		draw_rect(Rect2(ember.round(),Vector2(2,2)),Color(1,0.85,0.3,alpha*(1-phase)))
		if i%3==0:
			draw_line(muzzle.lerp(tip,0.05),muzzle.lerp(tip,0.38+sin(clock*18+i)*0.06),Color(1,0.92,0.5,alpha),2)
	draw_circle(muzzle,3,Color(1,0.94,0.7,alpha))
