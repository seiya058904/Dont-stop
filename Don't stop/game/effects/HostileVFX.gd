extends Node2D
static var alive = 0
var age = 0.0
var lifetime = 0.28
var radius = 18.0
var direction = Vector2.RIGHT
static func emit_at(parent: Node, point: Vector2, reach = 18.0, dir = Vector2.RIGHT):
	if alive >= 32: return
	var fx = load("res://game/effects/HostileVFX.gd").new()
	fx.position = point; fx.radius = minf(75,reach); fx.direction = dir
	parent.add_child(fx)
func _ready():
	alive += 1; add_to_group("combat_transient"); add_to_group("hostile_vfx"); z_index = 6
func _exit_tree(): alive -= 1
func _process(delta):
	age += delta
	if age >= lifetime: queue_free(); return
	queue_redraw()
func _draw():
	var p = age/lifetime
	var color = Color(1,0.56+0.28*(1-p),0.2,(1-p)*0.7)
	draw_arc(Vector2.ZERO,radius*(0.25+0.75*p),0,TAU,28,color,1.8*(1-p)+0.5,true)
	var sparks = PackedVector2Array()
	for i in 8:
		var dir = direction.rotated(i*TAU/8)
		sparks.append(dir*radius*p*0.6)
		sparks.append(dir*radius*(p*0.8+0.18))
	draw_multiline(sparks,color,1.4,true)
