extends Node2D
var region_id = "R2"
var path_queries = 0
var spawn_path_queries = 0
var grid = AStarGrid2D.new()
var cells: Array[Vector2i] = []
var obstacles: Array = []
## 768x576 -> 880x660 (+14.6% on each axis). The user asked for roughly +12-18% and for the
## change to be a real re-layout, not a scene-wide scale: every dependent system below
## (grid region, border walls, obstacle table, spawn ring, boss ring, hazard anchors,
## navigation) is updated with it, and R1's camp is deliberately untouched.
var bounds = Rect2(-440,-330,880,660)
const CELL := 16
const GRID_ORIGIN := Vector2i(-28,-21)
const GRID_SIZE := Vector2i(56,42)
func _ready():
	obstacles = M5Content.WALLS[region_id].duplicate()
	for rect in [Rect2(-456,-346,912,16),Rect2(-456,330,912,16),Rect2(-456,-346,16,692),Rect2(440,-346,16,692)]+obstacles:
		var body = StaticBody2D.new(); body.collision_layer = 2147483648; body.collision_mask = 0
		var shape = CollisionShape2D.new(); var box = RectangleShape2D.new(); box.size = rect.size; shape.shape = box; body.position = rect.get_center(); body.add_child(shape); add_child(body)
	grid.region = Rect2i(GRID_ORIGIN,GRID_SIZE); grid.cell_size = Vector2(CELL,CELL); grid.offset = Vector2(CELL*0.5,CELL*0.5)
	grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES; grid.update()
	for x in range(GRID_ORIGIN.x,GRID_ORIGIN.x+GRID_SIZE.x):
		for y in range(GRID_ORIGIN.y,GRID_ORIGIN.y+GRID_SIZE.y):
			var cell = Vector2i(x,y); var point = grid.get_point_position(cell)
			var blocked = not bounds.grow(-16).has_point(point)
			for rect in obstacles:
				if rect.grow(13).has_point(point): blocked = true
			grid.set_point_solid(cell,blocked)
			if not blocked: cells.append(cell)
	z_index = -4
func cell(point: Vector2) -> Vector2i:
	var local = to_local(point); return Vector2i(floori(local.x/float(CELL)),floori(local.y/float(CELL)))
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
func spawn_near(center: Vector2, minimum: float, maximum: float, side = -1, radius := -1.0) -> Vector2:
	# A negative radius means "the actor's own size". Every enemy instantiates the
	# same body, so the scene is the source of truth and a caller that forgets to
	# pass a radius still gets a real clearance instead of the old fixed 7 px that
	# let capsule-shaped bodies be created inside walls.
	if radius <= 0.0: radius = M5Content.default_radius()
	var target = cell(Utils.player.global_position)
	# Player collision permits wall-adjacent positions outside the conservative AI grid.
	# Use the closest reachable target cell, never cancel all reinforcement there.
	if not grid.is_in_boundsv(target) or grid.is_point_solid(target): target=nearest(Utils.player.global_position)
	var offset = randi()%cells.size()
	for i in cells.size():
		var candidate = cells[(offset+i)%cells.size()]; var point = to_global(grid.get_point_position(candidate)); var relative = point-center
		M5Content.audit_candidates += 1
		if relative.length() < minimum or relative.length() > maximum or point.distance_to(Utils.player.global_position)<55:
			M5Content.audit_rejected += 1; continue
		if side >= 0 and relative.dot(Vector2.RIGHT.rotated(side*PI/2)) < relative.length()*0.35:
			M5Content.audit_rejected += 1; continue
		# The grid above is built from two rectangle tests on the cell CENTRE, with a
		# fixed 13 px margin that has nothing to do with how big the actor really is.
		# Ask the physics world instead, using the actor's own radius, so a large
		# elite or boss is not placed with its collider inside a wall.
		if not _is_clear(point,radius):
			M5Content.audit_rejected += 1; continue
		spawn_path_queries+=1
		if grid.get_id_path(candidate,target).size()>1: return point
		M5Content.audit_rejected += 1
	M5Content.audit_arena_failed += 1
	return Vector2.INF

## Reachable reinforcement from the far side of the arena, for Hell Mode's multi-direction
## arrivals. Same validation rules as spawn_near(); only the arc is different, so a flank
## wave cannot smuggle an illegal point past the audit.
func spawn_flank(center: Vector2, minimum: float, maximum: float, radius := -1.0) -> Vector2:
	if radius <= 0.0: radius = M5Content.default_radius()
	var target = cell(Utils.player.global_position)
	if not grid.is_in_boundsv(target) or grid.is_point_solid(target): target = nearest(Utils.player.global_position)
	var offset = randi()%cells.size()
	for i in cells.size():
		var candidate = cells[(offset+i)%cells.size()]
		var point = to_global(grid.get_point_position(candidate))
		var relative = point-center
		M5Content.audit_candidates += 1
		if relative.length() < minimum or relative.length() > maximum or point.distance_to(Utils.player.global_position) < 55:
			M5Content.audit_rejected += 1; continue
		if not _is_clear(point,radius):
			M5Content.audit_rejected += 1; continue
		spawn_path_queries += 1
		if grid.get_id_path(candidate,target).size() > 1: return point
		M5Content.audit_rejected += 1
	M5Content.audit_arena_failed += 1
	return Vector2.INF

## Reuses the same approach the town navigation builder uses (a circle cast against the
## wall layers) rather than inventing a second, movement-decoupled rule.
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

## Public clearance probe for the hazard director and the audits, so everything is validated
## by exactly one rule. `exclude` must carry the RID of the actor being tested: an actor
## standing in a legal spot still intersects its OWN collider, and an audit that forgets to
## exclude it reports every unit as "inside a wall".
func point_clear(point: Vector2, radius: float, exclude: Array = [], mask := 2147483649) -> bool:
	var space := get_world_2d().direct_space_state
	if space == null: return true
	var shape := CircleShape2D.new()
	shape.radius = radius
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = shape
	# The default mask includes bit 0, which is where monsters (collision_layer 3) and the
	# player (25) live, so it answers "is this spot free". Mask 2147483648 (the arena's wall
	# layer) answers "is this spot inside geometry", which is what a wall-overlap audit means.
	query.collision_mask = mask
	query.transform = Transform2D(0,point)
	query.exclude = exclude
	return space.intersect_shape(query,1).is_empty()

## Walkable area in square world pixels, measured from the actual navigation cells rather
## than from bounds arithmetic, so the hazard coverage budget is a share of real floor.
func walkable_area() -> float:
	return float(cells.size())*float(CELL*CELL)

func reachable_from_player(point: Vector2) -> bool:
	var target = cell(Utils.player.global_position)
	if not grid.is_in_boundsv(target) or grid.is_point_solid(target): target = nearest(Utils.player.global_position)
	var here = cell(point)
	if not grid.is_in_boundsv(here) or grid.is_point_solid(here): here = nearest(point)
	return grid.get_id_path(here,target).size() > 1

## Any legal walkable cell that fits `extent`.
func hazard_point(extent: float) -> Vector2:
	if cells.is_empty(): return Vector2.INF
	var offset_index = randi()%cells.size()
	for i in cells.size():
		var candidate = cells[(offset_index+i)%cells.size()]
		var point = to_global(grid.get_point_position(candidate))
		if _is_clear(point,extent*0.55+10.0): return point
	return Vector2.INF
func _draw():
	preload("res://game/map/RegionTheme.gd").draw_arena(self,region_id,bounds,obstacles)
