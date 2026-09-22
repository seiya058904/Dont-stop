extends Node2D
var region_id = "R2"
var path_queries = 0
var spawn_path_queries = 0
var spawn_path_checks = 0
var spawn_path_cache_hits = 0
var spawn_path_reachable = 0
var spawn_path_rejected = 0
var spawn_geometry_rejected = 0
var spawn_clearance_queries = 0
var spawn_clearance_rejected = 0
var spawn_requests = 0
var grid = AStarGrid2D.new()
var cells: Array[Vector2i] = []
var obstacles: Array = []
## 768x576 -> 880x660 (+14.6% on each axis). The user asked for roughly +12-18% and for the
## change to be a real re-layout, not a scene-wide scale: every dependent system below
## (grid region, border walls, obstacle table, spawn ring, boss ring, hazard anchors,
## navigation) is updated with it, and R1's camp is deliberately untouched.
var bounds = Rect2(-440,-330,880,660)
const CELL := 16
const SPAWN_GEOMETRY_BIN_SIZE := 64.0
const GRID_ORIGIN := Vector2i(-28,-21)
const GRID_SIZE := Vector2i(56,42)
const CLEAR_MASK := 2147483649
const DYNAMIC_CLEAR_MASK := 1
const WALL_MASK := 2147483648
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
var _spawn_points := PackedVector2Array()
var _spawn_transform := Transform2D()
var _spawn_geometry_key: Array = []
var _spawn_geometry := PackedByteArray()
var _spawn_geometry_bins: Dictionary = {}
var _spawn_valid_indices := PackedInt32Array()
var _spawn_wall_clearance_sq := PackedFloat32Array()
var _wall_rects: Array = []
var _static_wall_fast_path := false
## The grid topology is built once in _ready() and has no runtime solid-point
## updates. Cache only this static connectivity result; geometry, physics
## clearance, dynamic occupancy and the caller's random candidate order remain
## per-request checks. If the arena ever mutates the grid, this cache must be
## cleared at the same mutation site.
var _spawn_reachability: Dictionary = {}
var _spawn_batch_depth := 0
var _spawn_batch_failed: Dictionary = {}
var spawn_failed_cache_hits := 0

## Only bracket synchronous birth-only loops: no movement, removals or awaits.
## Occupancy can only increase, so an exhausted search stays exhausted. Never
## cache a successful point; every birth must still check current occupancy.
func begin_spawn_batch() -> void:
	if _spawn_batch_depth == 0: _spawn_batch_failed.clear()
	_spawn_batch_depth += 1

func end_spawn_batch() -> void:
	_spawn_batch_depth -= 1
	if _spawn_batch_depth == 0: _spawn_batch_failed.clear()

func _spawn_failure_key(radius: float) -> Array:
	return [_spawn_geometry_key.duplicate(),_spawn_transform,radius,Engine.get_physics_frames()]

func _prepare_spawn_geometry(center: Vector2, minimum: float, maximum: float, side: int) -> void:
	if _spawn_points.size() != cells.size() or _spawn_transform != global_transform:
		_spawn_transform = global_transform
		_spawn_points.clear()
		_spawn_geometry_bins.clear()
		_spawn_valid_indices = PackedInt32Array()
		_spawn_wall_clearance_sq.resize(cells.size())
		_static_wall_fast_path = is_equal_approx(global_transform.x.length(),1.0) \
			and is_equal_approx(global_transform.y.length(),1.0) \
			and is_zero_approx(global_transform.x.dot(global_transform.y))
		for candidate in cells:
			var index := _spawn_points.size()
			var point := to_global(grid.get_point_position(candidate))
			_spawn_points.append(point)
			_spawn_wall_clearance_sq[index] = _static_wall_clearance_sq(point) if _static_wall_fast_path else -1.0
			var bin := _spawn_geometry_bin(point)
			var bucket: Array = _spawn_geometry_bins.get(bin,[])
			bucket.append(index)
			_spawn_geometry_bins[bin] = bucket
		_spawn_geometry.resize(cells.size())
		_spawn_geometry_key.clear()
	var key: Array = [center,Utils.player.global_position,minimum,maximum,side]
	if key != _spawn_geometry_key:
		_spawn_geometry_key = key
		# Mark the complete candidate order as not-yet-tested, then leave only bins that can
		# intersect the requested maximum radius untested. `_spawn_geometry_allows()` still runs
		# the exact old distance/player/side predicates for those bins; this only removes work for
		# cells that are mathematically outside the annulus and cannot be selected.
		_spawn_geometry.fill(2)
		var origin := _spawn_geometry_bin(center)
		var span := ceili(maximum/SPAWN_GEOMETRY_BIN_SIZE)+1
		for bx in range(-span,span+1):
			for by in range(-span,span+1):
				for index in _spawn_geometry_bins.get(origin+Vector2i(bx,by),[]):
					_spawn_geometry[index] = 0
		_spawn_valid_indices.resize(cells.size())
		var valid_count := 0
		for index in cells.size():
			if _spawn_geometry_allows(index,center,minimum,maximum,side):
				_spawn_valid_indices[valid_count] = index
				valid_count += 1
		_spawn_valid_indices.resize(valid_count)

