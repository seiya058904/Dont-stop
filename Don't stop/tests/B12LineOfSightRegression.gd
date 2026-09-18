extends "res://tests/M8Runtime.gd"
## B12 line-of-sight regression: pins the exact timing that broke the reusable
## clear_line query and forces the fixed behaviour to hold under real actor churn.
##
## The bug (B11.1 -> B12): Combat._clear_line_query reused ONE
## PhysicsRayQueryParameters2D and re-mirrored its exclude list only when the
## shared exclusions_dirty flag was still set. game/effects/CombatFootprint.gd
## consumes that same flag for its own throwaway queries, so the sequence
##   actor set changes -> exclusions_dirty = true -> footprint refreshes
##   actor_exclusions and clears the flag -> clear_line called
## left the reused query's exclude list holding the PREVIOUS actor set (or, on a
## fresh query, nothing at all). The ray then hit the current target itself -
## layer bit 0 is shared by player, monsters and walls - and every LOS-gated
## attack (explosion / cone / thermal / rocket) whiffed until the next spawn.
## The fix mirrors the exclude list on EVERY call; this test proves that under
## the exact breaking order, and proves freed RIDs from a churned actor cannot
## pollute the reused query, and that a real wall still blocks the ray.

const FIELD := Vector2(30000, -6000)  # far outside the town tilemap: no incidental geometry

func wall_at(point: Vector2) -> StaticBody2D:
	var body := StaticBody2D.new()
	body.collision_layer = 1          # bit 0: inside CLEAR_LINE_MASK (2147483649)
	body.collision_mask = 0
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(40, 160)
	shape.shape = rect
	body.add_child(shape)
	body.global_position = point
	LevelServer.town.add_child(body)
	return body

func spawn_chaser(point: Vector2):
	var actor = M5Content.spawn("E01", LevelServer.town.monster_root, point)
	return actor

func _ready():
	await boot()
	# --- an empty, deterministic field ------------------------------------------------
	for monster in get_tree().get_nodes_in_group("monsters"): monster.free()
	Combat.exclusions_dirty = true
	Utils.player.global_position = FIELD
	Utils.player.velocity = Vector2.ZERO
	for i in 3: await get_tree().physics_frame
	# --- step 1-6: the exact breaking order -------------------------------------------
	var a = spawn_chaser(FIELD + Vector2(200, 0))
	check(a != null,"monster A spawned")
	for i in 2: await get_tree().physics_frame
	var rid_a: RID = a.get_rid()
	Combat.exclusions_dirty = true                       # actor set changed
	CombatFootprint.polygon(Utils.player.global_position, 100.0)  # the REAL consumer path
	check(Combat.exclusions_dirty == false,"footprint consumed the shared dirty flag first")
	var clear_a: bool = Combat.clear_line(Utils.player.global_position, a.global_position)
	check(clear_a,"clear_line to monster A is clear right after the footprint refresh")
	check(Combat.clear_query.exclude.size() == 2,"reused query exclude mirrors exactly player + A")
	check(Combat.clear_query.exclude.has(rid_a),"reused query exclude holds A's live RID")
	# --- step 7-11: actor churn, freed RID must not survive ---------------------------
	a.queue_free()
	await get_tree().process_frame
	await get_tree().physics_frame
	# NOTE: the reused query still carries its LAST list here - it only re-mirrors on
	# the next call, which is exactly the staleness window the bug lived in. The freed
	# RID assertion therefore runs after the next real refresh below.
	var b = spawn_chaser(FIELD + Vector2(-180, 60))
	check(b != null,"monster B spawned after A was freed")
	for i in 2: await get_tree().physics_frame
	var rid_b: RID = b.get_rid()
	Combat.exclusions_dirty = true                       # actor set changed again
	CombatFootprint.polygon(Utils.player.global_position, 100.0)  # real path consumes it again
	var clear_b: bool = Combat.clear_line(Utils.player.global_position, b.global_position)
	check(clear_b,"clear_line to monster B is clear after the churn")
	check(Combat.clear_query.exclude.has(rid_b),"reused query exclude holds B's live RID")
	check(not Combat.clear_query.exclude.has(rid_a),"freed A's RID did not survive the refresh")
	check(Combat.clear_query.exclude.size() == 2,"exclude still mirrors exactly player + B")
	# --- step 12-13: a real wall still blocks the ray ----------------------------------
	var wall := wall_at(FIELD + Vector2(-90, 30))         # halfway between player and B
	for i in 2: await get_tree().physics_frame
	check(Combat.clear_line(Utils.player.global_position, b.global_position) == false,
		"a real wall between player and B blocks clear_line")
	# and the same wall does not block the other direction where there is no wall:
	var clear_away: bool = Combat.clear_line(b.global_position, FIELD + Vector2(-180, 400))
	check(clear_away,"a ray with no wall on its path stays clear")
	# --- cleanup -------------------------------------------------------------------------
	wall.queue_free()
	b.queue_free()
	await get_tree().process_frame
	print("B12_LOS_CHECKS ",checks," FAILURES ",failures)
	if failures: get_tree().quit(1)
	else: await Demo.quit_game()
