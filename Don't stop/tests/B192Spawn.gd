extends "res://tests/M8Runtime.gd"

## Frozen pre-cache selection algorithm, against the same live physics world.
func reference(arena,center: Vector2,minimum: float,maximum: float,side: int,radius: float) -> Vector2:
	var target = arena.cell(Utils.player.global_position)
	if not arena.grid.is_in_boundsv(target) or arena.grid.is_point_solid(target): target = arena.nearest(Utils.player.global_position)
	var offset = randi()%arena.cells.size()
	for i in arena.cells.size():
		var candidate = arena.cells[(offset+i)%arena.cells.size()]
		var point = arena.to_global(arena.grid.get_point_position(candidate))
		var relative = point-center
		if relative.length()<minimum or relative.length()>maximum or point.distance_to(Utils.player.global_position)<55: continue
		if side>=0 and relative.dot(Vector2.RIGHT.rotated(side*PI/2))<relative.length()*0.35: continue
		if radius>arena.grid_clearance and not arena._is_clear(point,radius): continue
		if arena.grid.get_id_path(candidate,target).size()>1: return point
	return Vector2.INF

func compare(arena,round_id: int) -> void:
	for side in [-1,0,1,2,3]:
		for sample in 8:
			var test_seed = 20260920+sample
			var center: Vector2 = Utils.player.global_position
			var radius = M5Content.default_radius()*(2.2 if sample%3==0 else 1.0)
			seed(test_seed)
			var expected = reference(arena,center,108,280,side,radius)
			var next_random = randi()
			seed(test_seed)
			var actual = arena.spawn_flank(center,108,280,radius) if side==-1 else arena.spawn_near(center,108,280,side,radius)
			check(actual==expected and randi()==next_random,"spawn selection/RNG round %d side %d sample %d"%[round_id,side,sample])

func _ready():
	await boot(); configure(112,true)
	LevelServer.return_to_camp(); dismiss(); await wait(0.1)
	LevelServer.town.depart(39,true); LevelServer.timerStop(); await clean()
	var arena = LevelServer.town.arena
	Utils.player.set_physics_process(false)
	Utils.player.global_position = arena.global_position
	compare(arena,0)
	# Occupancy changes must never use a previously clear cached physics result.
	seed(20260920)
	var point = arena.spawn_near(Utils.player.global_position,108,280,0,M5Content.default_radius())
	var actor = M5Content.spawn("E01",LevelServer.town.monster_root,point)
	actor.set_physics_process(false)
	await get_tree().physics_frame; await get_tree().physics_frame
	var actor_rid: RID = actor.get_rid()
	var actor_point: Vector2 = actor.global_position
	# The cached query object is intentionally shared by radius. A wall-only probe must
	# not poison the following ordinary occupancy probe, and excluding the actor must
	# not poison the following non-excluding probe.
	check(arena.point_clear(actor_point,M5Content.default_radius(),[],arena.WALL_MASK),
		"wall-only probe sees the live actor position as wall-clear")
	check(not arena._is_clear(actor_point,M5Content.default_radius()),
		"ordinary clearance still sees an actor after a wall-only probe")
	check(arena._is_clear_excluding(actor_point,M5Content.default_radius(),actor_rid),
		"excluding the tested actor leaves its legal position clear")
	check(not arena._is_clear(actor_point,M5Content.default_radius()),
		"ordinary clearance clears the self-exclusion after the excluding probe")
	check(not arena.point_clear(actor_point,M5Content.default_radius(),[],arena.CLEAR_MASK),
		"ordinary public probe still sees the live actor after reverse mask order")
	var wall_point: Vector2 = arena.to_global(arena.obstacles[0].get_center())
	check(not arena.point_clear(wall_point,4.0,[],arena.WALL_MASK),
		"wall-only probe independently detects a real arena wall")
	compare(arena,1)
	actor.global_position += Vector2(50,0)
	Utils.player.global_position += Vector2(16,0)
	await get_tree().physics_frame; await get_tree().physics_frame
	compare(arena,2)
	# An exhausted birth-only batch must preserve selection and RNG while avoiding
	# repeated queries. A new batch must observe an obstruction being removed.
	var blocker := StaticBody2D.new()
	blocker.collision_layer = 1; blocker.collision_mask = 0
	var collider := CollisionShape2D.new()
	var box := RectangleShape2D.new(); box.size = Vector2(1200,1000)
	collider.shape = box; blocker.add_child(collider); arena.add_child(blocker)
	await get_tree().physics_frame; await get_tree().physics_frame
	arena.begin_spawn_batch()
	var center: Vector2 = Utils.player.global_position
	var radius := M5Content.default_radius()
	var after_first_queries := 0
	var before_hits: int = arena.spawn_failed_cache_hits
	for sample in 3:
		seed(922200+sample)
		var expected := reference(arena,center,108,280,0,radius)
		var next_random := randi()
		seed(922200+sample)
		if sample == 1: arena.begin_spawn_batch()
		var actual: Vector2 = arena.spawn_near(center,108,280,0,radius)
		if sample == 1: arena.end_spawn_batch()
		check(actual == Vector2.INF and actual == expected and randi() == next_random,"exhausted batch preserves failure and RNG")
		if sample == 0: after_first_queries = arena.spawn_clearance_queries
		else: check(arena.spawn_clearance_queries == after_first_queries,"same batch reuses exhausted search")
	check(arena.spawn_failed_cache_hits-before_hits == 2,"both repeated failures reused")
	arena.end_spawn_batch()
	blocker.queue_free()
	await get_tree().physics_frame; await get_tree().physics_frame
	arena.begin_spawn_batch()
	seed(922200)
	var expected := reference(arena,center,108,280,0,radius)
	var next_random := randi()
	seed(922200)
	var actual: Vector2 = arena.spawn_near(center,108,280,0,radius)
	check(actual.is_finite() and actual == expected and randi() == next_random,"new batch sees freed space with original selection and RNG")
	arena.end_spawn_batch()
	LevelServer.return_to_camp(); dismiss(); await wait(0.1)
	check(get_tree().get_nodes_in_group("monsters").is_empty(),"cache fixture lifecycle drains")
	print("B192_SPAWN checks=",checks," failures=",failures)
	if failures: get_tree().quit(1)
	else: await Demo.quit_game()
