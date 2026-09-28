extends Node2D
## Shared, capped contact ink. It observes resolved damage and never rolls RNG.
static var active := 0
const LIMIT := 32
var age := 0.0
var critical := false
var tint := Color("f3c786")
var epoch := -1
var phase := 0.0

func _ready():
	active += 1
	add_to_group("combat_transient")
	epoch = LevelServer.epoch
	z_index = 4
	phase = fposmod(position.x*0.17+position.y*0.23,TAU)

func _exit_tree(): active -= 1

func _process(delta):
	age += delta
	if age >= 0.22 or epoch != LevelServer.epoch: queue_free(); return
	queue_redraw()

func _draw():
	var progress := age/0.22
	var fade := 1.0-progress
	var alpha := fade*(0.3 if Combat.reduced_flash else 0.85)
	var count := 6 if critical else 3
	for i in count:
		var direction := Vector2.RIGHT.rotated(phase+i*TAU/count)
		var distance := (3.0+progress*11.0)*(1.25 if critical else 1.0)
		var p := direction*distance+Vector2(0,progress*progress*4)
		draw_line(p,p+direction*(1.0+fade*3),Color(tint,alpha),1)
	if age < 0.055:
		draw_line(Vector2(-2,0),Vector2(2,0),Color("fff3d7",alpha),1)
		draw_line(Vector2(0,-2),Vector2(0,2),Color("fff3d7",alpha),1)
	if critical:
		draw_arc(Vector2.ZERO,3+progress*9,phase,phase+PI*1.5,12,Color(tint,alpha*0.55),1)