func _spawn_valid_start(offset: int) -> int:
	# `_spawn_valid_indices` is in the same order as `cells`. Find the first valid
	# index at or after the original random offset, then wrap. This is exactly the
	# order produced by the old full-cell loop, without visiting every rejected cell.
	var low := 0
	var high := _spawn_valid_indices.size()
	while low < high:
		var middle: int = (low+high)>>1
		if _spawn_valid_indices[middle] < offset: low = middle+1
		else: high = middle
	return low

func _spawn_geometry_bin(point: Vector2) -> Vector2i:
	return Vector2i(floori(point.x/SPAWN_GEOMETRY_BIN_SIZE),floori(point.y/SPAWN_GEOMETRY_BIN_SIZE))

func _static_wall_clearance_sq(point: Vector2) -> float:
	var local := to_local(point)
	var nearest := INF
	for raw_rect in _wall_rects:
		var rect: Rect2 = raw_rect
		var end := rect.position+rect.size
		var dx := maxf(maxf(rect.position.x-local.x,0.0),local.x-end.x)
		var dy := maxf(maxf(rect.position.y-local.y,0.0),local.y-end.y)
		nearest = minf(nearest,dx*dx+dy*dy)
	return nearest

func static_line_may_hit(from: Vector2, to: Vector2) -> bool:
	# Combat.clear_line excludes every dynamic actor, so inside an unchanged arena the
	# only possible hit is one of these static rectangles. An AABB miss is a proof that
	# the segment cannot touch a wall; ambiguous overlaps still use the exact physics ray.
	if not _static_wall_fast_path: return true
	var local_from := to_local(from)
	var local_to := to_local(to)
	if not bounds.grow(16.0).has_point(local_from) or not bounds.grow(16.0).has_point(local_to): return true
	var min_x := minf(local_from.x,local_to.x)
	var max_x := maxf(local_from.x,local_to.x)
	var min_y := minf(local_from.y,local_to.y)
	var max_y := maxf(local_from.y,local_to.y)
	for raw_rect in _wall_rects:
		var rect: Rect2 = raw_rect
		if max_x < rect.position.x or min_x > rect.end.x: continue
		if max_y < rect.position.y or min_y > rect.end.y: continue
		return true
	return false

func _spawn_geometry_allows(index: int, center: Vector2, minimum: float, maximum: float, side: int) -> bool:
	# Only immutable ring/arc arithmetic is reused between synchronous births.
	# Dynamic occupancy, actor clearance and connectivity are always re-queried.
	if _spawn_geometry[index] != 0: return _spawn_geometry[index] == 1
	var point := _spawn_points[index]
	var relative := point-center
	var distance := relative.length()
	var valid := distance >= minimum and distance <= maximum and point.distance_to(Utils.player.global_position) >= 55
	if valid and side >= 0: valid = relative.dot(Vector2.RIGHT.rotated(side*PI/2)) >= distance*0.35
	_spawn_geometry[index] = 1 if valid else 2
	return valid

func _spawn_reachable(candidate: Vector2i, target: Vector2i) -> bool:
	spawn_path_checks += 1
	if B11Probe.enabled and not B11Probe.spawn_reachability_cache:
		var uncached_started := Time.get_ticks_usec()
		spawn_path_queries += 1
		var uncached_reachable: bool = grid.get_id_path(candidate,target).size() > 1
		B11Probe.cost("spawn_path",uncached_started)
		if uncached_reachable: spawn_path_reachable += 1
		else: spawn_path_rejected += 1
		return uncached_reachable
	var target_cache: Dictionary = _spawn_reachability.get(target,{})
	if target_cache.has(candidate):
		spawn_path_cache_hits += 1
		var cached: bool = bool(target_cache[candidate])
		if cached: spawn_path_reachable += 1
		else: spawn_path_rejected += 1
		return cached
	var started := Time.get_ticks_usec() if B11Probe.enabled else 0
	spawn_path_queries += 1
	var reachable: bool = grid.get_id_path(candidate,target).size() > 1
	if B11Probe.enabled: B11Probe.cost("spawn_path",started)
	target_cache[candidate] = reachable
	_spawn_reachability[target] = target_cache
	if reachable: spawn_path_reachable += 1
	else: spawn_path_rejected += 1
	return reachable

