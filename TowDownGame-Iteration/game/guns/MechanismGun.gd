extends "res://game/guns/AlienRifle.gd"

func _shoot():
	if not is_use or player.is_dead or get_tree().paused or bullets_count <= 0 or is_reloading: return
	var spec = WeaponCatalog.definition(weapon_id)
	var context = damage_context()
	context.radius = effective.radius
	bullets_count -= 1
	Combat.attacks += 1
	var count = int(spec.get("count",1))
	for i in count:
		var angle = (i-(count-1)*0.5)*spec.get("fan",0.0)*effective.spread
		var shot_direction = direction.rotated(angle)
		var bullet = bullet_scene.instantiate()
		bullet.set_script(load("res://game/bullets/MechanismProjectile.gd"))
		bullet.spec = spec.duplicate(true)
		bullet.context = context.duplicate(true)
		bullet.hurt = context.damage
		bullet.speed = bullet_speed
		bullet.player = player
		bullet.gun = self
		get_tree().current_scene.add_child(bullet)
		bullet.global_position = gun_tip.global_position
		bullet.rotation = shot_direction.angle()
		bullet.fire()
		bullet.lock_target()
	audio.play()
	_shootAnim()
