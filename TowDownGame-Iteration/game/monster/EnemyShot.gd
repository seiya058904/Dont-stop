extends CharacterBody2D
var owner_ref: WeakRef
var life = 0.0
var epoch = 0
var trail: Array[Vector2] = []
func _ready():
	add_to_group("combat_transient")
	epoch = LevelServer.epoch
	collision_layer = 0
	collision_mask = 2147483649
	add_collision_exception_with(Utils.player)
	for actor in get_tree().get_nodes_in_group("monsters"): add_collision_exception_with(actor)
	var shape = CollisionShape2D.new()
	shape.shape = CircleShape2D.new()
	shape.shape.radius = 3
	add_child(shape)
	z_index = 5
func _draw():
	for i in range(1,trail.size()):
		draw_line(to_local(trail[i-1]),to_local(trail[i]),Color(1,0.4,0.1,0.1+0.45*i/trail.size()),1.0+1.5*i/trail.size(),true)
	draw_circle(Vector2.ZERO,4,Color(0.15,0.08,0.04))
	draw_circle(Vector2.ZERO,2.8,Color(1,0.55,0.15))
func _physics_process(delta):
	life += delta
	if life > 4 or epoch != LevelServer.epoch or (owner_ref and (not is_instance_valid(owner_ref.get_ref()) or owner_ref.get_ref().is_die)):
		queue_free()
		return
	trail.append(global_position)
	if trail.size()>7: trail.pop_front()
	queue_redraw()
	var previous = global_position
	if move_and_collide(velocity*delta):
		queue_free()
		return
	if Geometry2D.get_closest_point_to_segment(Utils.player.global_position,previous,global_position).distance_to(Utils.player.global_position) < 12:
		Utils.player.onHit(1,owner_ref.get_ref() if owner_ref else null)
		preload("res://game/effects/HostileVFX.gd").emit_at(get_tree().current_scene,global_position,14,velocity.normalized())
		queue_free()
