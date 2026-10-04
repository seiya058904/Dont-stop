extends "res://tests/M8Runtime.gd"

# Exercise the real factory, live PhysicsServer queries and E01's signal path.
# --legacy-sensors permits running the same fixture against 0248e60 for comparison.
func _ready():
	await boot()
	dismiss()
	configure(0,false)
	Utils.player.set_physics_process(false)
	LevelServer.level = 40
	var legacy := OS.get_cmdline_user_args().has("--legacy-sensors")
	var actors := Node2D.new()
	add_child(actors)
	var crowd = M5Content.spawn("E01",actors,origin+Vector2(-50,0))
	crowd.set_physics_process(false)
	var barrier = wall(origin+Vector2(50,-9),Vector2(12,60))
	var records: Array = []
	for id in M5Content.ENEMIES.keys()+M5Content.BOSSES.keys():
		seed(20261004)
		var actor = M5Content.spawn(id,actors,origin)
		check(is_instance_valid(actor),id+" production actor spawns")
		if not is_instance_valid(actor): continue
		actor.set_physics_process(false)
		actor.set_process(false)
		var body: CollisionShape2D = actor.get_node("CollisionShape2D")
		var area: Area2D = actor.get_node("Area2D")
		var sensor: CollisionShape2D = area.get_node("CollisionShape2D")
		check(actor.collision_layer == 3 and actor.collision_mask == 2147483649 and not body.disabled,id+" retains active body layers and geometry")
		if id.begins_with("B"):
			check(body.shape is CircleShape2D and body.shape.radius == (13.0 if id == "B04" else 11.0) and body.position == Vector2(0,-2),id+" retains authored boss hull")
		else:
			check(body.shape is CapsuleShape2D and body.shape.radius == 7.0 and body.shape.height == 20.0 and body.position == Vector2(1,-9),id+" retains authored capsule")
		check(area.monitoring == (id == "E01") and not area.monitorable and area.collision_layer == 0 and area.collision_mask == 8,id+" retains sensing contract")
		check(sensor.disabled == (not legacy and id != "E01"),id+" has expected sensor geometry registration")
		records.append({"id":id,"hp":actor.HP,"speed":actor.SPEED,"hurt":actor.hurt,"rng_next":randi(),"children":actor.get_child_count(),"shape":str(body.shape.get_rect())})
		await get_tree().physics_frame
		await get_tree().physics_frame
		check(actor.test_move(actor.global_transform,Vector2(100,0)) and not actor.test_move(actor.global_transform,Vector2(0,-100)),id+" still blocks at a wall and moves through open space")
		check(actor.test_move(actor.global_transform,Vector2(-100,0)),id+" still collides with another live enemy body")
		var query := PhysicsPointQueryParameters2D.new()
		query.position = body.global_position
		query.collision_mask = 1
		var found := false
		for hit in actor.get_world_2d().direct_space_state.intersect_point(query):
			if hit.collider == actor: found = true
		check(found,id+" remains visible to player projectile collision queries")
		if id == "E01":
			actor.global_position = Utils.player.global_position+Vector2(0,8)
			await get_tree().physics_frame
			await get_tree().physics_frame
			check(actor.area_player == Utils.player and actor.is_atk,"E01 real body_entered signal starts melee")
			actor.global_position = origin
			await get_tree().physics_frame
			await get_tree().physics_frame
			check(actor.area_player == null and not actor.is_atk,"E01 real body_exited signal ends contact")
		actor.queue_free()
		await get_tree().process_frame
	barrier.queue_free()
	crowd.queue_free()
	print("WEB_PHYSICS_SNAPSHOT ",JSON.stringify(records))
	print("WEB_PHYSICS_CONTRACTS checks=",checks," failures=",failures)
	if failures: get_tree().quit(1)
	else: await Demo.quit_game()
