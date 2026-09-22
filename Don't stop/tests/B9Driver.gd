extends "res://tests/M8Runtime.gd"

## B9 driver contracts: the shared safe-movement core.
##
## Why this scene exists: B8 measured Normal Stage 21-29 clear rates with a driver whose
## 16-direction danger evaluation was gated behind `if target_boss and target.is_boss`. The
## Boss driver dodged; the Stage 21-29 driver did not. Every Normal clear rate from B8 is
## therefore an underestimate of what the build can do, and it must not be used as the
## justification for another product nerf. B9 lifts that evaluation into one shared core
## (M8Runtime.choose_safe_movement) that both paths call.
##
## This scene is the proof that the core does what it claims, on real game code paths, in
## seconds - before any 45-second battle is allowed to quote it. It runs no round that could
## produce a balance number, and it makes no survivability claim: what it measures is the
## DIRECTION the core returns for a known arena.
##
## Contracts (the brief's list):
##   A. empty field            the wanted direction is not changed without cause
##   B. one circle             the dangerous direction is downweighted, a safe one is chosen
##   C. line / beam            it does not walk into a clear linear danger
##   D. cone                   it can pick a direction outside the cone
##   E. projectile             short-horizon trajectory prediction lowers that candidate
##   F. wall                   it never chooses a collision-blocked movement
##   G. all-danger             it still picks the LOWEST danger depth, and never returns NaN
##   H. ordinary encounter     with target_boss = false the scorer really is called - the
##                             anti-regression contract that stops it becoming boss-only again
##
## The geometry predicates used for the assertions below are re-stated from
## HostileZone.step()'s own damage tests rather than read out of the core, so the core is
## checked against the game's rule and not against itself.

const STEP := 38.0
const WALL_STEP := 24.0

func player_at() -> Vector2:
	return Utils.player.global_position

func ahead(direction: Vector2) -> Vector2:
	return player_at()+direction*STEP

func inside_circle(point: Vector2, centre: Vector2, radius: float) -> bool:
	return point.distance_to(centre) <= radius

func lane_distance(point: Vector2, from: Vector2, to: Vector2) -> float:
	return Geometry2D.get_closest_point_to_segment(point,from,to).distance_to(point)

## HostileZone.step()'s own cone test: inside the radius AND inside the angle.
func inside_cone(point: Vector2, apex: Vector2, direction: Vector2, radius: float, angle: float) -> bool:
	var offset = point-apex
	if offset.length() > radius: return false
	return absf(direction.angle_to(offset)) <= angle

## A real HostileZone with explicit geometry. `damage` is real; the duration is long enough to
## outlive the synchronous call under test and the zone is retired by hand afterwards.
func footprint(mode: String, at: Vector2, radius: float, direction: Vector2, length: float,
		width: float, angle: float, damage_value: float, warning := 0.05) -> Node2D:
	var zone = load("res://game/monster/HostileZone.gd").new()
	zone.mode = mode; zone.radius = radius; zone.length = length; zone.width = width
	zone.angle = angle; zone.direction = direction
	zone.warning = warning; zone.duration = 8.0; zone.tick = 0.2; zone.damage = damage_value
	zone.world_point = at
	get_tree().current_scene.add_child(zone)
	return zone

func retire(nodes) -> void:
	if nodes is Array:
		for node in nodes:
			if is_instance_valid(node): node.queue_free()
	elif is_instance_valid(nodes):
		nodes.queue_free()

func clear_transients() -> void:
	for node in get_tree().get_nodes_in_group("combat_transient"): node.queue_free()
	for node in get_tree().get_nodes_in_group("monsters"): node.queue_free()
	await wait(0.3)

## Ask the core for a decision and hand back both the answer and the telemetry it recorded.
func ask(wanted: Vector2, target, actors: Array) -> Dictionary:
	reset_dodge_telemetry()
	var chosen: Vector2 = choose_safe_movement(wanted,target,actors)
	return {"chosen":chosen,"last":dodge_last.duplicate(),"decisions":dodge_decisions}

