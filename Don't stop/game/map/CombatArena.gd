extends Node2D
var region_id = "R2"
var path_queries = 0
var spawn_path_queries = 0
var grid = AStarGrid2D.new()
var cells: Array[Vector2i] = []
var obstacles: Array = []
var bounds = Rect2(-384,-288,768,576)
func _ready():
	obstacles = M5Content.WALLS[region_id].duplicate()
	for rect in [Rect2(-400,-304,800,16),Rect2(-400,288,800,16),Rect2(-400,-288,16,576),Rect2(384,-288,16,576)]+obstacles:
		var body = StaticBody2D.new(); body.collision_layer = 2147483648; body.collision_mask = 0
		var shape = CollisionShape2D.new(); var box = RectangleShape2D.new(); box.size = rect.size; shape.shape = box; body.position = rect.get_center(); body.add_child(shape); add_child(body)
	grid.region = Rect2i(-24,-18,48,36); grid.cell_size = Vector2(16,16); grid.offset = Vector2(8,8)
	grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES; grid.update()
	for x in range(-24,24):
		for y in range(-18,18):
			var cell = Vector2i(x,y); var point = grid.get_point_position(cell)
			var blocked = not bounds.grow(-16).has_point(point)
			for rect in obstacles:
				if rect.grow(13).has_point(point): blocked = true
			grid.set_point_solid(cell,blocked)
			if not blocked: cells.append(cell)
	z_index = -4
func cell(point: Vector2) -> Vector2i:
	var local = to_local(point); return Vector2i(floori(local.x/16),floori(local.y/16))
func nearest(point: Vector2) -> Vector2i:
	var result = cells[0]; var best = INF
	for candidate in cells:
		var distance = grid.get_point_position(candidate).distance_squared_to(to_local(point))
		if distance < best: best = distance; result = candidate
	return result
func path_step(from: Vector2, target: Vector2) -> Vector2:
	path_queries+=1
	var a = cell(from); var b = cell(target)
	if not grid.is_in_boundsv(a) or grid.is_point_solid(a): a = nearest(from)
	if not grid.is_in_boundsv(b) or grid.is_point_solid(b): b = nearest(target)
	var path = grid.get_point_path(a,b)
	return to_global(path[1]) if path.size()>1 else to_global(grid.get_point_position(b))
func spawn_near(center: Vector2, minimum: float, maximum: float, side = -1, radius := 7.0) -> Vector2:
	var target = cell(Utils.player.global_position)
	# Player collision permits wall-adjacent positions outside the conservative AI grid.
	# Use the closest reachable target cell, never cancel all reinforcement there.
	if not grid.is_in_boundsv(target) or grid.is_point_solid(target): target=nearest(Utils.player.global_position)
	var offset = randi()%cells.size()
	for i in cells.size():
		var candidate = cells[(offset+i)%cells.size()]; var point = to_global(grid.get_point_position(candidate)); var relative = point-center
		if relative.length() < minimum or relative.length() > maximum or point.distance_to(Utils.player.global_position)<55: continue
		if side >= 0 and relative.dot(Vector2.RIGHT.rotated(side*PI/2)) < relative.length()*0.35: continue
		# The grid above is built from two rectangle tests on the cell CENTRE, with a
		# fixed 13 px margin that has nothing to do with how big the actor really is.
		# Ask the physics world instead, using the actor's own radius, so a large
		# elite or boss is not placed with its collider inside a wall.
		if not _is_clear(point,radius): continue
		spawn_path_queries+=1
		if grid.get_id_path(candidate,target).size()>1: return point
	return Vector2.INF

## Reuses the same approach the town navigation builder uses (a circle cast against
## the wall layers) rather than inventing a second, movement-decoupled rule.
func _is_clear(point: Vector2, radius: float) -> bool:
	var space := get_world_2d().direct_space_state
	if space == null: return true
	var shape := CircleShape2D.new()
	shape.radius = radius
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = shape
	query.collision_mask = 2147483649
	query.transform = Transform2D(0,point)
	return space.intersect_shape(query,1).is_empty()
func _draw():
	preload("res://game/map/RegionTheme.gd").draw_arena(self,region_id,bounds,obstacles)
