extends "res://tests/M8Runtime.gd"

## R3 spawn audit: quantified evidence for the "monsters outside the map / in walls
## / unreachable" report.
##
## It drives the REAL production spawn paths (the `monsterCreate` signal that
## LevelServer emits, the boss path in Town.depart(), the summon path in
## TacticalEnemy, and the arena/town candidate selection) and measures the result
## with the game's own navigation grid and a physics shape query built from each
## actor's real collision shape - not with centre-point arithmetic invented here.
##
## Counts printed at the end:
##   samples                     actors actually created by the sampled entries
##   invalid_candidates          candidate points the validators rejected
##   retries / deferred          boss retries; spawn attempts deferred for lack of
##                               a legal point (never spawned at a bad coordinate)
##   illegal_final               created actors failing a legality rule at birth
##   out_of_bounds_during_play   live actors outside the playable region later
##   wall_overlap                live actors whose real collider overlaps a wall
##   unreachable                 live actors with no navigation path to the player
##   refusals                    M5Content.spawn() rejections (shared guard)
##
## Nothing here reduces enemy counts, spawn rates or wall collisions, and nothing
## teleports an actor to the player.

const SEEDS := [11, 808, 4242]
## One encounter per spawn-entry shape; roles/rhythm/cap come from DemoConfig.
const WAVE_STAGES := [1, 4, 5, 16, 21, 26, 29]
const BOSS_STAGES := [10, 20, 30]
const EMISSIONS_PER_ROUND := 5
const DENSE_EMISSIONS := 8
## Hard wall-clock budget. Sampling stops when it is reached and the summary says
## so, so a slow machine produces truncated-but-real numbers instead of a hang.
const TIME_BUDGET_MS := 420000

var samples := 0
var illegal_final := 0
var out_of_bounds_during_play := 0
var wall_overlap := 0
var unreachable := 0
var seen_stages := {}
var seen_entries := {}
var arena_failed_before := 0
var candidate_before := 0
var rejected_before := 0
var started_ms := 0
var truncated := false
var rounds_done := 0

func _out_of_time() -> bool:
	if Time.get_ticks_msec() - started_ms < TIME_BUDGET_MS: return false
	if not truncated:
		truncated = true
		print("R3_SPAWN_AUDIT truncated=1 reason=time_budget rounds=%d samples=%d" % [rounds_done, samples])
	return true

func _ready() -> void:
	started_ms = Time.get_ticks_msec()
	await boot()
	configure(124)
	await wait(0.3)
	# Room to survive the sampling window; combat numbers are untouched.
	PlayerData.player_hp_max = 5000.0
	PlayerData.player_hp = 5000.0

	arena_failed_before = M5Content.audit_arena_failed
	candidate_before = M5Content.audit_candidates
	rejected_before = M5Content.audit_rejected

	# ---- wave entries: every region, three fixed seeds, edge and corner player
	for seed_value in SEEDS:
		for stage in WAVE_STAGES:
			if _out_of_time(): break
			await _audit_wave_round(stage, seed_value)
	# ---- boss entries (largest collider)
	for seed_value in SEEDS:
		for stage in BOSS_STAGES:
			if _out_of_time(): break
			await _audit_boss_round(stage, seed_value)
	# ---- summon entry
	for seed_value in SEEDS:
		if _out_of_time(): break
		await _audit_summon_round(seed_value, 21)
	# ---- high density: let the wave accumulate instead of purging each emission
	for stage in [26, 29]:
		if _out_of_time(): break
		await _audit_dense_round(stage)
	# ---- sequence: camp -> depart again -> different region (stale result check)
	if not _out_of_time():
		await _audit_sequence_round()

	await _report()

## ---------------------------------------------------------------- round drivers

func _audit_wave_round(stage: int, seed_value: int) -> void:
	seed(seed_value)
	if not LevelServer.town.depart(stage, true):
		check(false, "depart stage %d seed %d" % [stage, seed_value])
		return
	LevelServer.timerStop()
	await wait(0.15)
	_seen(stage)
	_keep_player_alive()
	# Edge and corner coverage: the arena candidate ring behaves differently when
	# the player stands against the boundary, which is where the report came from.
	await _place_player_at_edge(stage)

	for i in EMISSIONS_PER_ROUND:
		_exercise_entry(i, stage)
		var created := _emit_wave()
		_measure(created, "wave")
		await _advance_physics(5)
		_measure_moving("wave")
		_purge()
		await wait(0.02)
	LevelServer.return_to_camp()
	await wait(0.1)

