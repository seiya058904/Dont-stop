extends "res://tests/M8Runtime.gd"

## B11.1 static-lane clipping contract.
##
## WHY THIS EXISTS. The confirmed root cause of the Stage 39 dense-attack stutter was one boolean.
## `HostileZone` decided whether to recompute its wall clip with
##
##     ray_clock <= 0 or elapsed >= warning or global_position != last_ray_origin
##
## and `elapsed >= warning` becomes true FOREVER at the instant a lane fires. So a lane that never
## turns re-raycast the SAME frozen segment against static level geometry on every physics frame of
## its entire active window, for an answer that provably could not change. An unpromoted E14 beam is
## exactly that lane: no sweep, a 0.35 s active window, and up to ten of them alive at once in
## Stage 39. Fixing it means the clip must still be right, so this test pins the fix from BOTH
## sides - the cost it removes and the correctness it must not trade away.
##
##   A. the WARNING still clips, so a lane cannot fire with a stale length;
##   B. past the warning a frozen lane stops re-clipping and says so, and only the 0.1 s safety
##      refresh remains;
##   C. but its `length` is still EXACTLY the wall-clipped distance, recomputed here by the test's
##      own raycast from the same origin/direction/maximum_length - and it really is clipped by the
##      wall rather than left at maximum, so B is not passing on a lane with no wall in the way;
##   D. a lane that actually TURNS still re-clips every tick and its length really changes;
##   E. a lane whose ORIGIN moves re-clips at once, not on the 0.1 s cadence;
##   F. the incoming-damage fan-out still classifies the reward group into the four callback phases
##      over the same nodes in the same order, and re-uses that classification while the group is
##      unchanged - then re-classifies once a member leaves. This is the second change made in this
##      round and it must not reorder a callback. Every node is named by its position in the live
##      group, never by a catalog id, because `BaseReward.id` is runtime-unique.
##   G. B11.2, same defect class as A/B one layer up: a footprint whose ink provably cannot change
##      stops repainting (measured, not inferred - `profile_stats.redraw_requests`), while a lane
##      that really is TURNING keeps the physics cadence, so "stop when frozen" cannot freeze a
##      sweeping laser mid-arc.
##
## Every lane below is a product `TacticalEnemy.zone()` footprint on live geometry, not a synthetic
## fixture built to agree with the test. The only thing the test injects is a wall it places itself,
## so "was the lane clipped" has an answer the test can compute independently of the arena layout.

const WALL_LAYER := 2147483648
## The wall sits between the sentinel and the player, so the beam's own aim runs into it.
const SENTINEL_OFFSET := Vector2(200.0, 0.0)
const WALL_OFFSET := Vector2(150.0, 0.0)
const WALL_SIZE := Vector2(16.0, 240.0)
## How thick the wall's own half-width is, i.e. where the lane must stop.
const WALL_HALF := 8.0

var wall_body: StaticBody2D = null

## The test's own wall clip, using the same mask the product uses, over the lane's CURRENT
## geometry. If the product skipped a recomputation it should not have skipped, this disagrees.
func clip_of(zone) -> float:
	var query = PhysicsRayQueryParameters2D.create(zone.global_position,
		zone.global_position+zone.direction*zone.maximum_length,WALL_LAYER)
	var hit = Utils.player.get_world_2d().direct_space_state.intersect_ray(query)
	return zone.global_position.distance_to(hit.position) if not hit.is_empty() else zone.maximum_length

func lanes() -> Array:
	var out := []
	for node in get_tree().get_nodes_in_group("hostile_zone"):
		if node.mode == "line": out.append(node)
	return out

func one_lane() -> Node2D:
	var list := lanes()
	return list[0] if not list.is_empty() else null

## The product's own repaint counter, armed because B11Probe is enabled (see HostileZone.profile_stats).
func redraws() -> int:
	return int(load("res://game/monster/HostileZone.gd").profile_snapshot().redraw_requests)

## Spawn a stationary sentinel whose physics does not run, so the ONLY thing advancing is the lane
## under test. Contact is pushed out of the way; its own attacks are never reached.
func parked_sentinel(role: String):
	var actor = M5Content.spawn(role,LevelServer.town.monster_root,
		Utils.player.global_position+SENTINEL_OFFSET)
	if actor == null: return null
	actor.set_physics_process(false)
	actor.contact_cooldown = 99.0
	actor.locked_direction = actor.global_position.direction_to(Utils.player.global_position)
	return actor

## Advance real physics frames until the predicate holds, with a hard bound so a regression fails
## instead of hanging the runner.
func until(predicate: Callable, frames: int) -> bool:
	var i := 0
	while i < frames:
		if predicate.call(): return true
		i += 1
		await wait(1.0/60.0)
	return predicate.call()

