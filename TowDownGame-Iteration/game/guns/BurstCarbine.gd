extends "res://game/guns/GunSprite.gd"

func _ready():
	super._ready()
	tags = ["projectile","spread","burst","straight"]

func _shoot():
	var generation = action_generation
	can_shoot = false
	timer.stop()
	for shot in 3:
		if generation != action_generation or not is_use or player.is_dead or get_tree().paused or bullets_count <= 0: break
		var bullet = bullet_scene.instantiate()
		get_tree().current_scene.add_child(bullet)
		bullet.setOnwer(player)
		bullet.global_position = gun_tip.global_position
		bullet.rotation = direction.angle() + deg_to_rad(randf_range(-3,3)) * effective.spread
		fire(bullet)
		_shootAnim()
		if shot < 2: await get_tree().create_timer(0.08,false).timeout
	if generation == action_generation:
		timer.start()
