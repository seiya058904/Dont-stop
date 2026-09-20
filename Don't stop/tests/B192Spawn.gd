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
	compare(arena,1)
	actor.global_position += Vector2(50,0)
	Utils.player.global_position += Vector2(16,0)
	await get_tree().physics_frame; await get_tree().physics_frame
	compare(arena,2)
	LevelServer.return_to_camp(); dismiss(); await wait(0.1)
	check(get_tree().get_nodes_in_group("monsters").is_empty(),"cache fixture lifecycle drains")
	print("B192_SPAWN checks=",checks," failures=",failures)
	if failures: get_tree().quit(1)
	else: await Demo.quit_game()