func _audit_boss_round(stage: int, seed_value: int) -> void:
	seed(seed_value)
	# The boss is created by Town.depart() itself - the path that used to consume
	# the Vector2.INF sentinel as a real coordinate.
	if not LevelServer.town.depart(stage, true):
		check(false, "depart boss stage %d seed %d" % [stage, seed_value])
		return
	LevelServer.timerStop()
	await wait(0.2)
	_seen(stage)
	_keep_player_alive()
	seen_entries["boss"] = true
	var boss = instance_from_id(LevelServer.boss_instance) if LevelServer.boss_instance else null
	if is_instance_valid(boss):
		_measure([boss], "boss")
		await _advance_physics(6)
		_measure_moving("boss")
	else:
		# A deferred boss is a legal outcome (no validated point existed yet); the
		# illegal outcome is a boss created at an invalid coordinate, which the
		# legality rules below would catch. Record which one happened.
		seen_entries["boss_deferred"] = true
	await _advance_physics(4)
	var retried = instance_from_id(LevelServer.boss_instance) if LevelServer.boss_instance else null
	if is_instance_valid(retried):
		_measure([retried], "boss-retry")
	LevelServer.return_to_camp()
	await wait(0.1)

func _audit_summon_round(seed_value: int, stage: int) -> void:
	seed(seed_value)
	if not LevelServer.town.depart(stage, true): return
	LevelServer.timerStop()
	await wait(0.15)
	_seen(stage)
	_keep_player_alive()
	var town = LevelServer.town
	var point: Vector2 = town.spawn_near(Utils.player.global_position, 60.0, 120.0)
	if point == Vector2.INF or not point.is_finite():
		seen_entries["summon_deferred"] = true
	else:
		# E07 is the splitter: its summon() is the real production summon path.
		var parent = M5Content.spawn("E07", town.monster_root, point)
		if parent != null:
			_measure([parent], "summon-parent")
			var before := _monster_ids()
			parent.summon(4)
			await _advance_physics(2)
			var children: Array = []
			for m in get_tree().get_nodes_in_group("monsters"):
				if not before.has(m.get_instance_id()): children.append(m)
			if children.is_empty():
				seen_entries["summon_deferred"] = true
			else:
				seen_entries["summon"] = true
				_measure(children, "summon")
				await _advance_physics(5)
				_measure_moving("summon")
	_purge()
	LevelServer.return_to_camp()
	await wait(0.1)

func _audit_dense_round(stage: int) -> void:
	seed(4242)
	if not LevelServer.town.depart(stage, true): return
	LevelServer.timerStop()
	await wait(0.15)
	_seen(stage)
	_keep_player_alive()
	seen_entries["dense"] = true
	for i in DENSE_EMISSIONS:
		var created := _emit_wave()
		_measure(created, "dense")
		await _advance_physics(2)
	# Everything still alive must be legal, and must stay legal while it moves.
	_measure_moving("dense")
	await _advance_physics(10)
	_measure_moving("dense")
	_purge()
	LevelServer.return_to_camp()
	await wait(0.1)

## Consecutive combat -> camp -> depart again -> different region. A stale map or
## epoch result would place actors in the previous arena, which the legality rules
## below reject because the arena handle is the new one.
func _audit_sequence_round() -> void:
	var epoch_before = LevelServer.epoch
	seed(11)
	if not LevelServer.town.depart(6, true): check(false, "sequence depart R2"); return
	LevelServer.timerStop(); await wait(0.15)
	_seen(6); _keep_player_alive()
	_measure(_emit_wave(), "sequence")
	LevelServer.return_to_camp(); await wait(0.15)
	seed(808)
	if not LevelServer.town.depart(28, true): check(false, "sequence depart R6"); return
	LevelServer.timerStop(); await wait(0.15)
	_seen(28); _keep_player_alive()
	seen_entries["region_switch"] = true
	var second := _emit_wave()
	_measure(second, "sequence-switch")
	check(LevelServer.epoch > epoch_before, "epoch advances across camp->depart->switch")
	# Nothing from the previous arena may still be alive.
	var arena_ok := true
	var arena = LevelServer.town.arena
	for m in get_tree().get_nodes_in_group("monsters"):
		if not is_instance_valid(arena) or not is_instance_valid(m): continue
		if not arena.bounds.grow(64).has_point(arena.to_local(m.global_position)): arena_ok = false
	check(arena_ok, "no survivor from the previous arena after switching regions")
	_purge()
	LevelServer.return_to_camp(); await wait(0.1)

