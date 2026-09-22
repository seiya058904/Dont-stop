extends Node2D
## Only resolved hit edges enter this renderer. Animation never queries or damages actors.
var edges: Array = []
var contacts: Array = []
var age := 0.0
var epoch := -1
var _path_phase := -1
var _cached_paths: Array = []
var _contact_ink: Node2D
func _ready():
	epoch = LevelServer.epoch
	add_to_group("combat_transient")
	z_index = 3
	_contact_ink = Node2D.new()
	_contact_ink.draw.connect(_draw_contacts)
	add_child(_contact_ink)
func _process(delta):
	age += delta
	if age > 0.19 or epoch != LevelServer.epoch: queue_free(); return
	# Fade retained draw commands; only the 35 Hz shape changes rebuild the edges.
	modulate.a = (1.0-age/0.19)*(0.55 if Combat.reduced_flash else 1.0)
	if floori(age*35.0) != _path_phase: queue_redraw()
	_contact_ink.queue_redraw()

func _rebuild_paths(phase: int) -> void:
	_cached_paths.clear()
	for e in edges:
		var path = PackedVector2Array([e[0]])
		var normal = (e[1]-e[0]).normalized().orthogonal()
		for i in range(1,8):
			var p = e[0].lerp(e[1],i/8.0)+normal*sin(i*9.3+phase*2.1)*4
			path.append(p.round())
		path.append(e[1])
		_cached_paths.append(path)
	_path_phase = phase

func _draw():
	var phase := floori(age*35.0)
	if phase != _path_phase or _cached_paths.size() != edges.size(): _rebuild_paths(phase)
	for edge_index in _cached_paths.size():
		var path: PackedVector2Array = _cached_paths[edge_index]
		var edge = edges[edge_index]
		var normal = (edge[1]-edge[0]).normalized().orthogonal()
		draw_polyline(path,Color(0.05,0.18,0.32),5)
		draw_polyline(path,Color(0.25,0.65,1),3)
		draw_polyline(path,Color(0.8,0.97,1),1)
		for i in [2,5]:
			var fork = path[i]+normal*(6 if i==2 else -7)
			draw_polyline(PackedVector2Array([path[i],fork,fork+(edge[1]-edge[0]).normalized()*5]),Color(0.4,0.8,1,0.65),1)

func _draw_contacts() -> void:
	var segments := PackedVector2Array()
	segments.resize(contacts.size()*20)
	var offset := 0
	for p in contacts:
		for i in 5:
			var a = Vector2.RIGHT.rotated(i*TAU/5+age*9)
			var r = 5+age*28
			var bend = p+a*(r+3)+a.orthogonal()*3
			segments[offset] = p+a*r
			segments[offset+1] = bend
			segments[offset+2] = bend
			segments[offset+3] = p+a*(r+7)
			offset += 4
	if not segments.is_empty(): _contact_ink.draw_multiline(segments,Color(0.55,0.9,1),1)
