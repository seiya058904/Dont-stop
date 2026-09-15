extends "res://game/guns/BaseGun.gd"


func _shoot():
	super._shoot()
	gun_tip.rotation = direction.angle()
	for i in projectile_count():
		var b = bullet_scene.instantiate()
		b.setOnwer(player)
		b.knockback_speed = knockback_speed
		get_tree().root.add_child(b)
		b.position = gun_tip.global_position
		b.rotation = gun_tip.rotation + deg_to_rad(-15 + i * 15) * effective.spread
		fire(b,true,false)
	if bullets_count == 0:
		var generation = action_generation
		await get_tree().create_timer(0.2,false).timeout
		if generation == action_generation and is_use: reload_ammo()

func _shootAnim():
	if not is_use or not is_instance_valid(player) or player.is_dead or get_tree().paused: return
	super._shootAnim()
	audio.play()
	play_shot_feedback(timer.wait_time*effective.get("recovery",1.0))

func _on_timer_timeout():
	can_shoot = true

func projectile_count() -> int: return 5
