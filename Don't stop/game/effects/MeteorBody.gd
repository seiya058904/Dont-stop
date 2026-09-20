extends Node2D
# Foreground body uses the hazard's locked world point and real countdown.
var hazard: WeakRef
var announced := false
func _process(_delta):
	var source = hazard.get_ref()
	if not is_instance_valid(source) or source.is_queued_for_deletion(): hide(); return
	visible = source.phase == "warning"
	global_position = source.origin()
	if visible and not announced:
		announced = true
		source.meteor_event("descent")
	queue_redraw()
func _draw():
	var source = hazard.get_ref()
	if not is_instance_valid(source) or not visible: return
	var progress = clampf(1.0-source.phase_time/source.warning,0,1)
	var height = 180*pow(1-progress,0.7)
	var p = Vector2(-height*0.18,-height)
	# Projection and broken tail facets share the hazard's actual descent clock.
	draw_set_transform(Vector2.ZERO,0,Vector2(1,0.4))
	draw_circle(Vector2.ZERO,10+progress*4,Color(0.08,0.03,0.02,0.35))
	draw_set_transform(Vector2.ZERO)
	for i in 5:
		var trail=p+Vector2(-5-i*2,-13-i*5)
		draw_rect(Rect2(trail,Vector2(5-i*0.6,7)),Color(1,0.35+i*0.09,0.08,0.45-i*0.07))
	draw_colored_polygon(PackedVector2Array([p+Vector2(-7,-7),p+Vector2(-14,-32),p+Vector2(9,-10),p+Vector2(10,7)]),Color(1,0.3,0.05,0.8))
	draw_colored_polygon(PackedVector2Array([p+Vector2(-10,-7),p+Vector2(3,-12),p+Vector2(12,1),p+Vector2(4,11),p+Vector2(-9,7)]),Color(0.4,0.26,0.2))
	draw_colored_polygon(PackedVector2Array([p+Vector2(-10,-7),p+Vector2(3,-12),p+Vector2(1,-1),p+Vector2(-8,3)]),Color(0.65,0.43,0.29))
	draw_colored_polygon(PackedVector2Array([p+Vector2(2,0),p+Vector2(12,1),p+Vector2(4,11),p+Vector2(-2,7)]),Color(0.23,0.14,0.12))
	draw_polyline(PackedVector2Array([p+Vector2(-7,5),p+Vector2(-2,0),p+Vector2(1,-6)]),Color(1,0.4,0.1),1)
	draw_line(p+Vector2(-5,-4),p+Vector2(7,3),Color(1,0.6,0.2),3)
	draw_line(Vector2(0,-16),Vector2(0,-5),Color(1,0.65,0.25),2)
	draw_polyline(PackedVector2Array([Vector2(-4,-9),Vector2(0,-5),Vector2(4,-9)]),Color(1,0.65,0.25),2)
