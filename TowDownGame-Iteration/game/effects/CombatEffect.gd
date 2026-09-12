extends Node2D
var radius = 0.0
var points: Array[Vector2] = []
var life = 0.0
var color = Color(0.4,0.85,1)
var width = 2.0
func _ready():
	add_to_group("combat_transient")
	z_index = 3
func _process(delta):
	life += delta
	if life > 0.24: queue_free()
	queue_redraw()
func _draw():
	var opacity = clampf(1.0-life/0.24,0,1)
	if radius > 0:
		draw_arc(Vector2.ZERO,radius*minf(1,life/0.08),0,TAU,32,Color(0.3,1.0,0.8,opacity),2)
		if life < 0.06 and not Combat.reduced_flash: draw_circle(Vector2.ZERO,radius*0.3,Color(1,0.9,0.5,opacity*0.5))
	else:
		for i in range(1,points.size()):
			var a = points[i-1]
			var b = points[i]
			var middle = (a+b)*0.5 + (b-a).orthogonal().normalized()*4
			draw_polyline(PackedVector2Array([a,middle,b]),Color(color,opacity),width)
			draw_circle(b,3,Color(1,1,0.7,opacity))
