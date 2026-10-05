extends Control
var title: Label
var phases: Label
var ratio = 1.0
var second = false
var third = false
var style: StyleBoxFlat
var badge: Label
var trailing_ratio := 1.0
var trail_delay := 0.0
var observed_boss := -1
var attack_status: Label
const PHASE_TWO_AT := 0.70
const PHASE_THREE_AT := 0.35
const ATTACK_CUES := {"dash":"突进","recover":"恢复","transition":"阶段转换","spawn":"入场"}
func _ready():
	position = Vector2(111,8); size = Vector2(180,28); mouse_filter = Control.MOUSE_FILTER_IGNORE
	style = preload("res://ui/GildedTheme.gd").plate(Color("111821bf"),Color("907652"),3)
	title = Label.new(); title.add_theme_font_size_override("font_size",8); add_child(title)
	title.add_theme_font_override("font",preload("res://fonts/fusion-pixel.otf"))
	title.add_theme_color_override("font_color",Color("f1d8aa"))
	title.size = Vector2(165,12)
	title.clip_text = true
	phases = Label.new(); phases.position.y = 20; phases.add_theme_font_size_override("font_size",6); add_child(phases)
	attack_status = Label.new()
	attack_status.position = Vector2(92,20)
	attack_status.size = Vector2(88,9)
	attack_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	attack_status.clip_text = true
	attack_status.add_theme_font_size_override("font_size",6)
	attack_status.add_theme_font_override("font",preload("res://fonts/fusion-pixel.otf"))
	add_child(attack_status)
	# HELL badge: the round's difficulty layer has to be visible for the whole fight, not
	# only on the stage-select screen.
	badge = Label.new(); badge.position = Vector2(168,2); badge.add_theme_font_size_override("font_size",5)
	badge.text = "HELL"; badge.modulate = Color(0.86,0.55,1); add_child(badge)
func _process(delta):
	var boss = LevelServer.get_boss()
	visible = LevelServer.state == "COMBAT" and is_instance_valid(boss) and not boss.is_die
	if not visible: return
	# Boss information has a fixed viewport-edge footprint, independent of inventory.
	position.y = 8
	badge.visible = HellMode.is_hell(LevelServer.level)
	observe_health(clampf(boss.HP/boss.max_hp,0,1),boss.get_instance_id(),delta)
	second = boss.phase_two
	third = boss.phase_three
	title.text = M5Content.definition(boss.role).name + ("  ·  第%d关" % LevelServer.level)
	# Three explicit phases with the active one marked, so the switch at 70% and 35% is a
	# readout the player can plan against instead of a surprise.
	var marker = "  ◀"
	phases.text = "I" + (marker if not second else "") + "  |  II" + (marker if second and not third else "") + "  |  III" + (marker if third else "")
	phases.modulate = Color(0.85,0.5,1) if third else (Color(1,0.62,0.25) if second else Color(0.95,0.86,0.68))
	attack_status.text = ("锁定" if boss.lock_frozen else "瞄准") if boss.phase == "warn" else ATTACK_CUES.get(boss.phase,"交战")
	attack_status.modulate = Color("f5cf91") if boss.phase == "warn" else Color("a7bbc2")
	queue_redraw()

func observe_health(value: float, identity: int, delta: float) -> void:
	# The solid fill is always live HP. Only the lost-health accent settles later.
	if identity != observed_boss or value > ratio:
		trailing_ratio = value
		trail_delay = 0.0
	elif value < ratio:
		if is_equal_approx(trailing_ratio,ratio): trail_delay = 0.12
		trailing_ratio = maxf(trailing_ratio,ratio)
	observed_boss = identity
	ratio = value
	trail_delay = maxf(0.0,trail_delay-delta)
	if trail_delay == 0.0: trailing_ratio = move_toward(trailing_ratio,ratio,delta*1.8)

func _draw():
	draw_style_box(style,Rect2(-5,-3,196,32))
	draw_rect(Rect2(0,13,180,5),Color(0.13,0.07,0.06))
	if trailing_ratio > ratio:
		draw_rect(Rect2(180*ratio,13,180*(trailing_ratio-ratio),5),Color("c68764"))
	var ink = Color(0.85,0.4,1) if third else (Color(1,0.39,0.12) if second else Color(0.98,0.69,0.24))
	draw_rect(Rect2(0,13,180*ratio,5),ink)
	draw_rect(Rect2(0,13,180*ratio,1),ink.lightened(0.5))
	for i in range(1,18): draw_line(Vector2(i*10,14),Vector2(i*10,18),Color(0.05,0.07,0.1,0.3),0.5)
	# Real thresholds drawn on the bar itself, not just in the label.
	for mark in [PHASE_TWO_AT,PHASE_THREE_AT]:
		draw_line(Vector2(180*mark,11),Vector2(180*mark,20),Color(0.05,0.04,0.06),2)
