extends "res://game/guns/BaseGun.gd"

func _shoot():
	var mouse_pos = get_global_mouse_position()
	var direction = (mouse_pos - gun_tip.global_position).normalized()
	gun_tip.rotation = direction.angle()
	var b = bullet_scene.instantiate()
	b.setOnwer(player)
	get_tree().root.add_child(b)
	b.position = gun_tip.global_position
	b.rotation = gun_tip.rotation
	fire(b)

	call_deferred("_shootAnim")
	can_shoot = false
	timer.start()

func _shootAnim():
	if not is_use or player.is_dead or get_tree().paused: return
	super._shootAnim()
	audio.play()
	var tween = get_tree().create_tween().set_parallel(true)
	tween.tween_property(self, "position", position, timer.wait_time*effective.get("recovery",1.0)).from(position + Vector2(-1, -1))
	tween.tween_property($Sprite2D, "scale", Vector2(1,1), timer.wait_time*effective.get("recovery",1.0)).from(Vector2(0.5, 1.1))

func _on_timer_timeout():
	can_shoot = true
