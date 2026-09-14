extends "res://game/guns/BaseGun.gd"

@export var cast_count = 2 #激光目标个数

@onready var cast = $RayCast2D
@onready var line_2d = $RayCast2D/Line2D
@onready var particles_box = $RayCast2D/Line2D/GPUParticles2D
@onready var particles_end = $RayCast2D/GPUParticles2D2
@onready var tick = $tick

var beam_tween: Tween
var is_cast = false
var pulse_boost = 1.0
var one_bullet_array = []

func _shoot():
	super._shoot()
	var mouse_pos = Utils.get_aim_world_position()
	var direction = (mouse_pos - gun_tip.global_position).normalized()
	gun_tip.rotation = direction.angle()
	openFire()

func _shootAnim():
	if not is_use or player.is_dead or get_tree().paused: return
	super._shootAnim()
	var tween = get_tree().create_tween().set_parallel(true)
	tween.tween_property(self, "position", position, timer.wait_time).from(position + Vector2(-1, -1))
	tween.tween_property($Sprite2D, "scale", Vector2(1,1), timer.wait_time).from(Vector2(0.5, 1.1))
	add_child(particles_pre.instantiate())

func _on_timer_timeout():
	can_shoot = true

func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	cast.target_position = Vector2(effective.range,0)
	var endpoint = cast.to_global(cast.target_position)
	cast.force_raycast_update()
	if is_cast:
		if cast.is_colliding():
			var coller = cast.get_collider()
			endpoint = cast.get_collision_point()
			particles_end.global_rotation = cast.get_collision_normal().angle()
			if coller is BaseMonster && one_bullet_array.size() < cast_count:
				bulletHurt(coller)
	# PackedVector2Array property indexing edits a copy; use the Line2D setter.
	var start = line_2d.to_local(cast.global_position)
	var end = line_2d.to_local(endpoint)
	line_2d.set_point_position(0, start)
	line_2d.set_point_position(1, end)
	particles_box.position = (start + end) * 0.5
	particles_box.rotation = (end - start).angle()
	particles_box.process_material.emission_box_extents.x = start.distance_to(end) * 0.5
	particles_end.global_position = endpoint

func bulletHurt(coller):
	if one_bullet_array.has(coller):
		return
	var context = damage_context()
	context.damage *= pulse_boost
	Combat.hit(coller, context)
	one_bullet_array.append(coller)

func openFire():
	if bullets_count == 0:
		return
	pulse_boost = 1.0+DemoConfig.talent_value("T12",Demo.rank("T12")) if first_round else 1.0
	first_round = false
	bullets_count -= 1
	is_cast = true
	openLaser()
	var generation = action_generation
	await get_tree().create_timer(0.4, false).timeout
	if generation == action_generation: stopLaser()

func openLaser():
	one_bullet_array.clear()
	audio.play()
	player.set_knockback(recoil)
	tick.start()
	particles_end.emitting = true
	particles_box.emitting = true
	if beam_tween and beam_tween.is_valid(): beam_tween.kill()
	beam_tween = get_tree().create_tween().set_ease(Tween.EASE_OUT)
	beam_tween.tween_property(line_2d,"width",effective.width,0.2)

func stopLaser():
	audio.stop()
	tick.stop()
	is_cast = false
	particles_end.emitting = false
	particles_box.emitting = false
	if beam_tween and beam_tween.is_valid(): beam_tween.kill()
	beam_tween = get_tree().create_tween().set_ease(Tween.EASE_OUT)
	beam_tween.tween_property(line_2d,"width",0.0,0.2)


func _on_tick_timeout() -> void:
	one_bullet_array.clear()

func cancel_actions():
	if beam_tween and beam_tween.is_valid(): beam_tween.kill()
	super.cancel_actions()
	if is_instance_valid(tick):
		tick.stop()
		is_cast = false
		one_bullet_array.clear()
		particles_end.emitting = false
		particles_box.emitting = false
		line_2d.width = 0