## ------------------------------------------------------------------- entries

func _emit_wave() -> Array:
	var before := _monster_ids()
	LevelServer.monsterCreate.emit()
	return _created_since(before)

func _exercise_entry(index: int, stage: int) -> void:
	var config = DemoConfig.ENCOUNTERS[stage]
	if config.rhythm == "精英":
		# Elite branch in Town.monsterCreate() needs the clock past 30s.
		LevelServer.level_info.time = maxf(LevelServer.level_info.time, 35.0)
		seen_entries["elite"] = true
	match index % 3:
		0: seen_entries["wave"] = true
		1:
			seen_entries["rush"] = true
			LevelServer.rush_active = true; LevelServer.rush_side = index % 4
		2:
			if M5Content.HORDES.has(stage):
				seen_entries["horde"] = true
				LevelServer.horde_active = true; LevelServer.horde_role = "E02"; LevelServer.horde_side = 0

func _restore_entry_flags() -> void:
	LevelServer.rush_active = false
	LevelServer.horde_active = false

## ---------------------------------------------------------------- measurement

func _measure(actors: Array, tag: String) -> void:
	for actor in actors:
		if not is_instance_valid(actor): continue
		samples += 1
		var reason = _illegal_reason(actor)
		if reason != "":
			illegal_final += 1
			check(false, "illegal spawn [%s/%s] %s" % [tag, reason, _describe(actor)])

func _measure_moving(tag: String) -> void:
	for actor in get_tree().get_nodes_in_group("monsters"):
		if not is_instance_valid(actor) or actor.get("training") == true: continue
		if not _in_playable_region(actor):
			out_of_bounds_during_play += 1
			check(false, "left playable region while running [%s] %s" % [tag, _describe(actor)])
		if _collider_overlaps_wall(actor):
			wall_overlap += 1
			check(false, "collider overlaps wall while running [%s] %s" % [tag, _describe(actor)])
		if not _reachable_from_player(actor):
			unreachable += 1
			check(false, "unreachable from player area [%s] %s" % [tag, _describe(actor)])

func _illegal_reason(actor: Node2D) -> String:
	if not is_finite(actor.global_position.x) or not is_finite(actor.global_position.y):
		return "non-finite"
	if not _in_playable_region(actor): return "outside-region"
	if _collider_overlaps_wall(actor): return "wall-overlap"
	if not _reachable_from_player(actor): return "unreachable"
	return ""

## The playable region is the game's own definition: the arena bounds plus its
## navigation grid, or the town navigation grid for the arena-less region R1.
func _in_playable_region(actor: Node2D) -> bool:
	var pos: Vector2 = actor.global_position
	if not is_finite(pos.x) or not is_finite(pos.y): return false
	var town = LevelServer.town
	var arena = town.arena if is_instance_valid(town) else null
	if is_instance_valid(arena):
		if not arena.bounds.grow(-16).has_point(arena.to_local(pos)): return false
		return not arena.grid.is_point_solid(arena.cell(pos))
	if not town.nav_ready: return true
	var nav: AStarGrid2D = town.navigation
	var cell: Vector2i = town.nav_cell(pos)
	if not nav.is_in_boundsv(cell): return false
	return not nav.is_point_solid(cell)

func _reachable_from_player(actor: Node2D) -> bool:
	if not is_instance_valid(Utils.player): return true
	var town = LevelServer.town
	var arena = town.arena if is_instance_valid(town) else null
	var player_pos: Vector2 = Utils.player.global_position
	if is_instance_valid(arena):
		var path = arena.grid.get_id_path(arena.cell(actor.global_position), arena.nearest(player_pos))
		return path.size() > 1
	if not town.nav_ready: return true
	var nav: AStarGrid2D = town.navigation
	return nav.get_id_path(town.nav_cell(actor.global_position), town.nav_cell(player_pos)).size() > 1

