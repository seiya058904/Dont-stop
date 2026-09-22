extends Label
var elapsed = 0.0
func _ready():
	position = Vector2(8,174)
	size = Vector2(345,30)
	autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	add_theme_font_override("font",load("res://fonts/fusion-pixel.otf"))
	add_theme_font_size_override("font_size",6)
	add_theme_color_override("font_shadow_color",Color.BLACK)
	add_theme_constant_override("shadow_offset_x",1)
	add_theme_constant_override("shadow_offset_y",1)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	Demo.changed.connect(refresh)

func refresh():
	update_text()

func _process(delta):
	elapsed += delta
	if elapsed < 0.2: return
	elapsed = 0
	update_text()

func update_text():
	text=preload("res://game/config/CombatStatus.gd").display()
