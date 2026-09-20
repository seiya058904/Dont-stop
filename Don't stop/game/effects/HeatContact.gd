extends Node2D
var age := 0.0
var epoch := -1
func _ready():
	epoch = LevelServer.epoch
	add_to_group("combat_transient")
	z_index = 4
func _process(delta):
	age += delta
	if age>0.22 or epoch!=LevelServer.epoch: queue_free(); return
	queue_redraw()
func _draw():
	var a = (1-age/0.22)*(0.5 if Combat.reduced_flash else 1.0)
	draw_rect(Rect2(-3,-4,6,7),Color(1,0.25,0.04,a*0.6))
	for i in 4:
		var p = Vector2.RIGHT.rotated(i*1.8)*(3+age*24)
		draw_rect(Rect2(p.round(),Vector2(2,2)),Color(1,0.75,0.2,a))