## Physics shape query with the actor's OWN collider against the wall layers - the
## same technique Town.build_navigation() uses, so it cannot drift from movement.
func _collider_overlaps_wall(actor: Node2D) -> bool:
	var cs := actor.get_node_or_null("CollisionShape2D") as CollisionShape2D
	if cs == null or cs.shape == null: return false
	var space := actor.get_world_2d().direct_space_state
	if space == null: return false
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = cs.shape
	query.collision_mask = 2147483649
	query.transform = cs.global_transform
	query.exclude = [actor.get_rid()]
	return not space.intersect_shape(query, 1).is_empty()

## ------------------------------------------------------------------- helpers

func _monster_ids() -> Dictionary:
	var ids := {}
	for m in get_tree().get_nodes_in_group("monsters"): ids[m.get_instance_id()] = true
	return ids

func _created_since(before: Dictionary) -> Array:
	var out: Array = []
	for m in get_tree().get_nodes_in_group("monsters"):
		if not before.has(m.get_instance_id()): out.append(m)
	return out

func _purge() -> void:
	for m in get_tree().get_nodes_in_group("monsters"):
		if m.get("training") == true: continue
		m.queue_free()
	_restore_entry_flags()
	await get_tree().physics_frame

func _advance_physics(frames: int) -> void:
	for i in frames:
		await get_tree().physics_frame

func _keep_player_alive() -> void:
	PlayerData.player_hp = PlayerData.player_hp_max
	if is_instance_valid(Utils.player):
		Utils.player.is_dead = false
	LevelServer.state = "COMBAT"

func _place_player_at_edge(stage: int) -> void:
	var arena = LevelServer.town.arena
	if not is_instance_valid(arena):
		seen_entries["town_nav"] = true
		return
	seen_entries["arena"] = true
	# Cycle through two boundary edges and two corners so edge/corner candidate
	# rings are actually exercised, not just the open middle.
	var spots := [Vector2(375, 0), Vector2(-375, 0), Vector2(375, 271), Vector2(-375, -271)]
	var spot: Vector2 = spots[stage % spots.size()]
	Utils.player.global_position = arena.to_global(spot)
	await _advance_physics(2)

func _seen(stage: int) -> void:
	seen_stages[stage] = seen_stages.get(stage, 0) + 1
	rounds_done += 1
	# Streamed so a truncated run still shows where it got to.
	print("R3_SPAWN_AUDIT_PROGRESS round=%d stage=%d samples=%d illegal=%d oob=%d wall=%d unreach=%d t=%dms" % [
		rounds_done, stage, samples, illegal_final, out_of_bounds_during_play, wall_overlap, unreachable,
		Time.get_ticks_msec() - started_ms])

func _describe(actor: Node2D) -> String:
	var id = str(actor.get_meta("content_id", "?"))
	return "%s at %s" % [id, str(actor.global_position.round())]

## -------------------------------------------------------------------- report

func _report() -> void:
	var invalid_candidates = (M5Content.audit_candidates) - candidate_before
	var rejected = (M5Content.audit_rejected) - rejected_before
	var deferred = M5Content.audit_deferred
	var boss_deferred = M5Content.audit_boss_deferred
	var retries = M5Content.audit_boss_retry
	var refusals = M5Content.audit_refused
	var arena_failed = M5Content.audit_arena_failed - arena_failed_before
	print("R3_SPAWN_AUDIT samples=%d invalid_candidates=%d rejected=%d retries=%d deferred=%d boss_deferred=%d illegal_final=%d out_of_bounds_during_play=%d wall_overlap=%d unreachable=%d refusals=%d arena_no_point=%d truncated=%d rounds=%d" % [
		samples, invalid_candidates, rejected, retries, deferred + boss_deferred, boss_deferred,
		illegal_final, out_of_bounds_during_play, wall_overlap, unreachable, refusals, arena_failed,
		1 if truncated else 0, rounds_done])
	print("R3_SPAWN_AUDIT stages=%s entries=%s" % [str(seen_stages.keys()), str(seen_entries.keys())])
	print("R3_SPAWN_AUDIT checks=%d failures=%d" % [checks, failures])
	print("R3_SPAWN_AUDIT_RESULT %s" % ("PASS" if failures == 0 and illegal_final == 0 and out_of_bounds_during_play == 0 and wall_overlap == 0 and unreachable == 0 and not truncated else "FAIL"))
	LevelServer.return_to_camp()
	await wait(0.2)
	get_tree().quit(0 if failures == 0 and not truncated else 1)
