extends "res://tests/M8Runtime.gd"

func _ready():
	await boot()
	dismiss()
	var builder_script = preload("res://game/map/ArenaMesh.gd")
	var builder = builder_script.new()
	builder.draw_rect(Rect2(2,3,8,6),Color.RED)
	builder.draw_rect(Rect2(4,4,3,2),Color(0,1,0,0.5))
	var arrays = builder.finish().surface_get_arrays(0)
	check(arrays[Mesh.ARRAY_VERTEX].size() == 8,"mesh keeps four vertices per filled rectangle")
	check(arrays[Mesh.ARRAY_VERTEX][0] == Vector3(2,3,0) and arrays[Mesh.ARRAY_VERTEX][2] == Vector3(10,9,0),"mesh preserves exact world coordinates")
	var translucent: Color = arrays[Mesh.ARRAY_COLOR][4]
	# Mesh colours are packed to RGBA8 by Godot; half alpha round-trips as 128/255.
	check(arrays[Mesh.ARRAY_INDEX][6] == 4 and translucent.g == 1.0 and absf(translucent.a-0.5) <= 1.0/255.0,"translucent primitives retain painter order and alpha")
	for region in RegionTheme.FLOOR:
		seed(20260929)
		var expected := randi()
		seed(20260929)
		var first = builder_script.new()
		RegionTheme.draw_arena(first,region,Rect2(-440,-330,880,660),M5Content.WALLS[region])
		check(randi() == expected,region+" art does not consume gameplay RNG")
		var second = builder_script.new()
		RegionTheme.draw_arena(second,region,Rect2(-440,-330,880,660),M5Content.WALLS[region])
		check(first.vertices == second.vertices and first.colors == second.colors and first.indices == second.indices,region+" art is deterministic")
		var valid: bool = not first.indices.is_empty() and first.indices.size()%3==0
		for index in first.indices:
			if index < 0 or index >= first.vertices.size(): valid = false
		for point in first.vertices:
			if not point.is_finite(): valid = false
		check(valid,region+" mesh has finite indexed triangles")
		check(first.finish().get_surface_count() == 1,region+" static arena uses one mesh surface")
	configure(0,false)
	LevelServer.town.depart(39,true)
	LevelServer.timerStop()
	var actor = M5Content.spawn("E01",LevelServer.town.monster_root,Vector2(60,60))
	check(actor.get_node("UndeadShadow").z_index == -2,"contact shadows are below actors and warnings")
	var feedback = load("res://ui/widgets/HitLabel.tscn").instantiate()
	actor.add_child(feedback)
	check(not feedback.z_as_relative and feedback.z_index == 8,"feedback stays above actors independent of parent depth")
	actor.queue_free()
	await wait(1.1)
	check(not is_instance_valid(feedback),"batched feedback retains parent-owned cleanup")
	stop()
	print("DEEP_PRESENTATION checks=",checks," failures=",failures)
	if failures: get_tree().quit(1)
	else: await Demo.quit_game()