func same_nodes(calls: Array, expected: Array) -> bool:
	if calls.size() != expected.size(): return false
	for i in calls.size():
		if calls[i].get_object() != expected[i]: return false
	return true

func clean_actors() -> void:
	for group in ["monsters","hostile_zone","enemy_projectiles"]:
		for node in get_tree().get_nodes_in_group(group):
			if is_instance_valid(node): node.queue_free()
	await wait(0.15)

func _ready():
	# The probe is the test-only measurement channel (game/diag/B11Probe.gd). It is OFF in every
	# normal launch; arming it here is what lets the test see the clip count instead of inferring it.
	B11Probe.enabled = true
	await boot()
	await dismiss()
	await wait(0.3)
	var town = LevelServer.town
	LevelServer.state = "COMBAT"
	Utils.player.global_position = town.global_position+Vector2(0.0,-40.0)
	# A wall the test places itself, straight across the lane the sentinel will fire down.
	wall_body = wall(Utils.player.global_position+WALL_OFFSET,WALL_SIZE)
	await wait(0.2)

	# ---- A + B + C. the real unpromoted E14 beam: frozen lane, warning clip, then the skip ------
	var sentinel = parked_sentinel("E14")
	check(sentinel != null,"the laser sentinel spawns")
	if sentinel == null:
		await finish()
		return
	sentinel.phase = "move"; sentinel.phase_time = 0.0
	sentinel._begin("beam")
	var zone = one_lane()
	check(zone != null,"the beam creates exactly one line lane")
	if zone == null:
		await finish()
		return
	check(float(zone.sweep) == 0.0,"an unpromoted sentinel's beam does not sweep, i.e. it is the frozen case")
	# Non-damaging: this test is about the CLIP. The damage window has its own variables and is
	# already pinned by tests/B11Fairness.gd, and a hit in the middle of the sample would replace
	# the timeline this test is measuring with the player's own.
	zone.damage = 0.0

	var rays_at_spawn: int = B11Probe.raycasts
	await until(func(): return zone.elapsed >= float(zone.warning)*0.5,60)
	check(B11Probe.raycasts > rays_at_spawn,"the lane clips its own geometry during its warning")
	check(absf(zone.length-clip_of(zone)) < 0.5,
		"the warning's length is the wall-clipped distance (%.1f vs %.1f)" % [zone.length,clip_of(zone)])
	check(zone.length < 60.0,
		"the lane really is clipped by the wall, not left at maximum (%.1f of %.1f)"
		% [zone.length,zone.maximum_length])

	await until(func(): return zone.elapsed >= float(zone.warning)+0.05,240)
	check(zone.elapsed >= float(zone.warning) and not zone.is_queued_for_deletion(),
		"the lane is past its warning and still alive")
	var rays_a: int = B11Probe.raycasts
	var skips_a: int = B11Probe.raycasts_skipped
	var dir_a: Vector2 = zone.direction
	await wait(0.20)
	var d_rays: int = B11Probe.raycasts-rays_a
	var d_skips: int = B11Probe.raycasts_skipped-skips_a
	check(d_skips >= 6,"past the warning the frozen lane skips its redundant re-clip (%d skipped)" % d_skips)
	check(d_rays <= 4,"...and only the 0.1 s safety refresh still clips it (%d clips in 0.20 s)" % d_rays)
	check(zone.direction.is_equal_approx(dir_a) and dir_a.is_equal_approx(zone.initial_direction),
		"a frozen lane's direction never moved, which is why the skip is sound")
	check(absf(zone.length-clip_of(zone)) < 0.5,
		"the frozen lane's length is STILL the wall-clipped distance (%.1f vs %.1f)"
		% [zone.length,clip_of(zone)])

	# ---- D. a lane that really turns must keep re-clipping --------------------------------------
	await clean_actors()
	LevelServer.state = "COMBAT"
	var turner = parked_sentinel("E14")
	check(turner != null,"a second sentinel spawns for the turning case")
	if turner == null:
		await finish()
		return
	var spin = turner.zone("line",turner.global_position,330.0,0.35,0.9,"sweep")
	spin.damage = 0.0
	spin.sweep = 1.0
	await until(func(): return spin.elapsed >= float(spin.warning)+0.05,240)
	var rays_t: int = B11Probe.raycasts
	var len_t: float = spin.length
	var dir_t: Vector2 = spin.direction
	await wait(0.25)
	var t_rays: int = B11Probe.raycasts-rays_t
	check(t_rays >= 10,"a TURNING lane keeps re-clipping every tick (%d clips in 0.25 s)" % t_rays)
	check(absf(spin.length-len_t) > 0.5 or absf(spin.direction.angle_to(dir_t)) > 0.05,
		"a turning lane's geometry really moves, so its clip really had to be recomputed")
	check(absf(spin.length-clip_of(spin)) < 0.5,
		"a turning lane's length is still wall-clipped (%.1f vs %.1f)" % [spin.length,clip_of(spin)])

	# ---- E. a moving origin re-clips at once, without waiting for the safety refresh ------------
	await clean_actors()
	LevelServer.state = "COMBAT"
	var holder = parked_sentinel("E14")
	check(holder != null,"a third sentinel spawns for the moving-origin case")
	if holder == null:
		await finish()
		return
	# A long active window on the same product factory, so the settled state has room to be sampled.
	var still = holder.zone("line",holder.global_position,330.0,0.30,2.0,"laser")
	still.damage = 0.0
	await until(func(): return still.elapsed >= float(still.warning)+0.2,300)
	var skip_probe := B11Probe.raycasts_skipped
	await wait(0.12)
	check(B11Probe.raycasts_skipped > skip_probe,
		"the long lane is settled in the skipping state before the origin is moved")
	var rays_m: int = B11Probe.raycasts
	still.global_position += Vector2(0.0,26.0)
	await wait(0.05)
	check(B11Probe.raycasts > rays_m,
		"a lane whose ORIGIN moves is re-clipped at once, not on the 0.1 s cadence")
	check(absf(still.length-clip_of(still)) < 0.5,
		"...and to the true wall-clipped distance at the new origin (%.1f vs %.1f)"
		% [still.length,clip_of(still)])
	check(still.last_ray_origin.is_equal_approx(still.global_position),
		"...and last_ray_origin follows the lane, so one move costs one clip, not one per frame")

	# ---- F. the reward fan-out: same nodes, same order, and the classification is re-used -------
	# `addReward` is the same door the camp shop uses and the same one tests/M10Growth.gd uses; it
	# does not consult LevelServer.state, so the combat state stays untouched through this section.
	# The id set mixes the rewards that arm `connect_beforePlayerHit` (1 and 3) with CombatReward-derived
	# ones that implement `incoming`/`received`, so no phase is vacuous by accident. Two build facts
	# shape what may be asserted, and neither is a literal the test gets to choose:
	#   * id 1 (HpReward) has only_start = true, so BaseReward._ready removes it again in the same
	#     frame. It is kept in the set on purpose - the group has to survive that churn - but it can
	#     never be counted as a member, so the width is NOT the id count;
	#   * `connect_afterPlayerHit` is armed by nothing in this build, so that phase is legitimately
	#     empty - which is exactly the case a cache could get wrong by omission.
	for id in ["1","3","12","14","17","18","20","22","23"]:
		RewardServer.addReward(RewardServer.reward_list[id].instantiate())
	var nodes = get_tree().get_nodes_in_group("reward")
	# Identity is taken from the LIVE GROUP and never from a catalog key: BaseReward.id is a
	# runtime-unique value (Time.get_ticks_usec() + randi()%1000), so no literal id can name a node.
	check(nodes.size() >= 4,
		"the reward group is populated, so the fan-out is measured at width (%d)" % nodes.size())
	# The reference classification, computed here from the same group. Order is the group's own
	# order, which is what the product's four phases walk.
	var ref_before: Array = []; var ref_incoming: Array = []
	var ref_received: Array = []; var ref_after: Array = []
	for node in nodes:
		if node.connect_beforePlayerHit: ref_before.append(node)
		if node.has_method("incoming"): ref_incoming.append(node)
		if node.has_method("received"): ref_received.append(node)
		if node.connect_afterPlayerHit: ref_after.append(node)
	var built_a: int = B11Probe.reward_fanouts_built
	Utils.player._reward_fanout(nodes)
	var built_b: int = B11Probe.reward_fanouts_built
	check(built_b == built_a+1,"the first classification of a changed group rebuilds the fan-out")
	check(same_nodes(Utils.player.fanout_before,ref_before),
		"the beforePlayerHit phase is the same nodes in the same order (%d)" % ref_before.size())
	check(same_nodes(Utils.player.fanout_incoming,ref_incoming),
		"the incoming phase is the same nodes in the same order (%d)" % ref_incoming.size())
	check(same_nodes(Utils.player.fanout_received,ref_received),
		"the received phase is the same nodes in the same order (%d)" % ref_received.size())
	check(same_nodes(Utils.player.fanout_after,ref_after),
		"the afterPlayerHit phase is the same nodes in the same order (%d)" % ref_after.size())
	check(ref_incoming.size() >= 1,"at least one reward really implements the incoming hook")
	check(ref_before.size() >= 1,"at least one reward really arms the beforePlayerHit hook")
	check(ref_after.is_empty(),
		"nothing in this build arms afterPlayerHit, so that phase must classify to zero rather than to everything")
	var reused_a: int = B11Probe.reward_fanouts_reused
	Utils.player._reward_fanout(nodes)
	check(B11Probe.reward_fanouts_built == built_b,
		"an UNCHANGED group is re-used, not re-classified")
	check(B11Probe.reward_fanouts_reused == reused_a+1,"...and the re-use is counted")
	# Removing a reward must miss the key and force a rebuild, or the cache would outlive its input.
	# The victim comes from the CLASSIFICATION, not from a catalog key - see the identity note above.
	# It is deliberately one that really implements `incoming`, so the removal changes a phase list and
	# not merely the group width, which is the stronger of the two ways to miss.
	var victim = null
	if ref_incoming.size() > 0: victim = ref_incoming[0]
	check(victim != null and victim in nodes,"the reward that is about to be removed was in the group")
	if victim != null:
		RewardServer.removeReward(victim)
		await wait(0.1)
		Utils.player._reward_fanout(get_tree().get_nodes_in_group("reward"))
		check(B11Probe.reward_fanouts_built == built_b+1,
			"a changed group misses the cache and is re-classified")

	# ---- G. the B11.2 repaint contract ---------------------------------------------------------
	# The SAME "permanently true" defect as the clip above, one layer up - in the repaint gate
	# rather than in the raycast gate:
	#
	#     if visual_clock <= 0 or active != previous_active or elapsed >= warning-0.15:
	#
	# `elapsed >= warning-0.15` also becomes true FOREVER the instant a footprint fires, so an
	# ACTIVE zone repainted at the PHYSICS cadence for its whole active window - even though
	# `progress` is clamped to 1, `active` overwrites both palette entries and the geometry cache
	# cannot miss, so the ink it produced was byte-identical on every one of those frames. The fix
	# stops the repaint while the ink provably cannot change, and keeps it wherever the ink CAN:
	# activation, a turning lane, a moved origin, a detail-budget flip. `redraw_requests` is the
	# product's own counter; every other footprint is cleared first so the delta is attributable.
	await clean_actors()
	var frozen_actor = parked_sentinel("E14")
	check(frozen_actor != null,"a sentinel spawns for the frozen-repaint half")
	if frozen_actor != null:
		frozen_actor.phase = "move"; frozen_actor.phase_time = 0.0
		frozen_actor._begin("beam")
		var frozen_lane = one_lane()
		check(frozen_lane != null and float(frozen_lane.sweep) == 0.0,
			"the frozen-repaint probe is an unpromoted, non-turning lane")
		if frozen_lane != null:
			check(await until(func(): return frozen_lane.activated,400),"the frozen-repaint probe really fires")
			if is_instance_valid(frozen_lane):
				await until(func(): return frozen_lane.active_elapsed > 0.06,120)
				if is_instance_valid(frozen_lane):
					var mark: int = redraws()
					for i in 8: await wait(1.0/60.0)
					var grown: int = redraws()-mark
					check(grown == 0,
						"a frozen active lane stops repainting, because its ink cannot change (%d requests in 8 frames)" % grown)

	# The carve-out, and it is the half that protects readability: a lane that really IS turning
	# changes its ink every tick, so it must keep the physics cadence. Without this, "stop
	# repainting when frozen" would freeze a sweeping laser mid-arc.
	await clean_actors()
	var sweeping_actor = parked_sentinel("E14")
	check(sweeping_actor != null,"a promoted sentinel spawns for the turning half")
	if sweeping_actor != null:
		sweeping_actor.is_elite = true
		sweeping_actor.phase = "move"; sweeping_actor.phase_time = 0.0
		sweeping_actor._begin("beam")
		var turning_lane = one_lane()
		check(turning_lane != null and float(turning_lane.sweep) != 0.0,
			"a promoted E14 really produces a TURNING lane")
		if turning_lane != null:
			check(await until(func(): return turning_lane.activated,400),"the turning lane really fires")
			if is_instance_valid(turning_lane):
				await until(func(): return turning_lane.active_elapsed > 0.04,120)
				if is_instance_valid(turning_lane):
					var mark2: int = redraws()
					for i in 5: await wait(1.0/60.0)
					var grown2: int = redraws()-mark2
					check(grown2 >= 4,
						"a turning lane keeps repainting every tick (%d requests in 5 frames)" % grown2)

	await finish()

func finish() -> void:
	if is_instance_valid(wall_body): wall_body.queue_free()
	await clean_actors()
	B11Probe.enabled = false
	print("B11_ZONECLIP checks=",checks," failures=",failures)
	if failures: get_tree().quit(1)
	else: await Demo.quit_game()
