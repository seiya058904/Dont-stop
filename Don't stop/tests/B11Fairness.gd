extends "res://tests/M8Runtime.gd"

## B11 attack-fairness contract.
##
## The rule, in one sentence: every enemy attack must be answerable by correct play, and what the
## player was shown must be what actually happens.
##
## Both halves are proven here for the mechanisms that were wrong on origin/main:
##
##   A. THE COMPUTED WINDOW. The reaction interval is derived from this build's own movement speed,
##      the player's own collider and the attack's own damage half-width. The derivation is re-done
##      here from the LIVE collider rather than by trusting the constant.
##   B. THE LASER STATE MACHINE. TRACK follows the player; at LOCK the geometry freezes; moving the
##      player afterwards changes nothing; FIRE still lands on the frozen region; and there is a real
##      interval between LOCK and FIRE.
##   C. TELEGRAPH BEFORE DAMAGE, for a laser, a charge and a self-destruct.
##   D. THE CONTACT HIT-RATE LIMITER, which is what turned a late-Hell pile-up into an instant death.
##      Telegraphs must NOT be throttled by it, and the two cases are asserted separately.
const COS45 := 0.7071067811865476

## Every number below is read from the two production scripts rather than re-typed, so this test
## cannot agree with itself while disagreeing with the game. Neither script has a `class_name`, so
## their constants are read off a preloaded reference.
const MONSTER_BASE := preload("res://game/monster/DemoEnemy.gd")
const MONSTER_TACTICAL := preload("res://game/monster/TacticalEnemy.gd")

var player_radius := 0.0

func player_collider_radius() -> float:
	var collider = Utils.player.get_node_or_null("CollisionShape2D")
	if collider == null or collider.shape == null: return -1.0
	if collider.shape is CircleShape2D: return (collider.shape as CircleShape2D).radius
	return -1.0

func beams() -> Array:
	var out := []
	for node in get_tree().get_nodes_in_group("hostile_zone"):
		if node.mode == "line": out.append(node)
	return out

func lanes() -> Array:
	var out := []
	for node in get_tree().get_nodes_in_group("hostile_zone"):
		if node.mode == "charge": out.append(node)
	return out

func fuse_circles() -> Array:
	var out := []
	for node in get_tree().get_nodes_in_group("hostile_zone"):
		if node.mode == "circle" and float(node.damage) == 0.0: out.append(node)
	return out

func clean_actors():
	for group in ["monsters","combat_transient","hostile_zone"]:
		for node in get_tree().get_nodes_in_group(group):
			if is_instance_valid(node): node.queue_free()
	await wait(0.15)