func _ready():
	obstacles = M5Content.WALLS[region_id].duplicate()
	var wall_rects: Array = [Rect2(-456,-346,912,16),Rect2(-456,330,912,16),Rect2(-456,-346,16,692),Rect2(440,-346,16,692)]+obstacles
	_wall_rects = wall_rects
	_static_wall_fast_path = is_equal_approx(global_transform.x.length(),1.0) \
		and is_equal_approx(global_transform.y.length(),1.0) \
		and is_zero_approx(global_transform.x.dot(global_transform.y))
	for rect in wall_rects:
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
	# B11.2 test-only timer (game/diag/B11Probe.gd). `path_queries` alone cannot say whether the
	# crowd's A* share is 1% of the frame or 20%; this is the number that decides it.
	var t0 := 0
	if B11Probe.enabled: t0 = Time.get_ticks_usec()
	var a = cell(from); var b = cell(target)
	if not grid.is_in_boundsv(a) or grid.is_point_solid(a): a = nearest(from)
	if not grid.is_in_boundsv(b) or grid.is_point_solid(b): b = nearest(target)
	var path = grid.get_point_path(a,b)
	if B11Probe.enabled: B11Probe.path_usec += Time.get_ticks_usec()-t0
	return to_global(path[1]) if path.size()>1 else to_global(grid.get_point_position(b))
func spawn_near(center: Vector2, minimum: float, maximum: float, side = -1, radius := -1.0) -> Vector2:
	spawn_requests += 1
	# A negative radius means "the actor's own size". Every enemy instantiates the
	# same body, so the scene is the source of truth and a caller that forgets to
	# pass a radius still gets a real clearance instead of the old fixed 7 px that
	# let capsule-shaped bodies be created inside walls.
	if radius <= 0.0: radius = M5Content.default_radius()
	var target = cell(Utils.player.global_position)
	# Player collision permits wall-adjacent positions outside the conservative AI grid.
	# Use the closest reachable target cell, never cancel all reinforcement there.
	if not grid.is_in_boundsv(target) or grid.is_point_solid(target): target=nearest(Utils.player.global_position)
	_prepare_spawn_geometry(center,minimum,maximum,int(side))
	var offset = randi()%cells.size()
	var valid_count := _spawn_valid_indices.size()
	M5Content.audit_candidates += cells.size()
	var geometry_rejected := cells.size()-valid_count
	spawn_geometry_rejected += geometry_rejected
	M5Content.audit_rejected += geometry_rejected
	var valid_start := _spawn_valid_start(offset)
	var failure_key := _spawn_failure_key(radius) if _spawn_batch_depth > 0 else []
	if _spawn_batch_failed.has(failure_key):
		spawn_failed_cache_hits += 1
		M5Content.audit_rejected += valid_count
		M5Content.audit_arena_failed += 1
		return Vector2.INF
	for i in valid_count:
		var index: int = _spawn_valid_indices[(valid_start+i)%valid_count]
		var candidate = cells[index]; var point = _spawn_points[index]
		# The grid above is built from two rectangle tests on the cell CENTRE, with a
		# fixed 13 px margin that has nothing to do with how big the actor really is.
		# Ask the physics world instead, using the actor's own radius, so a large
		# elite or boss is not placed with its collider inside a wall.
		# The clearance query is only needed when the actor can be WIDER than the 7 px circle the
		# grid itself was built with. For a default-size enemy the grid's own solid/walkable answer
		# already IS the clearance rule, and re-asking the physics world for every candidate made a
		# single reinforcement cost up to ~677 shape queries. Large actors keep the real check.
		if radius > grid_clearance and not _spawn_clear(index,point,radius):
			M5Content.audit_rejected += 1; continue
		if _spawn_reachable(candidate,target):
			return point
		M5Content.audit_rejected += 1
	M5Content.audit_arena_failed += 1
	if _spawn_batch_depth > 0: _spawn_batch_failed[failure_key] = true
	return Vector2.INF

