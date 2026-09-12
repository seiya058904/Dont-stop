extends Node
var checks = 0
var failures = 0
func _ready():
	Demo.test_mode = true
	get_window().size = Vector2i(1536,864)
	var viewport = SubViewport.new()
	viewport.size = Vector2i(1536,864)
	viewport.world_2d = get_viewport().world_2d
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(viewport)
	viewport.add_child(load("res://game/map/Main.tscn").instantiate())
	Utils.gameStart()
	for frame in 10: await get_tree().process_frame
	Demo.try_purchase("weapon","0")
	var target = Utils.player.global_position+Vector2(70,-9)
	for local in [false,true]:
		var motion = InputEventMouseMotion.new()
		motion.position = viewport.get_canvas_transform()*target
		viewport.push_input(motion,local)
		print("INPUT PROBE local=",local," target=",target," actual=",Utils.player.get_global_mouse_position()," viewport=",get_viewport().size)
	checks += 1
	if Utils.player.get_global_mouse_position().distance_to(target)>0.1: failures+=1
	print("R1 BACKGROUND INPUT checks=",checks," failures=",failures)
	await Demo.quit_game()
