extends "res://tests/M8Runtime.gd"

func _ready():
	await boot()
	var out = "res://evidence/visual-upgrade-20260919/b17-auras"
	DirAccess.make_dir_recursive_absolute(out)
	var view = SubViewport.new()
	view.size = Vector2i(1366,768)
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(view)
	view.canvas_transform = Transform2D(0,Vector2(3.33,3.33),0,Vector2.ZERO)
	var bg = ColorRect.new()
	bg.color = Color("141b23"); bg.size = Vector2(411,231); view.add_child(bg)
	var ids = [0,112,121,116,113,120,124,6,111,114,115,122]
	for id in ids:
		configure(id)
		var gun = Utils.player.gun
		check(is_instance_valid(gun.idle_visual) == (WeaponCatalog.tier(id)>=4),"aura tier contract "+str(id))
		var sprite = Sprite2D.new()
		sprite.texture = gun.image
		sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		sprite.position = Vector2(205,115)
		view.add_child(sprite)
		var aura = load("res://game/effects/WeaponIdle.gd").new()
		aura.preview_id = id
		aura.preview_tip = gun.gun_tip.position-gun.gun_image.position
		sprite.add_child(aura)
		for enabled in [false,true]:
			aura.aura_enabled = enabled
			await wait(0.15)
			if DisplayServer.get_name() != "headless":
				await RenderingServer.frame_post_draw
				view.get_texture().get_image().save_png(out+"/%d-%s.png" % [id,"on" if enabled else "off"])
		sprite.queue_free()
		await wait(0.05)
	view.queue_free()
	await wait(0.2)
	print("B17 AURAS checks=",checks," failures=",failures)
	get_tree().quit(1 if failures else 0)
