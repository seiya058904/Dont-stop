extends Node2D
var clock := 0.0
func label_at(text: String, point: Vector2, size: int, color: Color) -> void:
	var label := Label.new(); label.text = text; label.position = point
	label.add_theme_font_size_override("font_size",size)
	label.add_theme_color_override("font_color",color); add_child(label)
func _ready():
	get_window().size = Vector2i(1280,720)
	get_window().content_scale_size = Vector2i(1280,720)
	var bg := ColorRect.new(); bg.color = Color("151b24"); bg.size = Vector2(1280,720); add_child(bg)
	label_at("ENCHANTMENT / BODY GLINT",Vector2(58,38),26,Color("e6e7ec"))
	label_at("Original sprite. Pixel-stepped violet sheen. No ring, flame or particle layer.",Vector2(58,81),18,Color("939cb0"))
	var actor = load("res://game/monster/Monster 2/Monster2.tscn").instantiate()
	var frames = actor.get_node("body/AnimatedSprite2D").sprite_frames
	for i in 4:
		var x := 170.0+i*310.0
		var sprite := AnimatedSprite2D.new()
		sprite.sprite_frames = frames; sprite.animation = "run"; sprite.play()
		sprite.position = Vector2(x,390)
		sprite.scale = Vector2.ONE*(10.0 if i==3 else 7.0)
		var material := ShaderMaterial.new(); material.shader = preload("res://shader/HitFlash.gdshader")
		material.set_shader_parameter("enchantment_tier",[0.0,1.0,2.0,1.0][i])
		sprite.material = material; add_child(sprite)
		label_at(["ORIGINAL","ENCHANTED I","ENCHANTED II","GIANT / I"][i],Vector2(x-95,500),20,Color("bab1d8") if i else Color("939cb0"))
	actor.free()
	DirAccess.make_dir_recursive_absolute("res://output/b19-1/glint-motion")
	for i in 40:
		await get_tree().create_timer(0.08).timeout
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("res://output/b19-1/glint-motion/frame-%02d.png"%i)
	await Demo.finish_quit()
func _process(delta):
	clock += delta
	RenderingServer.global_shader_parameter_set("b19_enchantment_time",clock)