func _ready():
	await boot()
	configure(117,false)
	Demo.talents = {}
	Demo.refresh()
	# The contracts below are about the DIRECTION the core returns, not about surviving. A real
	# round is not running (the round timer is only started by LevelServer.roundStart), and the
	# pool is widened only so a footprint that is deliberately placed around the player cannot
	# end the scene halfway through the contract list. No survivability number is produced here.
	PlayerData.player_hp_max = 100000; PlayerData.player_hp = 100000
	LevelServer.state = "COMBAT"
	var anchor := Utils.player

	# ---- A. empty field: the wish is not changed without cause ------------------------------
	var empty = ask(Vector2(0.6,0.8),anchor,[])
	check(int(empty.last.get("blocked",-1)) == 0,
		"A setup: the test position has clearance in all %d directions (%d blocked)" % [DODGE_DIRECTIONS,int(empty.last.get("blocked",-1))])
	check(int(empty.last.get("penalties",-1)) == 0,
		"A setup: an empty field applies no penalty at all (%d penalties)" % int(empty.last.get("penalties",-1)))
	check(empty.chosen == Vector2(0.6,0.8),
		"A. an empty field leaves the wanted direction unchanged (wanted (0.6, 0.8), chose %s)" % str(empty.chosen))

	# ---- B. one circle: the dangerous direction is downweighted ------------------------------
	var circle_at = player_at()+Vector2(60,0)
	var circle = footprint("circle",circle_at,38.0,Vector2.RIGHT,38.0,8.0,0.7,0.0)
	await wait(0.15)
	check(inside_circle(ahead(Vector2.RIGHT),circle_at,38.0),"B setup: the wanted step really is inside the footprint")
	var circle_pick = ask(Vector2.RIGHT,anchor,[])
	await wait(0.02)
	check(circle_pick.chosen != Vector2.RIGHT,
		"B. a footprint on the wanted direction is downweighted (chose %s)" % str(circle_pick.chosen))
	check(not inside_circle(ahead(circle_pick.chosen),circle_at,38.0),
		"B. and the step it picks is outside the real footprint (%s is %.1f px from the centre, radius 38)" % [
			str(ahead(circle_pick.chosen)),ahead(circle_pick.chosen).distance_to(circle_at)])
	check(bool(circle_pick.last.get("all_danger",true)) == false,
		"B. a safe direction existed, so this is not the emergency path")
	retire(circle); await wait(0.2)

	# ---- C. line / beam: never walk into a clear linear danger ------------------------------
	# The lane starts one step ahead of the player and runs away, so the player himself is never
	# inside it: the contract is about the STEP the core chooses, not about taking damage.
	var lane_at = player_at()+Vector2(STEP,0)
	var lane = footprint("line",lane_at,300.0,Vector2.RIGHT,300.0,8.0,0.7,1.0)
	await wait(0.15)
	check(lane_distance(ahead(Vector2.RIGHT),lane.global_position,lane.global_position+lane.direction*lane.length) <= lane.width,
		"C setup: the wanted step really is inside the damaging lane")
	var lane_pick = ask(Vector2.RIGHT,anchor,[])
	check(lane_pick.chosen != Vector2.RIGHT,
		"C. a linear danger downweights the direction it covers (chose %s)" % str(lane_pick.chosen))
	check(lane_distance(ahead(lane_pick.chosen),lane.global_position,lane.global_position+lane.direction*lane.length) > lane.width,
		"C. and the step it picks is outside the damaging lane (%.1f px from the centre line, half-width %.1f)" % [
			lane_distance(ahead(lane_pick.chosen),lane.global_position,lane.global_position+lane.direction*lane.length),lane.width])
	retire(lane); await wait(0.2)

	# ---- D. cone: pick a direction outside the cone -----------------------------------------
	# Aimed back at the player from beyond its own radius, so the player is never inside it.
	var cone_at = player_at()+Vector2(60,0)
	var cone_dir = Vector2.LEFT
	var cone = footprint("cone",cone_at,50.0,cone_dir,50.0,8.0,0.6,1.0)
	await wait(0.15)
	check(inside_cone(ahead(Vector2.RIGHT),cone.global_position,cone_dir,cone.radius,cone.angle),
		"D setup: the wanted step really is inside the cone")
	check(not inside_cone(player_at(),cone.global_position,cone_dir,cone.radius,cone.angle),
		"D setup: the player himself is outside the cone, so this contract cannot take damage")
	var cone_pick = ask(Vector2.RIGHT,anchor,[])
	check(not inside_cone(ahead(cone_pick.chosen),cone.global_position,cone_dir,cone.radius,cone.angle),
		"D. the step it picks is outside the cone (chose %s)" % str(cone_pick.chosen))
	retire(cone); await wait(0.2)

	# ---- E. projectile: short-horizon prediction lowers that candidate ----------------------
	# Frozen the instant its _ready() has run, so it never takes a physics step: the core scores
	# the shot's PREDICTED path (position + velocity * 0.3 s), which is exactly what a shot that
	# has not moved yet still supplies. Letting it fly instead would make the arena depend on
	# whatever piece of camp scenery it happened to hit first.
	var shot = load("res://game/monster/EnemyShot.gd").new()
	shot.position = player_at()+Vector2(40,-60)
	shot.velocity = Vector2(0,220); shot.damage = 1.0; shot.style = "projectile"
	get_tree().current_scene.add_child(shot)
	shot.set_physics_process(false)
	check(is_instance_valid(shot) and shot.is_in_group("combat_transient"),
		"E setup: a real EnemyShot is live in the transient group")
	var shot_at: Vector2 = shot.global_position
	var predicted: Vector2 = shot_at+Vector2(shot.velocity)*DODGE_SHOT_LOOKAHEAD
	check(lane_distance(ahead(Vector2.RIGHT),shot_at,predicted) < 18,
		"E setup: the wanted step really is on the projectile's predicted path (%.1f px)" % lane_distance(ahead(Vector2.RIGHT),shot_at,predicted))
	var shot_pick = ask(Vector2.RIGHT,anchor,[])
	check(shot_pick.chosen != Vector2.RIGHT,
		"E. an incoming trajectory downweights the direction it crosses (chose %s)" % str(shot_pick.chosen))
	check(lane_distance(ahead(shot_pick.chosen),shot_at,predicted) > 12.0,
		"E. and the step it picks clears the projectile's own %.0f px hit radius (%.1f px away)" % [
			12.0,lane_distance(ahead(shot_pick.chosen),shot_at,predicted)])
	retire(shot); await wait(0.2)

	# ---- F. wall: never choose a collision-blocked movement ----------------------------------
	# A real static slab whose left edge sits just outside the player's own 7 px collider, on the
	# layer the player's mask actually collides with, so test_move sees it exactly the way it
	# sees terrain.
	var wall = StaticBody2D.new()
	wall.collision_layer = 1; wall.collision_mask = 0
	var slab = CollisionShape2D.new()
	var rect = RectangleShape2D.new(); rect.size = Vector2(104,200)
	slab.shape = rect
	wall.add_child(slab)
	get_tree().current_scene.add_child(wall)
	wall.global_position = player_at()+Vector2(70,0)
	await wait(0.2)
	check(Utils.player.test_move(Utils.player.global_transform,Vector2.RIGHT*WALL_STEP),
		"F setup: the slab really does block a rightward step")
	var wall_pick = ask(Vector2.RIGHT,anchor,[])
	check(int(wall_pick.last.get("blocked",0)) > 0,
		"F. the blocked directions were detected and removed from the choice (%d of %d blocked)" % [
			int(wall_pick.last.get("blocked",0)),DODGE_DIRECTIONS])
	check(not Utils.player.test_move(Utils.player.global_transform,wall_pick.chosen*WALL_STEP),
		"F. and the chosen direction is not collision blocked (chose %s)" % str(wall_pick.chosen))
	retire(wall); await wait(0.3)

	# ---- G. all-danger: lowest danger depth, no NaN, no stall ---------------------------------
	# A footprint wide enough to contain every one of the 16 samples, offset so the depths differ
	# and the shallowest exit is the +X side. damage 0 keeps it a pure geometry contract.
	var field_at = player_at()+Vector2(-120,0)
	var field = footprint("circle",field_at,400.0,Vector2.RIGHT,400.0,8.0,0.7,0.0)
	await wait(0.15)
	var danger_pick = ask(Vector2.RIGHT,anchor,[])
	check(bool(danger_pick.last.get("all_danger",false)),
		"G setup: every one of the scored directions really is inside the footprint")
	var chosen_step = ahead(danger_pick.chosen)
	check(not is_nan(danger_pick.chosen.x) and not is_nan(danger_pick.chosen.y) and danger_pick.chosen.length_squared() < 1e18,
		"G. the all-danger answer is a finite vector, not NaN (%s)" % str(danger_pick.chosen))
	check(danger_pick.chosen.length() > 0.5,
		"G. and the driver has not stopped working (|chose| = %.2f)" % danger_pick.chosen.length())
	check(chosen_step.distance_to(field_at) > STEP,
		"G. and it walks out of the field rather than deeper into it (%.1f px from the centre vs %.1f at the start)" % [
			chosen_step.distance_to(field_at),player_at().distance_to(field_at)])
	var deepest := 0.0
	var best_exit := 0.0
	var worst_exit := 99999.0
	for i in DODGE_DIRECTIONS:
		var candidate := Vector2.RIGHT.rotated(i*TAU/DODGE_DIRECTIONS)
		if Utils.player.test_move(Utils.player.global_transform,candidate*WALL_STEP):
			deepest += 1
			continue
		var reach = ahead(candidate).distance_to(field_at)
		best_exit = maxf(best_exit,reach); worst_exit = minf(worst_exit,reach)
	check(deepest == 0.0,"G setup: no direction was wall-blocked, so all 16 were scored")
	check(chosen_step.distance_to(field_at) >= best_exit-0.01,
		"G. and it picks the LOWEST danger depth: the shallowest exit of the 16 (%.1f) equals its choice (%.1f), worst was %.1f" % [
			best_exit,chosen_step.distance_to(field_at),worst_exit])
	retire(field); await wait(0.3)

	# ---- H. ordinary encounter: the scorer is really called with target_boss = false ---------
	# This is the contract that stops the core going back to being boss-only. Two real rounds on
	# the SAME ordinary stage: once through the ordinary branch and once through the boss-target
	# branch, so both are shown to route through the same core.
	for boss_flag in [false,true]:
		await one_encounter(22,boss_flag,10.0)

	await clear_transients()
	LevelServer.state = "CAMP"
	print("B9 DRIVER CHECKS=",checks," FAILURES=",failures)
	if failures: get_tree().quit(1)
	else: await Demo.quit_game()

