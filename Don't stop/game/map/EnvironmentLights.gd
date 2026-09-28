extends Node2D
## Reflected environmental light, deliberately below actors and threat ink.
var anchors: Array[Vector2] = []
var ink := Color("d3ab72")
var clock := 0.0
var tick := 0.0

func _ready():
	z_as_relative = false
	z_index = -3
	var blend := CanvasItemMaterial.new()
	blend.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	blend.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	material = blend

func _process(delta):
	clock += delta
	tick += delta
	if tick < 0.08: return
	tick = 0.0
	queue_redraw()

func _draw():
	var light = preload("res://game/effects/PresentationLight.gd").texture()
	for i in anchors.size():
		var breath := 0.19 if Combat.reduced_flash else 0.21+sin(clock*0.7+i)*0.025
		var p: Vector2 = anchors[i]
		draw_texture_rect(light,Rect2(p-Vector2(58,35),Vector2(116,70)),false,Color(ink,breath))
		draw_texture_rect(light,Rect2(p-Vector2(12,5),Vector2(24,10)),false,Color(ink,breath*1.2))
