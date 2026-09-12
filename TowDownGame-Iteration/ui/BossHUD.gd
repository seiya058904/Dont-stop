extends Control
var title: Label
var phases: Label
var ratio = 1.0
var second = false
var style: StyleBoxFlat
func _ready():
	position = Vector2(120,8); size = Vector2(180,29); mouse_filter = Control.MOUSE_FILTER_IGNORE
	style = StyleBoxFlat.new(); style.bg_color = Color(0.05,0.06,0.08,0.82); style.set_corner_radius_all(3)
	title = Label.new(); title.add_theme_font_size_override("font_size",8); add_child(title)
	phases = Label.new(); phases.position.y = 20; phases.add_theme_font_size_override("font_size",6); add_child(phases)
func _process(_delta):
	var boss = instance_from_id(LevelServer.boss_instance)
	visible = LevelServer.state == "COMBAT" and is_instance_valid(boss) and not boss.is_die
	if not visible: return
	ratio = maxf(0,boss.HP/boss.max_hp); second = boss.phase_two
	title.text = M5Content.definition(boss.role).name
	phases.text = "PHASE I          |          PHASE II" + ("  ◀" if second else "")
	phases.modulate = Color(1,0.62,0.25) if second else Color(0.95,0.86,0.68)
	queue_redraw()
func _draw():
	draw_style_box(style,Rect2(-5,-3,190,34))
	draw_rect(Rect2(0,13,180,5),Color(0.13,0.07,0.06))
	draw_rect(Rect2(0,13,180*ratio,5),Color(1,0.39,0.12) if second else Color(0.98,0.69,0.24))
	draw_line(Vector2(90,12),Vector2(90,19),Color(0.1,0.06,0.04),2)
