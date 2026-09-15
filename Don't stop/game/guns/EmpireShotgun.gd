extends "res://game/guns/BaseGun.gd"

func _shoot():
	super._shoot()
	gun_tip.rotation = direction.angle()

	call_deferred("createBullet",action_generation)

func createBullet(generation):
	for index in 2:
		if generation != action_generation or not is_use or player.is_dead or get_tree().paused: return
		for i in int(projectile_count()/2):
			var b = bullet_scene.instantiate()
			b.setOnwer(player)
			b.knockback_speed = knockback_speed
			get_tree().root.add_child(b)
			b.position = gun_tip.global_position
			b.rotation = gun_tip.rotation + deg_to_rad(-15 + i * 15) * effective.spread
			fire(b)
		await get_tree().create_timer(0.2).timeout

func _shootAnim():
	if not is_use or not is_instance_valid(player) or player.is_dead or get_tree().paused: return
	super._shootAnim()
	play_shot_feedback(timer.wait_time*effective.get("recovery",1.0))

func _on_timer_timeout():
	can_shoot = true

func projectile_count() -> int: return 4
