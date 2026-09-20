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
	draw_colored_polygon(PackedVector2Array([p+Vector2(-7,-7),p+Vector2(-14,-32),p+Vector2(9,-10),p+Vector2(10,7)]),Color(1,0.3,0.05,0.8))
	draw_colored_polygon(PackedVector2Array([p+Vector2(-10,-7),p+Vector2(3,-12),p+Vector2(12,1),p+Vector2(4,11),p+Vector2(-9,7)]),Color(0.4,0.26,0.2))
	draw_line(p+Vector2(-5,-4),p+Vector2(7,3),Color(1,0.6,0.2),3)
	draw_line(Vector2(0,-16),Vector2(0,-5),Color(1,0.65,0.25),2)
	draw_polyline(PackedVector2Array([Vector2(-4,-9),Vector2(0,-5),Vector2(4,-9)]),Color(1,0.65,0.25),2)