## Reachable reinforcement from the far side of the arena, for Hell Mode's multi-direction
## arrivals. Same validation rules as spawn_near(); only the arc is different, so a flank
## wave cannot smuggle an illegal point past the audit.
func spawn_flank(center: Vector2, minimum: float, maximum: float, radius := -1.0) -> Vector2:
	spawn_requests += 1
	if radius <= 0.0: radius = M5Content.default_radius()
	var target = cell(Utils.player.global_position)
	if not grid.is_in_boundsv(target) or grid.is_point_solid(target): target = nearest(Utils.player.global_position)
	_prepare_spawn_geometry(center,minimum,maximum,-1)
	var offset = randi()%cells.size()
	var valid_count := _spawn_valid_indices.size()
	M5Content.audit_candidates += cells.size()
	var geometry_rejected := cells.size()-valid_count
	spawn_geometry_rejected += geometry_rejected
	M5Content.audit_rejected += geometry_rejected
	var valid_start := _spawn_valid_start(offset)
	var failure_key := _spawn_failure_key(radius) if _spawn_batch_depth > 0 else []
	if _spawn_batch_failed.has(failure_key):
		spawn_failed_cache_hits += 1
		M5Content.audit_rejected += valid_count
		M5Content.audit_arena_failed += 1
		return Vector2.INF
	for i in valid_count:
		var index: int = _spawn_valid_indices[(valid_start+i)%valid_count]
		var candidate = cells[index]
		var point = _spawn_points[index]
		if radius > grid_clearance and not _spawn_clear(index,point,radius):
			M5Content.audit_rejected += 1; continue
		if _spawn_reachable(candidate,target):
			return point
		M5Content.audit_rejected += 1
	M5Content.audit_arena_failed += 1
	if _spawn_batch_depth > 0: _spawn_batch_failed[failure_key] = true
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
	query.collision_mask = CLEAR_MASK
	_queries[key] = query
	return query

func _is_clear(point: Vector2, radius: float) -> bool:
	var space := get_world_2d().direct_space_state
	if space == null: return true
	var query := _query_for(radius)
	query.collision_mask = CLEAR_MASK
	query.transform = Transform2D(0,point)
	query.exclude = _no_exclusions
	return space.intersect_shape(query,1).is_empty()

func _is_clear_dynamic(point: Vector2, radius: float) -> bool:
	var space := get_world_2d().direct_space_state
	if space == null: return true
	var query := _query_for(radius)
	query.collision_mask = DYNAMIC_CLEAR_MASK
	query.transform = Transform2D(0,point)
	query.exclude = _no_exclusions
	return space.intersect_shape(query,1).is_empty()

func _spawn_clear(index: int, point: Vector2, radius: float) -> bool:
	# Static arena rectangles are immutable after _ready(). Reject a candidate that is
	# definitely inside one without entering PhysicsServer2D; only the dynamic occupancy
	# query remains. If the arena is transformed in a non-orthonormal way, retain the old
	# combined query because the local rectangle distance is no longer exact in world space.
	if _static_wall_fast_path and _spawn_wall_clearance_sq[index] < radius*radius:
		spawn_clearance_rejected += 1
		return false
	spawn_clearance_queries += 1
	var clearance_started := Time.get_ticks_usec() if B11Probe.enabled else 0
	var clear := _is_clear_dynamic(point,radius) if _static_wall_fast_path else _is_clear(point,radius)
	if B11Probe.enabled: B11Probe.cost("spawn_clearance",clearance_started)
	if not clear: spawn_clearance_rejected += 1
	return clear

func _is_clear_excluding(point: Vector2, radius: float, rid: RID) -> bool:
	var space := get_world_2d().direct_space_state
	if space == null: return true
	var query := _query_for(radius)
	query.collision_mask = CLEAR_MASK
	query.transform = Transform2D(0,point)
	query.exclude = [rid]
	return space.intersect_shape(query,1).is_empty()

## Public clearance probe for the hazard director and the audits, so everything is validated
## by exactly one rule. `exclude` must carry the RID of the actor being tested: an actor
## standing in a legal spot still intersects its OWN collider, and an audit that forgets to
## exclude it reports every unit as "inside a wall".
func point_clear(point: Vector2, radius: float, exclude: Array = [], mask := CLEAR_MASK) -> bool:
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
