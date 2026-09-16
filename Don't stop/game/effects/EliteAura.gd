extends Node2D

## Elite identification marker.
##
## The old elite was "HP x 1.5" plus a 7 px 精英 label, which the player could not read in
## time. Every elite now carries an aura whose colour encodes its extra mechanic family, so
## the promotion is identifiable before it is engaged - the user's requirement that elites
## "视觉上必须有 Elite marker / aura / distinct color".
##
## Purely decorative: it owns no collision and no damage.
const FAMILY = {
	# modifier -> {ring, glyph}
	"sprint":Color(1.0,0.72,0.24),
	"pack":Color(1.0,0.72,0.24),
	"double_charge":Color(1,0.62,0.2),
	"burst":Color(1,0.78,0.34),
	"ram_shockwave":Color(1,0.5,0.18),
	"cluster":Color(1,0.34,0.24),
	"hive":Color(0.66,0.86,1.0),
	"bulwark":Color(0.98,0.86,0.4),
	"root_artillery":Color(0.8,0.5,1.0),
	"fan":Color(1.0,0.5,0.94),
	"ember_field":Color(1,0.45,0.3),
	"double_root":Color(0.82,0.46,1.0),
	"cross_beam":Color(0.45,0.95,1.0),
	"lingering_poison":Color(0.44,1.0,0.62)
}

var modifier := ""
var tint := Color(1,0.78,0.3)
var clock := 0.0
var label: Label

func _ready() -> void:
	tint = FAMILY.get(modifier,Color(1,0.78,0.3))
	z_index = 3
	label = Label.new()
	label.text = "精英"
	label.add_theme_font_size_override("font_size",7)
	label.position = Vector2(-10,-32)
	add_child(label)
	queue_redraw()

func _process(delta: float) -> void:
	clock += delta
	queue_redraw()

func _draw() -> void:
	var pulse = 0.5+0.5*sin(clock*3.0)
	# Two counter-rotating brackets plus a filled halo: readable at a glance and distinct
	# from every attack telegraph, which are all warm/cyan wedges rather than rings.
	draw_circle(Vector2(0,-8),15,Color(tint.r,tint.g,tint.b,0.10+0.06*pulse))
	draw_arc(Vector2(0,-8),15,-0.9+clock*0.9,0.9+clock*0.9,10,Color(tint.r,tint.g,tint.b,0.9),2,true)
	draw_arc(Vector2(0,-8),15,PI-0.9-clock*0.9,PI+0.9-clock*0.9,10,Color(tint.r,tint.g,tint.b,0.9),2,true)
	draw_arc(Vector2(0,-8),19,0,TAU,20,Color(tint.r,tint.g,tint.b,0.18+0.12*pulse),1,true)
