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
## Reusable physics query objects, keyed by quantised radius. See `_query_for()`.
var _queries: Dictionary = {}
## `cells` as a set, so "is this cell walkable" is one lookup instead of a scan.
var _walkable: Dictionary = {}
## Stable empty exclusion, so a query that excludes nothing does not allocate a new Array per call.
var _no_exclusions: Array = []
## The clearance the navigation grid itself was built with. Declared here, next to the rectangle
## margin that encodes it, so the spawn validator's early-out cannot drift away from the grid.
const GRID_CLEARANCE := 7.0
var grid_clearance := GRID_CLEARANCE

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
			if not blocked:
				cells.append(cell)
				_walkable[cell] = true
	z_index = -4
func cell(point: Vector2) -> Vector2i:
	var local = to_local(point); return Vector2i(floori(local.x/float(CELL)),floori(local.y/float(CELL)))
## Nearest WALKABLE grid cell, in bounded time.
##
## This used to scan every walkable cell and compare squared distances: ~677 iterations of a
## `to_local()` plus two `distance_squared_to()` calls per invocation. It is called from `path_step()`
## whenever a monster's own cell reads as solid or out of bounds - which is exactly what a monster
## pressed against a wall does - so the scan ran for a large fraction of the crowd at 5 Hz each, and
## its cost grew with the SQUARE of the enemy count while the arena stayed the same size.
##
## WHAT IT MUST STILL GUARANTEE: the result has to be a cell A* can path OUT of, because three
## callers hand it straight to `get_id_path()`. A clamped-index shortcut is therefore NOT a valid
## replacement - it can return a solid cell, the path query then returns one element, and every
## actor routed through it reads as unreachable. (That mistake was caught by tests/R3SpawnAudit.gd as
## 78 illegal births; do not reintroduce it.)
##
## So the search is bounded instead of removed: the exact cell when it is walkable (the common case,
## one dictionary lookup), and otherwise a ring search over the precomputed `cells` array, which
## costs O(ring circumference) dictionary lookups rather than O(all cells) distance computations. The
## ring radius is capped because a caller that is far outside the walkable set has no nearest cell
## worth finding - `cells[0]` is the documented fallback and is itself walkable.
const NEAREST_RING_MAX := 12

func nearest(point: Vector2) -> Vector2i:
	var local := to_local(point)
	var origin := Vector2i(
		floori((local.x-grid.offset.x)/grid.cell_size.x),
		floori((local.y-grid.offset.y)/grid.cell_size.y))
	if _walkable.has(origin): return origin
	for ring in range(1,NEAREST_RING_MAX+1):
		for dx in range(-ring,ring+1):
			for dy in [-ring,ring]:
				var candidate := origin+Vector2i(dx,dy)
				if _walkable.has(candidate): return candidate
		for dy in range(-ring+1,ring):
			for dx in [-ring,ring]:
				var candidate := origin+Vector2i(dx,dy)
				if _walkable.has(candidate): return candidate
	return cells[0]
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
		# The clearance query is only needed when the actor can be WIDER than the 7 px circle the
		# grid itself was built with. For a default-size enemy the grid's own solid/walkable answer
		# already IS the clearance rule, and re-asking the physics world for every candidate made a
		# single reinforcement cost up to ~677 shape queries. Large actors keep the real check.
		if radius > grid_clearance and not _is_clear(point,radius):
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
		if radius > grid_clearance and not _is_clear(point,radius):
			M5Content.audit_rejected += 1; continue
		spawn_path_queries += 1
		if grid.get_id_path(candidate,target).size() > 1: return point
		M5Content.audit_rejected += 1
	M5Content.audit_arena_failed += 1
	return Vector2.INF

## Reuses the same approach the town navigation builder uses (a circle cast against the
## wall layers) rather than inventing a second, movement-decoupled rule.
##
## The shape and the query object are CACHED per radius. `spawn_near()` calls this once per candidate
## cell, so an uncached version allocated a CircleShape2D and a PhysicsShapeQueryParameters2D up to
## ~677 times for a single reinforcement, at up to two reinforcements per second. Actor radii are a
## small fixed set (one per enemy kind plus a few boss extents), so the cache is bounded by the
## roster, not by the frame rate.
##
## `_is_clear_excluding()` is the same rule with the tested actor's own RID removed: an actor standing
## in a legal spot still intersects its OWN collider, so a caller that re-tests a live actor has to
## exclude it or every unit reads as inside a wall.
func _query_for(radius: float) -> PhysicsShapeQueryParameters2D:
	var key := snappedf(radius,0.01)
	if _queries.has(key): return _queries[key]
	var shape := CircleShape2D.new()
	shape.radius = radius
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = shape
	query.collision_mask = 2147483649
	_queries[key] = query
	return query

func _is_clear(point: Vector2, radius: float) -> bool:
	var space := get_world_2d().direct_space_state
	if space == null: return true
	var query := _query_for(radius)
	query.transform = Transform2D(0,point)
	query.exclude = _no_exclusions
	return space.intersect_shape(query,1).is_empty()

func _is_clear_excluding(point: Vector2, radius: float, rid: RID) -> bool:
	var space := get_world_2d().direct_space_state
	if space == null: return true
	var query := _query_for(radius)
	query.transform = Transform2D(0,point)
	query.exclude = [rid]
	return space.intersect_shape(query,1).is_empty()

## Public clearance probe for the hazard director and the audits, so everything is validated
## by exactly one rule. `exclude` must carry the RID of the actor being tested: an actor
## standing in a legal spot still intersects its OWN collider, and an audit that forgets to
## exclude it reports every unit as "inside a wall".
func point_clear(point: Vector2, radius: float, exclude: Array = [], mask := 2147483649) -> bool:
	var space := get_world_2d().direct_space_state
	if space == null: return true
	var query := _query_for(radius)
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
		# A hazard's clearance is never the default actor radius, so it always takes the real query.
		if extent*0.55+10.0 <= grid_clearance or _is_clear(point,extent*0.55+10.0): return point
	return Vector2.INF
func _draw():
	preload("res://game/map/RegionTheme.gd").draw_arena(self,region_id,bounds,obstacles)
