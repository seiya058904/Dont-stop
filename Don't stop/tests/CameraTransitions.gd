extends "res://tests/M3Weapons.gd"

func _ready():
	Demo.test_mode = true
	Demo.save_path = "user://camera-transitions.json"
	seed(808)
	add_child(load("res://game/map/Main.tscn").instantiate())
	Utils.gameStart()
	await wait(0.2)
	dismiss_panels()
	Demo.try_purchase("weapon","0")
	Utils.player.changeWeapon(0)
	var camera = LevelServer.town.get_node("TileMap2/PlayerRoot/Anchor/Camera2D")
	var screen := get_viewport().get_visible_rect()
	Utils.aim_override = screen.get_center()
	for stage in [1,10,20,30,31,39,40]:
		check(LevelServer.town.depart(stage,true),"camera test departs stage "+str(stage))
		# Sample immediately, before a smoothing frame can conceal the bad handover.
		check(player_on_screen(screen),"player is visible on the first combat frame "+str(stage))
		await wait(0.1)
		check(player_on_screen(screen),"player remains visible after settling "+str(stage))
		camera.offset = Vector2(12,-8)
		LevelServer.return_to_camp()
		dismiss_panels()
		check(player_on_screen(screen),"camp return snaps both camera smoothing layers "+str(stage))
		check(camera.offset == Vector2.ZERO,"camp return clears leftover recoil "+str(stage))
		await wait(0.05)
	Utils.aim_override = Vector2(100000,-100000)
	camera.position = Vector2.ZERO
	for i in 30: camera._process(1.0/30.0)
	var at_30: Vector2 = camera.position
	check(at_30.length() <= camera.MAX_LOOK_AHEAD+0.001,"off-window aiming cannot drag the hero out of view")
	camera.position = Vector2.ZERO
	for i in 120: camera._process(1.0/120.0)
	check(camera.position.distance_to(at_30) < 0.001,"camera lead converges equally at 30 and 120 FPS")
	camera.shootShake(Vector2(5,5))
	var old_tween: Tween = camera.shake_tween
	camera.reset_after_teleport()
	check(not camera.is_shake and (old_tween == null or not old_tween.is_valid()),"teleport retires the old recoil animation")
	Utils.aim_override = null
	print("CAMERA_TRANSITIONS checks=",checks," failures=",failures)
	if failures: get_tree().quit(1)
	else: await Demo.quit_game()

func dismiss_panels() -> void:
	for panel in Demo.pause_stack.duplicate():
		Demo.pop_pause(panel)
		panel.queue_free()

func player_on_screen(screen: Rect2) -> bool:
	var point := Utils.player.get_global_transform_with_canvas().origin
	return screen.grow(-24).has_point(point)
