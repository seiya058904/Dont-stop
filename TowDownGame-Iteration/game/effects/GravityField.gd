extends Node2D
var context: Dictionary = {}
var age = 0.0
var ended = false
func _ready():
	add_to_group("combat_transient")
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
		if offset.length() < radius and offset.length() > 8 and Combat.clear_line(global_position,target.global_position):
			target.move_and_collide(offset.normalized()*minf(65*delta,offset.length()-8))
	if age >= 0.9:
		ended = true
		Combat.explosion_context(global_position,radius,context)
		queue_free()
	queue_redraw()
func _draw():
	var radius = context.get("radius",64.0)
	for i in 3:
		draw_arc(Vector2.ZERO,radius*fposmod(1.0-age+i/3.0,1.0),0,TAU,24,Color(0.6,0.4,1,0.75),1)
