extends Node2D
## Only resolved hit edges enter this renderer. Animation never queries or damages actors.
var edges: Array = []
var contacts: Array = []
var age := 0.0
var epoch := -1
func _ready():
	epoch = LevelServer.epoch
	add_to_group("combat_transient")
	z_index = 3
func _process(delta):
	age += delta
	if age > 0.19 or epoch != LevelServer.epoch: queue_free(); return
	queue_redraw()
func _draw():
	var alpha = (1.0-age/0.19)*(0.55 if Combat.reduced_flash else 1.0)
	for e in edges:
		var path = PackedVector2Array([e[0]])
		var normal = (e[1]-e[0]).normalized().orthogonal()
		for i in range(1,8):
			var p = e[0].lerp(e[1],i/8.0)+normal*sin(i*9.3+floor(age*35)*2.1)*4
			path.append(p.round())
		path.append(e[1])
		draw_polyline(path,Color(0.05,0.18,0.32,alpha),5)
		draw_polyline(path,Color(0.25,0.65,1,alpha),3)
		draw_polyline(path,Color(0.8,0.97,1,alpha),1)
		for i in [2,5]:
			var fork = path[i]+normal*(6 if i==2 else -7)
			draw_polyline(PackedVector2Array([path[i],fork,fork+(e[1]-e[0]).normalized()*5]),Color(0.4,0.8,1,alpha*0.65),1)
	for p in contacts:
		for i in 5:
			var a = Vector2.RIGHT.rotated(i*TAU/5+age*9)
			var r = 5+age*28
			draw_polyline(PackedVector2Array([p+a*r,p+a*(r+3)+a.orthogonal()*3,p+a*(r+7)]),Color(0.55,0.9,1,alpha),1)
