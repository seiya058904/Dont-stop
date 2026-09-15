extends "res://game/guns/BaseGun.gd"

func _shoot():
	super._shoot()
	var mouse_pos = Utils.get_aim_world_position()
	var direction = (mouse_pos - gun_tip.global_position).normalized()
	gun_tip.rotation = direction.angle()
	createBullet()

func createBullet():
	var generation = action_generation
	for i in projectile_count():
		if generation != action_generation or not is_use or not is_instance_valid(player) or player.is_dead or get_tree().paused: return
		var b = bullet_scene.instantiate()
		b.setOnwer(player)
		get_tree().root.add_child(b)
		b.position = gun_tip.global_position
		b.rotation = gun_tip.rotation
		fire(b)
		# The recoil is started once per trigger pull, by BaseGun._shoot()'s
		# deferred _shootAnim(). Asking for it here as well played the same
		# animation once per pellet, so three of the four tweens always started
		# from an unfinished one - the actual mechanism behind the drift.
		await get_tree().create_timer(0.15,false).timeout

func _shootAnim():
	if not is_use or not is_instance_valid(player) or player.is_dead or get_tree().paused: return
	super._shootAnim()
	play_shot_feedback(0.15*effective.get("recovery",1.0))

func _on_timer_timeout():
	can_shoot = true

func projectile_count() -> int: return 3