func _ready():
	await boot()
	configure(124)
	PlayerData.player_hp_max = 100000; PlayerData.player_hp = 100000
	player_radius = player_collider_radius()

	# ---- A. the window is computed, and it is enough --------------------------------------
	var speed := float(Utils.player.SPEED)
	check(player_radius > 0.0,"the player really has a circular collider (%.1f)" % player_radius)
	check(is_equal_approx(player_radius,MONSTER_BASE.PLAYER_RADIUS),
		"the radius the windows are computed from is the collider the player really has (%.1f vs %.1f)"
			% [player_radius,MONSTER_BASE.PLAYER_RADIUS])
	check(speed > 0.0,"the player's speed is readable from the build (%.1f)" % speed)

	var beam_clear: float = MONSTER_TACTICAL.LASER_WIDTH+MONSTER_BASE.BEAM_SLOP+player_radius
	var beam_window: float = MONSTER_BASE.HUMAN_REACTION+(beam_clear/(speed*COS45))*MONSTER_BASE.REACTION_SAFETY
	var beam_escape: float = beam_clear/(speed*COS45)
	check(beam_window >= MONSTER_BASE.HUMAN_REACTION+beam_escape,
		"the beam's LOCK->FIRE interval (%.3fs) covers a human reaction plus a 45-degree escape (%.3fs)"
			% [beam_window,beam_escape])
	check(is_equal_approx(MONSTER_BASE.ESCAPE_COS,COS45),
		"the build's worst-case escape angle is the one this test assumes")
	check(MONSTER_BASE.TRACK_SECONDS < MONSTER_TACTICAL.BASE_WINDUP,
		"the tracking window is shorter than the shortest warning, so a freeze always has room")
	# The lead may spend the safety margin and nothing else. This is the exact quantity that made the
	# old laser undodgeable, so it is checked for the kinds that were worst on origin/main.
	for kind in ["beam","cross","cross_laser","artillery","root_shot","toxic_zone","band","tremor"]:
		var wanted: float = float(MONSTER_TACTICAL.LEAD_WANTED.get(kind,-1.0))
		check(wanted >= 0.0,"kind %s declares a wanted lead" % kind)
		check(wanted < beam_escape,
			"kind %s wants a lead (%.3fs) smaller than a whole escape (%.3fs)" % [kind,wanted,beam_escape])
	check(float(MONSTER_TACTICAL.LEAD_WANTED.get("charge",-1.0)) == 0.0 and
		float(MONSTER_TACTICAL.LEAD_WANTED.get("dash",-1.0)) == 0.0,
		"charges and dashes carry no lead at all")

	# ---- B. the laser state machine, driven through the REAL actor -------------------------
	LevelServer.return_to_camp()
	await wait(0.3)
	var town = LevelServer.town
	LevelServer.state = "COMBAT"
	Utils.player.global_position = town.global_position+Vector2(0.0,-40.0)
	var sentinel = M5Content.spawn("E14",town.monster_root,Utils.player.global_position+Vector2(200.0,0.0))
	check(sentinel != null,"the laser sentinel spawns")
	if sentinel == null:
		print("B11_FAIRNESS checks=",checks," failures=",failures+1)
		get_tree().quit(1)
		return
	sentinel.set_physics_process(false)
	sentinel.phase = "move"; sentinel.phase_time = 0.0
	sentinel.contact_cooldown = 99.0
	sentinel._begin("beam")
	var beam_list := beams()
	check(beam_list.size() == 1,"the beam creates exactly one warning lane")
	if beam_list.is_empty():
		print("B11_FAIRNESS checks=",checks," failures=",failures+1)
		get_tree().quit(1)
		return
	var zone = beam_list[0]
	var windup: float = sentinel.phase_time
	check(windup >= MONSTER_TACTICAL.BASE_WINDUP-0.001,
		"the sentinel waits at least the warning floor (%.3fs)" % windup)
	check(windup >= MONSTER_BASE.TRACK_SECONDS+sentinel.reaction_interval(sentinel.clearance("beam"))-0.001,
		"the warning really fits tracking plus the computed interval (%.3fs)" % windup)

	# TRACK: the aim follows the player while the lock is unfrozen.
	var seen_moving := false
	var frozen_at := -1.0
	var frozen_direction := Vector2.ZERO
	var frozen_point := Vector2.ZERO
	check(not bool(sentinel.aim_state().frozen),"the lock starts TRACKING")
	var step := 1.0/60.0
	var elapsed := 0.0
	while elapsed <= windup+step:
		sentinel.phase_time = windup-elapsed
		sentinel.step_lock(step)
		if not bool(sentinel.aim_state().frozen):
			var before: Vector2 = sentinel.locked_direction
			Utils.player.global_position += Vector2(0.0,5.0)
			sentinel.step_lock(0.0)
			if sentinel.locked_direction.distance_to(before) > 0.0001: seen_moving = true
		elif frozen_at < 0.0:
			frozen_at = elapsed
			frozen_direction = sentinel.locked_direction
			frozen_point = sentinel.locked_point
		elapsed += step
	check(seen_moving,"during TRACK the aim really follows a moving player")
	check(frozen_at > 0.0,"the lock really reaches FREEZE inside its own warning")
	check(frozen_at <= MONSTER_BASE.TRACK_SECONDS+step*2.0,
		"the freeze happens at the tracking window, not at the end of the warning (%.3fs)" % frozen_at)

	# FREEZE: moving the player after the lock changes NOTHING.
	var interval: float = windup-frozen_at
	check(interval >= sentinel.reaction_interval(sentinel.clearance("beam"))-step*2.0,
		"a real reaction interval exists between LOCK and FIRE (%.3fs)" % interval)
	check(interval >= MONSTER_BASE.HUMAN_REACTION,
		"and it is longer than a human reaction (%.3fs)" % interval)
	Utils.player.global_position += Vector2(0.0,120.0)
	sentinel.step_lock(step)
	check(sentinel.locked_direction.is_equal_approx(frozen_direction),
		"the frozen direction does not change when the player moves")
	check(sentinel.locked_point.is_equal_approx(frozen_point),
		"the frozen target point does not change when the player moves")
	var zone_direction: Vector2 = zone.direction
	sentinel.refresh_zones()
	check(zone.direction.is_equal_approx(zone_direction),
		"the warning lane keeps the frozen angle even if a subclass tries to re-aim it")

	# FIRE: the damaging geometry is the frozen geometry.
	check(zone.global_position.is_equal_approx(sentinel.global_position),
		"the damaging lane starts where the freeze recorded it")
	check(zone.direction.is_equal_approx(frozen_direction),
		"the damaging lane points where the freeze recorded it")
	check(is_equal_approx(zone.width,MONSTER_TACTICAL.LASER_WIDTH),
		"the LIVE lane's half-width equals the constant the window was computed from (%.1f vs %.1f)"
			% [zone.width,MONSTER_TACTICAL.LASER_WIDTH])
	check(not zone.activated,"the lane has not damaged anything before the interval elapses")

	# ---- C. telegraph before damage, three families ---------------------------------------
	check(float(zone.warning) >= MONSTER_BASE.HUMAN_REACTION,
		"the laser lane's own warning is a readable interval (%.3fs)" % zone.warning)
	await clean_actors()

	LevelServer.state = "COMBAT"
	# E04 is the DemoEnemy-roster charger and its pressure IS the dash's own body, so the readable
	# warning it owes the player is its WARN phase plus a dash that cannot turn. E03 is the
	# TacticalEnemy charger, which is the one that lays a lane; both shapes are checked.
	var charger = M5Content.spawn("E04",town.monster_root,Utils.player.global_position+Vector2(120.0,0.0))
	check(charger != null,"the light charger spawns")
	charger.set_physics_process(false)
	charger.phase = "move"; charger.phase_time = 0.0
	charger._physics_process(0.016)
	check(charger.phase == "warn","the light charge really enters its warning")
	check(charger.phase_time >= MONSTER_BASE.HUMAN_REACTION,
		"the light charge warns for a readable interval (%.3fs)" % charger.phase_time)
	check(not bool(charger.aim_state().frozen),"and its lock is tracking while the player can still move")
	await clean_actors()

	LevelServer.state = "COMBAT"
	var heavy = M5Content.spawn("E03",town.monster_root,Utils.player.global_position+Vector2(120.0,0.0))
	check(heavy != null,"the heavy charger spawns")
	heavy.set_physics_process(false)
	heavy.phase = "move"; heavy.phase_time = 0.0
	heavy._physics_process(0.016)
	check(String(heavy.get("attack_kind")) == "charge","the heavy charger really chooses a charge")
	var lane_list := lanes()
	check(lane_list.size() == 1,"the heavy charge creates a real lane before it moves")
	if not lane_list.is_empty():
		check(float(lane_list[0].warning) >= MONSTER_BASE.HUMAN_REACTION,
			"the charge lane warns for a readable interval (%.3fs)" % lane_list[0].warning)
		check(float(lane_list[0].damage) > 0.0,
			"the charge lane carries the hit, so the region that damages is the region drawn")
		check(float(lane_list[0].width) == MONSTER_BASE.CHARGE_WIDTH,
			"the lane's real half-width is the one its window was computed from (%.1f)" % lane_list[0].width)
		check(is_equal_approx(float(lane_list[0].direction.length()),1.0),
			"the lane has a real direction before it fires")
		check(not lane_list[0].activated,"and it has not damaged anything yet")
	await clean_actors()

	LevelServer.state = "COMBAT"
	# E06's engage reach is 34 px, so it is placed ON the player: the fuse is the point of the test,
	# not the approach.
	var bomber = M5Content.spawn("E06",town.monster_root,Utils.player.global_position)
	check(bomber != null,"the self-destructor spawns")
	bomber.set_physics_process(false)
	bomber.phase = "move"; bomber.phase_time = 0.0
	bomber._physics_process(0.016)
	check(String(bomber.get("attack_kind")) == "detonate",
		"the self-destructor really chooses its fuse (kind=%s)" % String(bomber.get("attack_kind")))
	var fuses := fuse_circles()
	check(fuses.size() >= 1,"the self-destruct shows a fuse circle before it fires")
	if not fuses.is_empty():
		check(float(fuses[0].warning) >= MONSTER_BASE.HUMAN_REACTION,
			"the fuse is a readable interval, not a frame (%.3fs)" % fuses[0].warning)
	await clean_actors()

	# ---- D. the contact hit-rate limiter, and what it must NOT throttle ---------------------
	LevelServer.state = "COMBAT"
	Utils.player.contact_immunity = 0.0
	var blocked_before: int = Utils.player.contact_blocked
	# Eight independent bodies touching on the same frame is the pile-up case: on origin/main that was
	# eight hits, because the cooldown lived on each attacker rather than on the player.
	for i in 8:
		Utils.player.onHit(1.0,self,1.0,"contact")
	var blocked_after: int = Utils.player.contact_blocked
	check(blocked_after-blocked_before == 7,
		"one contact hit lands and the other seven are dropped (%d of 8 dropped)" % (blocked_after-blocked_before))
	check(Utils.player.contact_immunity > 0.0,"the contact window is armed by a real hit")
	Utils.player.contact_immunity = 0.0
	for i in 4:
		Utils.player.onHit(0.0,self,0.0,"hazard_laser")
	check(not Utils.player.source_throttled("hazard_laser") and not Utils.player.source_throttled("shot:projectile"),
		"telegraphed damage is never throttled by the contact window")
	check(not Utils.player.source_throttled("contact"),"an expired window throttles nothing")

	await clean_actors()
	print("B11_FAIRNESS checks=",checks," failures=",failures)
	if failures: get_tree().quit(1)
	else: await Demo.quit_game()
