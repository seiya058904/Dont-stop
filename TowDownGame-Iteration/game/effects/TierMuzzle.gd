extends Node2D
var tier = 1
var remaining = 0.0
func _ready():
	z_index = 2
	set_process(false)
func pulse(level: int):
	tier = level
	remaining = 0.07
	visible = true
	set_process(true)
	queue_redraw()
func stop():
	remaining = 0
	visible = false
	set_process(false)
func _process(delta):
	remaining -= delta
	if remaining <= 0: stop()
	else: queue_redraw()
func _draw():
	var alpha = minf(0.8,remaining/0.07)* (0.35 if Combat.reduced_flash else 1.0)
	var color = [Color("deb984"),Color("f4d17c"),Color("7cdbdd"),Color("83b8ff"),Color("d9a2ff")][tier-1]
	color.a = alpha
	var length = 4+tier*2
	draw_line(Vector2.ZERO,Vector2(length,0),color,1.0+tier*0.35)
	if tier >= 3:
		for side in [-1,1]: draw_line(Vector2(2,side*2),Vector2(length*0.7,side*4),color,1)
	if tier == 5: draw_arc(Vector2(4,0),5,-0.8,0.8,8,color,1.4)
