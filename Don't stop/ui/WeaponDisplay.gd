extends Control
## An optical inspection cradle behind the real, unmodified weapon sprite.
var tint := Color("dfbf82")
var tier := 1
var clock := 0.0
var tick := 0.0

func _ready():
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	show_behind_parent = true

func _process(delta):
	if not is_visible_in_tree(): return
	clock += delta
	tick += delta
	if tick < 0.033: return
	tick = 0.0
	queue_redraw()

func _draw():
	var center := size*0.5
	draw_style_box(preload("res://ui/GildedTheme.gd").plate(Color("0a131b"),Color("344750"),0),Rect2(Vector2.ZERO,size))
	# Elliptical reflected light sits under, never over, the pixel art.
	for i in range(5,0,-1):
		draw_set_transform(center+Vector2(0,4),0,Vector2(2.1,0.6))
		draw_circle(Vector2.ZERO,3.0+i*2.0,Color(tint,0.024))
	draw_set_transform(Vector2.ZERO)
	draw_line(Vector2(7,size.y-5),Vector2(size.x-7,size.y-5),Color(tint,0.45),1)
	for x in [5.0,size.x-5.0]:
		for y in [5.0,size.y-5.0]:
			var direction := 1.0 if x < center.x else -1.0
			draw_line(Vector2(x,y),Vector2(x+direction*5,y),Color(tint,0.7),1)
	for i in tier:
		var x := center.x+(i-(tier-1)*0.5)*4
		draw_rect(Rect2(x,4,2,1),Color(tint,0.9))
	if tier >= 4:
		var strength := 0.35 if Combat.reduced_flash else 0.5
		for side in [-1,1]:
			var p := center+Vector2(side*(size.x*0.5-9),sin(clock*1.8)*5)
			draw_line(p-Vector2(0,3),p+Vector2(0,3),Color(tint,strength),1)
