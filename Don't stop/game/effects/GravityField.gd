extends Node2D
var context: Dictionary = {}
var age = 0.0
var ended = false
var footprint = PackedVector2Array()
var local_footprint = PackedVector2Array()
var edge = PackedVector2Array()
var inner_rings: Array[PackedVector2Array] = []
func _ready():
	add_to_group("combat_transient")
	footprint = preload("res://game/effects/CombatFootprint.gd").polygon(global_position,context.get("radius",64.0))
	for point in footprint: local_footprint.append(to_local(point))
	edge = local_footprint.duplicate()
	if not edge.is_empty(): edge.append(edge[0])
	for i in 3:
		var ring = PackedVector2Array()
		ring.resize(edge.size())
		inner_rings.append(ring)
func _physics_process(delta):
	if ended: return
	if context.get("epoch",-1) != LevelServer.epoch:
		queue_free()
		return
	age += delta
	var radius = context.get("radius",64.0)
	for target in get_tree().get_nodes_in_group("monsters"):
		if target.is_die or target.is_boss or target.training: continue
		var offset = global_position-target.global_position
		if Geometry2D.is_point_in_polygon(target.global_position,footprint) and offset.length() > 8 and Combat.clear_line(global_position,target.global_position):
			target.move_and_collide(offset.normalized()*minf(65*delta,offset.length()-8))
	if age >= 0.9:
		ended = true
		Combat.explosion_context(global_position,radius,context)
		queue_free()
	queue_redraw()
func _draw():
	var radius = context.get("radius",64.0)
	if local_footprint.is_empty(): return
	draw_colored_polygon(local_footprint,Color(0.6,0.4,1,0.08))
	draw_polyline(edge,Color(0.75,0.6,1,0.8),1)
	for i in 3:
		var scale_factor = fposmod(1.0-age+i/3.0,1.0)
		for point_index in edge.size(): inner_rings[i][point_index] = edge[point_index]*scale_factor
		draw_polyline(inner_rings[i],Color(0.6,0.4,1,0.65),1)
