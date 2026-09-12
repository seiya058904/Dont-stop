extends Node2D
# One epoch-bound warning/attack; all essential geometry remains visible.
var mode = "circle"
var radius = 38.0
var length = 210.0
var width = 8.0
var direction = Vector2.RIGHT
var angle = 0.7
var warning = 0.8
var duration = 0.12
var tick = 0.2
var damage = 1.0
var owner_ref: WeakRef
var epoch = -1
var elapsed = 0.0
var active_clock = 0.0
var hit_count = 0
var friendly_context: Dictionary = {}
var resolved = false
var sweep = 0.0
var initial_direction = Vector2.RIGHT
var maximum_length = 210.0
var activated = false
func _ready():
	epoch = LevelServer.epoch
	initial_direction = direction
	maximum_length = length
	add_to_group("combat_transient")
	add_to_group("hostile_zone")
	z_index = -1
func _physics_process(delta):
	if epoch != LevelServer.epoch or LevelServer.state != "COMBAT": queue_free(); return
	if owner_ref and (not is_instance_valid(owner_ref.get_ref()) or owner_ref.get_ref().is_die): queue_free(); return
	elapsed += delta
	if mode in ["line","charge"]:
		direction = initial_direction.rotated(clampf((elapsed-warning)/maxf(duration,0.01),0,1)*sweep)
		var query = PhysicsRayQueryParameters2D.create(global_position,global_position+direction*maximum_length,2147483648)
		var hit = get_world_2d().direct_space_state.intersect_ray(query)
		length = global_position.distance_to(hit.position) if not hit.is_empty() else maximum_length
	queue_redraw()
	if elapsed < warning: return
	if not activated:
		activated = true
		preload("res://game/effects/HostileVFX.gd").emit_at(get_tree().current_scene,global_position,radius if mode == "circle" else 18,direction)
	if not friendly_context.is_empty():
		if not resolved: resolved = true; Combat.explosion_context(global_position,radius,friendly_context)
	elif active_clock <= 0:
		active_clock += tick
		var target = Utils.player
		if is_instance_valid(target) and not target.is_dead:
			var offset = target.global_position-global_position
			var inside = offset.length() <= radius
			if mode in ["line","charge"]: inside = Geometry2D.get_closest_point_to_segment(target.global_position,global_position,global_position+direction*length).distance_to(target.global_position) <= width+6
			elif mode == "cone": inside = offset.length() <= radius and absf(direction.angle_to(offset)) <= angle
			if damage > 0 and inside and Combat.clear_line(global_position,target.global_position): target.onHit(damage,owner_ref.get_ref() if owner_ref else null); hit_count += 1
	active_clock -= delta
	if elapsed >= warning+duration: queue_free()
func _draw():
	preload("res://game/effects/CombatTelegraph.gd").paint(self,mode,direction,radius,length,width,angle,elapsed/maxf(0.01,warning),elapsed>=warning,sweep)
