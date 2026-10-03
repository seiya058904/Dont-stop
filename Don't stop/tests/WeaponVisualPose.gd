extends "res://tests/M8Runtime.gd"

# Compare attached artwork with the same points on the sprite, including its
# texture offset. Sampling immediately catches a one-frame following delay too.
func follows_sprite(gun: BaseGun, points: Array, offset: Vector2) -> bool:
	for pair in points:
		var expected: Vector2 = gun.gun_image.to_global(pair[1]+gun.gun_image.offset-offset)
		if gun.idle_visual.to_global(pair[0]).distance_to(expected) > 0.001: return false
	return true

func _ready():
	await boot()
	dismiss()
	Utils.player.set_process(false)
	Utils.player.set_physics_process(false)
	configure(0)
	for id in preload("res://game/effects/WeaponIdle.gd").PALETTES:
		configure(id)
		var gun: BaseGun = Utils.player.gun
		var sprite: Sprite2D = gun.gun_image
		var rest := sprite.transform
		var offset := sprite.offset
		var tip: Vector2 = gun.gun_tip.position
		var points: Array = []
		for point in [Vector2.ZERO,tip,tip+Vector2(-9,4)]:
			points.append([point,sprite.to_local(gun.idle_visual.to_global(point))])
		check(follows_sprite(gun,points,offset),str(id)+" ornament aligns at rest")
		gun.bullets_count -= 1
		gun.reload_ammo()
		check(gun.is_reloading and gun.anim_player.current_animation == "reload",str(id)+" uses the real reload animation")
		for time in [0.3,0.5,0.7]:
			gun.anim_player.seek(time,true)
			check(follows_sprite(gun,points,offset),str(id)+" ornament follows reload at "+str(time))
		gun.anim_player.seek(0.5,true)
		Utils.player.changeWeapon(0)
		check(sprite.transform.is_equal_approx(rest) and sprite.offset == offset,str(id)+" switching mid-reload restores the entire sprite pose")
		check(not gun.idle_visual.is_visible_in_tree(),str(id)+" unequipped ornament is hidden")
		Utils.player.changeWeapon(id)
		gun.set_process(false)
		check(sprite.transform.is_equal_approx(rest) and follows_sprite(gun,points,offset),str(id)+" re-equipping cannot retain a partial reload pose")
		gun.play_shot_feedback(0.1)
		check(follows_sprite(gun,points,offset),str(id)+" ornament inherits recoil squash")
		gun.cancel_actions()
		gun.anim_player.play("run")
		gun.anim_player.seek(0.075,true)
		check(follows_sprite(gun,points,offset),str(id)+" ornament follows the texture's running offset immediately")
		Utils.player.body.scale.x = -1
		gun.rotation = 0.6
		check(follows_sprite(gun,points,offset),str(id)+" ornament stays attached while aiming left")
		gun.cancel_actions()
		check(sprite.transform.is_equal_approx(rest) and sprite.offset == offset,str(id)+" cancellation restores running offset too")
		check(gun.gun_tip.position == tip,str(id)+" cosmetic pose does not move the firing anchor")
		Utils.player.body.scale.x = 1
		gun.rotation = 0
	var preview = preload("res://game/effects/WeaponIdle.gd").new()
	preview.preview_id = 113
	preview.preview_tip = Vector2(12,0)
	add_child(preview)
	await wait(0.05)
	check(preview.visible and preview.position == Vector2.ZERO,"camp preview still works without a live gun")
	preview.queue_free()
	print("WEAPON_VISUAL_POSE checks=",checks," failures=",failures)
	if failures: get_tree().quit(1)
	else: await Demo.quit_game()
