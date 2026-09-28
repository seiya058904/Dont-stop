extends Control
var title: Label
var phases: Label
var ratio = 1.0
var second = false
var third = false
var style: StyleBoxFlat
var badge: Label
const PHASE_TWO_AT := 0.70
const PHASE_THREE_AT := 0.35
func _ready():
	position = Vector2(111,8); size = Vector2(180,35); mouse_filter = Control.MOUSE_FILTER_IGNORE
	style = preload("res://ui/GildedTheme.gd").plate(Color("111821f2"),Color("907652"),3)
	title = Label.new(); title.add_theme_font_size_override("font_size",8); add_child(title)
	title.add_theme_font_override("font",preload("res://fonts/fusion-pixel.otf"))
	title.add_theme_color_override("font_color",Color("f1d8aa"))
	title.size = Vector2(165,12)
	title.clip_text = true
	phases = Label.new(); phases.position.y = 20; phases.add_theme_font_size_override("font_size",6); add_child(phases)
	# HELL badge: the round's difficulty layer has to be visible for the whole fight, not
	# only on the stage-select screen.
	badge = Label.new(); badge.position = Vector2(168,2); badge.add_theme_font_size_override("font_size",5)
	badge.text = "HELL"; badge.modulate = Color(0.86,0.55,1); add_child(badge)
func _process(_delta):
	var boss = LevelServer.get_boss()
	visible = LevelServer.state == "COMBAT" and is_instance_valid(boss) and not boss.is_die
	if not visible: return
	# The existing reward grid can now wrap to two rows. Keep both HUDs readable.
	position.y = 8
	badge.visible = HellMode.is_hell(LevelServer.level)
	var rewards = Utils.canvasLayer.get_node_or_null("GameUI/RwGridContainer")
	if rewards and rewards.get_child_count()>0 and rewards.get_global_rect().intersects(Rect2(position,Vector2(218,35))):
		position.y = rewards.get_global_rect().end.y+4
	ratio = maxf(0,boss.HP/boss.max_hp)
	second = boss.phase_two
	third = boss.phase_three
	title.text = M5Content.definition(boss.role).name + ("  ·  第%d关" % LevelServer.level)
	# Three explicit phases with the active one marked, so the switch at 70% and 35% is a
	# readout the player can plan against instead of a surprise.
	var marker = "  ◀"
	phases.text = "PHASE I" + (marker if not second else "") + "  |  PHASE II" + (marker if second and not third else "") + "  |  PHASE III" + (marker if third else "")
	phases.modulate = Color(0.85,0.5,1) if third else (Color(1,0.62,0.25) if second else Color(0.95,0.86,0.68))
	queue_redraw()
func _draw():
	draw_style_box(style,Rect2(-5,-3,196,41))
	draw_rect(Rect2(0,13,180,5),Color(0.13,0.07,0.06))
	var ink = Color(0.85,0.4,1) if third else (Color(1,0.39,0.12) if second else Color(0.98,0.69,0.24))
	draw_rect(Rect2(0,13,180*ratio,5),ink)
	draw_rect(Rect2(0,13,180*ratio,1),ink.lightened(0.5))
	for i in range(1,18): draw_line(Vector2(i*10,14),Vector2(i*10,18),Color(0.05,0.07,0.1,0.3),0.5)
	# Real thresholds drawn on the bar itself, not just in the label.
	for mark in [PHASE_TWO_AT,PHASE_THREE_AT]:
		draw_line(Vector2(180*mark,11),Vector2(180*mark,20),Color(0.05,0.04,0.06),2)
