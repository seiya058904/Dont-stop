extends Node2D
var caption: Label
func _ready():
	z_index=80
	caption=Label.new(); caption.position=Vector2(-18,-34); caption.add_theme_font_size_override("font_size",8)
	caption.add_theme_color_override("font_shadow_color",Color.BLACK); caption.add_theme_constant_override("shadow_offset_x",1); caption.add_theme_constant_override("shadow_offset_y",1); add_child(caption)
func _process(_delta):
	var player=get_parent()
	visible=player.root_remaining>0 or player.cc_immunity>0
	caption.text="束缚 %.1fs" % player.root_remaining if player.root_remaining>0 else "束缚免疫"
	queue_redraw()
func _draw():
	var root=get_parent().root_remaining>0
	var color=Color(0.95,0.55,1) if root else Color(0.25,1,0.7)
	draw_arc(Vector2(0,5),24,0,TAU,36,color,3)
	if root:
		for i in 4:
			var p=Vector2(22,0).rotated(i*PI/2)
			draw_rect(Rect2(p-Vector2(3,3),Vector2(6,6)),color)
		for x in [-10,10]: draw_line(Vector2(x,-15),Vector2(-x,21),Color(color,0.85),2)