## One short REAL ordinary round, driven by the real driver, to prove the core is reached.
## It produces no clear rate: the pool is widened and the window is far shorter than a round.
func one_encounter(stage: int, boss_flag: bool, seconds: float) -> void:
	stop(); dismiss(); LevelServer.return_to_camp(); await wait(0.3)
	PlayerData.player_hp_max = 100000; PlayerData.player_hp = 100000
	configure(117,false)
	check(LevelServer.town.depart(stage,true),"H setup: depart stage "+str(stage))
	movement = 0; shots_fired = 0; last_position = Utils.player.global_position
	reset_dodge_telemetry()
	target_boss = boss_flag; driving = true; moving = true
	var start = Time.get_ticks_msec()
	while LevelServer.state == "COMBAT" and Time.get_ticks_msec()-start < int(seconds*1000.0):
		await wait(0.1)
	driving = false
	var tag := "boss-branch" if boss_flag else "ordinary-branch"
	check(LevelServer.state == "COMBAT",
		"H. the %s round really ran as an ordinary encounter (%s)" % [tag,LevelServer.state])
	check(dodge_decisions >= 30,
		"H. target_boss=%s calls the shared safe-movement core once per movement decision (%d decisions in %.0f s)" % [
			str(boss_flag),dodge_decisions,seconds])
	check(dodge_scored >= 16*5,
		"H. the 16-direction scan really scored candidates on the %s (%d scored)" % [tag,dodge_scored])
	check(shots_fired > 0,"H. the driver still fights while dodging (%d shots)" % shots_fired)
	check(movement > 0.0,"H. the driver still moves while dodging (%.1f px)" % movement)
	stop(); LevelServer.return_to_camp(); await wait(0.4)
