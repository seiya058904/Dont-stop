extends "res://game/guns/BaseGun.gd"

func _shoot():
	var mouse_pos = Utils.get_aim_world_position()
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
	if not is_use or not is_instance_valid(player) or player.is_dead or get_tree().paused: return
	super._shootAnim()
	audio.play()
	play_shot_feedback(timer.wait_time*effective.get("recovery",1.0))

func _on_timer_timeout():
	can_shoot = true
