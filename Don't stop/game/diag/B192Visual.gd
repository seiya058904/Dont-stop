extends Node
## Frozen real actors/effects, solely for cross-renderer visual comparison.
var output := "user://b192-visual"
var subjects: Array = []

func freeze(node: Node) -> void:
	node.set_process(false); node.set_physics_process(false)
	for child in node.get_children(): freeze(child)
	if node is AnimatedSprite2D:
		node.stop()
		node.animation = "run" if node.sprite_frames.has_animation("run") else node.animation
		node.frame = mini(2,node.sprite_frames.get_frame_count(node.animation)-1)
		node.frame_progress = 0.0

func capture(key: String) -> void:
	var camera = get_viewport().get_camera_2d()
	camera.global_position = Utils.player.global_position
	camera.offset = Vector2.ZERO
	camera.reset_smoothing()
	camera.force_update_scroll()
	RenderingServer.global_shader_parameter_set("b19_enchantment_time",0.375)
	await RenderingServer.frame_post_draw
	if not OS.has_feature("web"): get_viewport().get_texture().get_image().save_png(output+"/"+key+".png")
	var states: Array = []
	for actor in subjects:
		states.append({"position":str(actor.global_position-Utils.player.global_position),"tier":actor.enchantment_tier,"phase":actor.enchantment_phase,"frame":actor.anim.frame,"hp":actor.HP})
	print("B192_VISUAL ",JSON.stringify({"name":key,"subjects":states,"window":str(get_window().size),"camera":str(get_viewport().get_canvas_transform()),"fixture":"frozen positions, animation and HP; not gameplay/performance acceptance"}))
	await get_tree().create_timer(2.5,true).timeout

func run() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for arg in OS.get_cmdline_args()+OS.get_cmdline_user_args():
		if arg.begins_with("--stress-visual-output="): output = arg.trim_prefix("--stress-visual-output=")
	if not OS.has_feature("web"): DirAccess.make_dir_recursive_absolute(output)
	LevelServer.return_to_camp()
	await get_tree().create_timer(0.3).timeout
	LevelServer.town.depart(39,true); LevelServer.timerStop()
	for group in ["monsters","combat_transient"]:
		for node in get_tree().get_nodes_in_group(group): node.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	get_tree().paused = true
	seed(20260920)
	var center: Vector2 = Utils.player.global_position
	Utils.player.changeWeapon(116); freeze(Utils.player)
	var variants = load("res://game/config/B18Variants.gd")
	variants.generation = LevelServer.epoch; variants.arrivals = 0; variants.enchanted_arrivals = 999999
	var positions = [Vector2(30,-32),Vector2(35,0),Vector2(20,36)]
	for i in 3:
		var actor = M5Content.spawn("E01",LevelServer.town.monster_root,center+positions[i])
		variants.apply(actor,i+1,1 if i==2 else 0)
		actor.set_enchantment_visual([1,2,1][i],i*2)
		actor.HP = float(actor.get_meta("initialized_hp"))*0.65
		freeze(actor); subjects.append(actor)
	var layer = LevelServer.town.monster_root.get_node("B19EnchantmentLayer")
	layer._process(0.375); layer.set_process(false)
	await capture("variants")
	for actor in subjects: actor.HP = 1000000.0
	var gun = Utils.player.gun
	var context = gun.shot_context()
	context.burn = WeaponCatalog.definition(116).burn
	get_tree().paused = false
	Combat.cone(gun,center+Vector2(10,-8),Vector2.RIGHT,context)
	get_tree().paused = true
	for node in get_tree().get_nodes_in_group("combat_transient"): freeze(node)
	await capture("thermal")
	Utils.player.changeWeapon(112); freeze(Utils.player)
	get_tree().paused = false
	Combat.arc(Utils.player.gun,center+Vector2(10,-8),Vector2.RIGHT)
	get_tree().paused = true
	for node in get_tree().get_nodes_in_group("combat_transient"): freeze(node)
	await capture("arc")
	for i in 9:
		var shot = load("res://game/monster/EnemyShot.gd").new()
		shot.position = center+Vector2(-65+i*12,60); shot.velocity = Vector2(125,0)
		shot.style = "ricochet" if i%2 else "laser"; shot.bounces_left = 1
		get_tree().current_scene.add_child(shot)
		shot.trail.assign([shot.position-Vector2(9,0),shot.position-Vector2(6,0),shot.position-Vector2(3,0)])
		shot._fog_position = shot.position; shot._fog_tip = shot.position+Vector2(14,0)
		shot._ink_dirty = true; shot._process(0); freeze(shot)
	await capture("barrage")
	get_tree().paused = false
	LevelServer.return_to_camp()
	await get_tree().create_timer(0.3).timeout
	LevelServer.town.depart(40,true); LevelServer.timerStop()
	await get_tree().create_timer(0.15).timeout
	get_tree().paused = true
	var boss = instance_from_id(LevelServer.boss_instance)
	subjects.clear()
	if is_instance_valid(boss):
		boss.phase_two = true; boss.phase_three = true; boss.HP = boss.max_hp*0.3
		boss.global_position = Utils.player.global_position+Vector2(75,-10); boss.phase = "move"
		freeze(boss); freeze(Utils.player); subjects.append(boss)
		boss._begin("cross_laser")
	await capture("boss-phase3")
	get_tree().paused = false
	LevelServer.return_to_camp()
	print("B192_VISUAL_DONE")
