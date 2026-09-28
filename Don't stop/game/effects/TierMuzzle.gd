extends Node2D
var tier = 1
var remaining = 0.0
var family := "ballistic"
var shot_id := -1
const FAMILIES = {1:"scatter",5:"scatter",8:"scatter",6:"beam",111:"prism",112:"arc",113:"rail",114:"plasma",115:"cone",116:"thermal",117:"heavy",118:"shard",119:"rocket",120:"rocket",121:"gravity",122:"disc",124:"rotary"}
func _ready():
	z_index = 2
	set_process(false)
func pulse(level: int, weapon_id: int = -1):
	tier = level
	shot_id = weapon_id
	family = FAMILIES.get(weapon_id,"ballistic")
	remaining = 0.07
	visible = true
	set_process(true)
	queue_redraw()
func stop():
	remaining = 0
	visible = false
	set_process(false)
func _process(delta):
	remaining -= delta
	if remaining <= 0: stop()
	else: queue_redraw()
func _draw():
	var alpha = minf(0.8,remaining/0.07)* (0.35 if Combat.reduced_flash else 1.0)
	var color = Color("ddbc83")
	if family in ["beam","prism","arc","rail","plasma","heavy","shard","disc"]: color = Color("91cdd4")
	elif family == "gravity": color = Color("b4a1d9")
	elif family == "thermal": color = Color("e2a15c")
	color.a = alpha
	if tier >= 4: color = Color(preload("res://game/effects/WeaponIdle.gd").PALETTES.get(shot_id,color),alpha)
	if not Combat.reduced_flash:
		draw_texture_rect(preload("res://game/effects/PresentationLight.gd").texture(),Rect2(-12,-9,32,18),false,Color(color,alpha*0.48))
	var flash_length := 5.0+minf(tier,5)*1.1
	if not Combat.reduced_flash:
		draw_colored_polygon(PackedVector2Array([Vector2(-1,0),Vector2(3,-2),Vector2(flash_length,0),Vector2(3,2)]),Color(color,alpha*0.25))
		draw_line(Vector2.ZERO,Vector2(flash_length*0.7,0),Color("fff3d8",alpha),1)
	# One reusable source emitter, at most four short strokes; no radial spray.
	var reach := 6.0 if tier <= 2 else 8.0
	match family:
		"scatter","cone":
			draw_line(Vector2.ZERO,Vector2(5,0),color,2)
			for side in [-1,1]: draw_line(Vector2(1,side),Vector2(5,side*3),color,1)
		"prism":
			for side in [-1,0,1]: draw_line(Vector2.ZERO,Vector2(7,side*2),color,1)
		"rail","beam":
			draw_line(Vector2.ZERO,Vector2(10,0),color,1)
			draw_line(Vector2(1,-2),Vector2(1,2),color,1)
		"arc":
			draw_polyline(PackedVector2Array([Vector2.ZERO,Vector2(3,-2),Vector2(4,1),Vector2(7,0)]),color,1)
		"thermal":
			draw_line(Vector2.ZERO,Vector2(8,0),color,2)
			draw_line(Vector2(2,-1),Vector2(5,-1),Color(color,alpha*0.6),1)
		"gravity","plasma","disc":
			draw_arc(Vector2(2,0),3,-1.1,1.1,6,color,1)
			draw_line(Vector2.ZERO,Vector2(5,0),color,1)
		_:
			draw_line(Vector2.ZERO,Vector2(reach,0),color,1.5)
			if tier >= 3: draw_line(Vector2(2,-1),Vector2(4,1),color,1)
