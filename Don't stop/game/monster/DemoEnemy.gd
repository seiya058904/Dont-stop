extends "res://game/monster/Monster 2/Monster2.gd"

var role = "E02"
var phase = "spawn"
var phase_time = 0.6
var locked_direction = Vector2.ZERO
## The point a locked attack was aimed at. DemoEnemy's own attacks aim by direction only, but the
## shared lock writes both, and TacticalEnemy (which extends this class) aims artillery at it.
var locked_point = Vector2.ZERO
var contact_cooldown = 0.0
var _last_draw_phase := ""
var _last_draw_lock_frozen := true

## ---- B11: the ONE bounded attack lock, shared by both rosters -------------------------------
##
## WHY THIS SECTION WAS REWRITTEN. B10 replaced a snapshot-at-warning-start with a lock that
## followed the player for 55% of the warning and then froze carrying a 0.15-0.35 s LEAD of the
## player's own velocity. The lead is what broke the brief: it aims where the player WILL be,
## which eats exactly the time the player needs to leave the marked area.
##
## Measured on the real numbers of this build (player SPEED 110 px/s, `CircleShape2D` radius 7
## from game/hero/Hero.tscn, `HostileZone` beam damage test `distance_to_segment <= width+6 = 16`):
##
##   warning 0.65 s, freeze at 55% -> 0.2925 s left, lead 0.30 s, beam half-width 16 px
##   * player standing still on the centreline at the freeze:
##     displacement available = 0.2925 s * 110 = 32.2 px, and the lead points 0.30 s * 110 = 33 px
##     AHEAD of them, so their own movement has to cover the lead before it covers anything else.
##     32.2 px of travel against 33 px of lead leaves them ~1 px inside the beam. Net escape: nil.
##   * player already moving along the beam at the freeze: 0 px escape. That is the "laser keeps
##     tracking me, there is no way to dodge" report, and it is arithmetically exact.
##   * best possible perpendicular escape: 0.707 * 110 * max(0, 0.2925 - 0.30) = 0 px.
##
## So the mechanism was not "hard", it was unfair, and it was unfair by construction. B11 fixes
## the construction, not the number:
##
##   1. A reaction interval is COMPUTED, never typed in. It is the time a player needs to leave
##      the frozen damage area from its worst legal starting point (dead centre), and it is
##      derived from this build's own movement speed, the player's own collision radius and the
##      attack's own damage half-width:
##
##        escape   = (half_width + player_radius) / speed   -- the pure travel term
##        reaction = HUMAN_REACTION + escape * REACTION_SAFETY
##
##      `HUMAN_REACTION` is 0.25 s because zero is not a reaction, it is a frame. `REACTION_SAFETY`
##      is 1.2, a margin on the travel term only.
##   2. The freeze happens at a fixed short TRACK window after the aim starts, and the lock's own
##      requirement extends the attack's warning until the full reaction interval fits after the
##      freeze. An attack can therefore never be authored back into an undodgeable state by
##      shortening its warning: shortening it makes the freeze earlier instead.
##   3. From the freeze onward the geometry is FROZEN: target point, direction, angle, swept arc,
##      clipped length, damage test. `step_lock()` may not touch any of it, and `refresh_zones()`
##      may not be called at all. FIRE attacks the frozen region or nothing.
##   4. A lead is still allowed, because a stationary player must not be able to ignore a
##      telegraph forever - but it is CAPPED by the same computed interval, so it can only ever
##      consume the safety margin and never the escape time:
##
##        lead_cap = max(0, escape_time - escape * REACTION_SAFETY * LEAD_FRACTION)
##
##      With the numbers above escape_time is 0.483 s and escape is 0.402 s, so the cap lands at
##      0.19 s. Every caller routes through `begin_lock()`, so no attack can opt out.
const TRACK_SECONDS := 0.35
const HUMAN_REACTION := 0.25
const REACTION_SAFETY := 1.2
const LEAD_FRACTION := 0.5
## Player collision radius, read from game/hero/Hero.tscn (`CircleShape2D` radius = 7.0). It is
## a constant because the offset must exist before a player is in the tree, and a test asserts it
## still equals the real collider.
const PLAYER_RADIUS := 7.0
## cos(45 degrees). See `escape_seconds()` for why the window is built from the 45-degree case.
const ESCAPE_COS := 0.7071067811865476
## A damage footprint's own half-extent used for the "can I leave it" calculation.
const BEAM_SLOP := 6.0

var lock_track := 0.0
var lock_lead := 0.0
var lock_frozen := true
## Observability for the B11 fairness audit and the read-only Web probe. Read-only: nothing in
## the product branches on these.
var lock_frozen_at := 0.0
var lock_fire_at := 0.0
var lock_geometry := {}
## Lane half-width of a charge footprint. `zone()` sets 18 for a non-boss charge and 22 for a
## boss one; both are declared here because both windows are computed here, and a boss charge that
## used the narrow number would be a silent unfairness. Declared on the BASE class because the base
## class computes the reaction window for the roster it owns (E02/E04/E05).
const CHARGE_WIDTH := 18.0
const BOSS_CHARGE_WIDTH := 22.0

## The player's top speed is read from the build, never assumed.
func player_speed_cap() -> float:
	var speed := 110.0
	if is_instance_valid(Utils.player) and Utils.player.SPEED > 0.0:
		speed = float(Utils.player.SPEED)
	return speed

## Seconds a player needs to travel `required_clearance` px sideways, at the WORST useful escape
## ANGLE. A player on a beam's centreline has to move perpendicular to it, and perpendicular is the
## LONGEST useful escape: an escape at 45 degrees covers the clearance with a perpendicular
## component of only cos(45) of the distance travelled. Bounding the window by the perpendicular
## case alone would therefore leave the 45-degree case short, so the window is built from the
## 45-degree case and the perpendicular case is then covered with room to spare.
func escape_seconds(required_clearance: float) -> float:
	return maxf(0.02,required_clearance/(maxf(1.0,player_speed_cap())*ESCAPE_COS))

## The reaction interval an attack MUST leave between its freeze and its first damaging frame.
## Prints nothing; the audit reads it through `aim_state()`.
func reaction_interval(required_clearance: float) -> float:
	return HUMAN_REACTION+escape_seconds(required_clearance)*REACTION_SAFETY

## The full warning an attack needs so that `reaction_interval()` fits after `TRACK_SECONDS`.
func warning_for(required_clearance: float) -> float:
	return TRACK_SECONDS+reaction_interval(required_clearance)

## Largest lead this attack may carry. See LEAD_FRACTION above: it may spend the safety margin
## and nothing else, so the player's own escape time is never consumed by prediction.
func lead_cap(required_clearance: float) -> float:
	var escape := escape_seconds(required_clearance)
	return maxf(0.0,escape-escape*REACTION_SAFETY*LEAD_FRACTION)

## Half-extent of the damage footprint a `kind` really tests against the player centre. Mirrors
## HostileZone.step()'s own test so the number the window is computed from is the number that
## hurts: `distance_to_segment <= width+6` and `distance <= radius`.
func required_clearance(kind: String, footprint: float, width: float) -> float:
	var half := footprint
	if kind in ["line","charge"]: half = width+BEAM_SLOP
	return half+PLAYER_RADIUS

## The volley's own envelope: a pellet hurts inside 12 px of its path (EnemyShot), plus the
## player's radius. Kept as a function so the telegraph and the reaction window cannot drift.
func volley_clearance() -> float:
	return 12.0+PLAYER_RADIUS

## Lead for a volley. A round has to be aimed where the player will be when the ROUND ARRIVES,
## so the natural lead is the wind-up still to run plus the flight time. It is then clamped by
## `lead_cap()` like every other attack - a projectile cannot be ordered to spend the player's
## escape time just because it flies slowly.
func projectile_lead(muzzle_speed: float, remaining_windup: float) -> float:
	if not is_instance_valid(Utils.player) or muzzle_speed <= 0.0: return 0.0
	var flight := global_position.distance_to(Utils.player.global_position)/muzzle_speed
	return maxf(0.0,remaining_windup)+flight

## Take a fresh lock. `full_warning` is the warning the attack wants (it is extended to
## `warning_for()` if it is too short), `lead_wanted` the lead the attack would like, and
## `clearance` the distance the player must put between themselves and the frozen centre.
## Returns the seconds the caller must keep the warning running so that the interval between the
## freeze and the first damaging frame is at least the computed reaction interval.
func begin_lock(full_warning: float, lead_wanted: float, clearance: float) -> float:
	var reaction := reaction_interval(clearance)
	var cap := lead_cap(clearance)
	lock_track = TRACK_SECONDS
	lock_lead = clampf(lead_wanted,0.0,cap)
	lock_frozen = false
	lock_frozen_at = 0.0
	lock_fire_at = 0.0
	lock_geometry = {}
	var wanted := maxf(full_warning,0.0)
	if wanted < TRACK_SECONDS+reaction:
		wanted = TRACK_SECONDS+reaction
	return maxf(reaction,wanted-lock_track)

## Aim at a point, optionally leading the player's own velocity by `lead` seconds. Called with a
## non-zero lead exactly once, at the freeze.
func aim_at(point: Vector2, lead: float) -> void:
	if not is_instance_valid(Utils.player): return
	var aim := point
	if lead > 0.0:
		aim = point+Utils.player.velocity.limit_length(player_speed_cap())*lead
	locked_point = aim
	locked_direction = global_position.direction_to(aim)
	lock_geometry = {"origin":global_position,"point":locked_point,"direction":locked_direction,
		"lead":lead,"frozen_at":lock_frozen_at}

## One step of the lock. While tracking it follows the player's CURRENT position with NO lead.
## At the freeze it takes the bounded lead once and then never touches the geometry again.
func step_lock(delta: float) -> void:
	if lock_frozen or phase != "warn": return
	lock_track -= delta
	if lock_track > 0.0:
		aim_at(Utils.player.global_position,0.0)
		refresh_zones()
		return
	lock_frozen = true
	lock_frozen_at = Time.get_ticks_msec()/1000.0
	aim_at(Utils.player.global_position,lock_lead)
	# The last call of this function, ever, for this attack: after it returns the geometry is
	# frozen and refresh_zones() is unreachable for the rest of the wind-up.
	refresh_zones()

## Read-only view of the lock for tests and the audit. Nothing in the product branches on it.
func aim_state() -> Dictionary:
	return {"frozen":lock_frozen,"track":lock_track,"lead":lock_lead,
		"frozen_at":lock_frozen_at,"fire_at":lock_fire_at,"geometry":lock_geometry.duplicate()}

func refresh_zones() -> void:
	pass

func _ready():
	super._ready()
	match role:
		"E02":
			HP = 1.2
			SPEED = 105
			sprite_body.scale = Vector2(0.65,0.65)
		"E04":
			HP = 5
			SPEED = 65
		"E05":
			HP = 3
			SPEED = 50
	$AtkTimer.stop()

func contact_damage() -> float:
	return 1.0+(damage_scale-1.0)*DemoConfig.CONTACT_DAMAGE_WEIGHT

func contact_reach() -> float:
	# A promoted pack runner tightens the bracket instead of hitting harder.
	return 24.0 if role == "E02" and is_elite else 17.0

## Shared by every ranged actor. Kept here so the 180-projectile ceiling and the fog
## mirroring apply to the DemoEnemy roster too: E05 used to add its pellets directly and
## was the one path that could push the count past the cap.
## Returns the created projectile (null when the ceiling refused it) so a subclass can
## register it for cleanup; a Node is truthy, so existing `if shot(...)` callers still work.
func shot(dir: Vector2, speed_value = 100.0, damage_value = 1.0, muzzle_flash = true, style := "projectile", control := 0.0, bounces := 0) -> Node:
	if preload("res://game/monster/EnemyShot.gd").live_count >= preload("res://game/monster/EnemyShot.gd").capacity_limit: return null
	var node = CharacterBody2D.new(); node.set_script(load("res://game/monster/EnemyShot.gd"))
	node.position = global_position; node.velocity = dir*speed_value; node.owner_ref = weakref(self)
	node.damage = damage_value; node.style = style; node.control = control
	node.bounces_left = bounces if control <= 0 else 0
	get_tree().current_scene.add_child(node)
	if muzzle_flash: preload("res://game/effects/HostileVFX.gd").emit_at(get_tree().current_scene,global_position,12,dir,style)
	return node

func _physics_process(delta):
	if is_die or not is_instance_valid(Utils.player) or Utils.player.is_dead or LevelServer.state != "COMBAT": return
	phase_time -= delta
	contact_cooldown = maxf(0,contact_cooldown-delta)
	# E02/E04 draw static role marks outside their phase transitions. E05's muzzle pulse is the
	# only continuously changing DemoEnemy drawing, and only after its aim is frozen. Avoid asking
	# CanvasItem to rebuild the same geometry for every ordinary enemy on every physics tick.
	if phase != _last_draw_phase or lock_frozen != _last_draw_lock_frozen or (role == "E05" and phase == "warn" and lock_frozen):
		_last_draw_phase = phase
		_last_draw_lock_frozen = lock_frozen
		queue_redraw()
	if phase == "spawn":
		if phase_time <= 0: phase = "move"
		return
	var distance = global_position.distance_to(Utils.player.global_position)
	if role == "E02":
		is_atk = false
		super._physics_process(delta)
		if distance < contact_reach() and contact_cooldown <= 0:
			Utils.player.onHit(contact_damage(),self,1.0,"contact")
			contact_cooldown = 0.8
		return
	if phase == "warn":
		step_lock(delta)
		if phase_time <= 0:
			if role == "E04":
				phase = "dash"
				# The charge is SIZED TO ARRIVE, and it keeps that property: it runs for exactly the
				# time it needs to cross the distance the lock was taken at, at its own dash speed.
				# The frozen direction is what the warning showed, so arriving means arriving on the
				# marked lane - not chasing a player who has already stepped off it.
				phase_time = clampf((distance+22.0)/240.0,0.3,0.85)
			else:
				var count = 5 if LevelServer.level>=6 else 1
				if is_elite: count += 3
				# 120 px/s is still slower than the player, so a read-and-move answer works: step
				# perpendicular to the frozen lane and the volley crosses behind. The centre pellet
				# is the fast one and it carries the lock's bounded lead.
				var centre := int(count)/2
				for i in count:
					var spread = 0.2
					var speed = 145.0 if i == centre else 120.0
					shot(locked_direction.rotated((i-(count-1)*0.5)*spread),speed,1.0,true,"projectile")
				phase = "recover"
				phase_time = 1.1
		return
	if phase == "dash":
		velocity = locked_direction*240
		_measured_move()
		if distance < 19 and contact_cooldown <= 0:
			Utils.player.onHit(contact_damage(),self,1.0,"contact")
			contact_cooldown = 0.8
		if phase_time <= 0 or get_slide_collision_count() > 0:
			if role == "E04" and is_elite:
				# Elite charge is a two-step, and the second step gets a FULL new warning: a fresh
				# tracking phase, a fresh freeze, and the computed reaction interval after it. The
				# old fixed 0.4 s warning was shorter than the interval a charge needs, which is how
				# a "two-step" turned into an unavoidable second hit.
				is_elite = true
				phase = "warn"
				begin_lock(0.6,0.0,required_clearance("charge",0.0,CHARGE_WIDTH))
				preload("res://game/effects/HostileVFX.gd").emit_at(get_tree().current_scene,global_position,16,locked_direction,"charge")
				return
			phase = "recover"
			phase_time = 0.8
		return
	if phase == "recover":
		is_atk = false
		super._physics_process(delta)
		if phase_time <= 0: phase = "move"
		return
	is_atk = false
	super._physics_process(delta)
	if distance < 170 and distance > 35 and Combat.clear_line(global_position,Utils.player.global_position):
		phase = "warn"
		# The wanted warning is the SMALLEST value that still fits the freeze plus the computed
		# reaction interval, so it cannot regress by an edit and cannot be padded by accident.
		if role == "E04":
			# A charge is a contact footprint: the player leaves it by stepping off the lane, so
			# the clearance is the player's own diameter plus the dash's contact reach. No lead:
			# a charge aimed at where the player is GOING is a charge that cannot be out-walked.
			var clearance := required_clearance("charge",0.0,CHARGE_WIDTH)
			phase_time = begin_lock(warning_for(clearance),0.0,clearance)
		else:
			# A pellet volley may lead by its own flight time, bounded by lead_cap().
			var clearance := volley_clearance()
			var reaction := reaction_interval(clearance)
			phase_time = begin_lock(warning_for(clearance),projectile_lead(145.0,reaction),clearance)

func onAtk():
	pass

func _on_animated_sprite_2d_frame_changed():
	pass

func _draw():
	super._draw()
	if is_die: return
	if phase == "spawn": draw_arc(Vector2.ZERO,14,0,TAU,16,Color(0.6,0.85,1,0.6),1)
	if role == "E04":
		draw_polyline(PackedVector2Array([Vector2(-8,-18),Vector2(0,-25),Vector2(8,-18)]),Color(1,0.65,0.2),2)
		# The charge's warning is the real `HostileZone` lane created in _physics_process: it
		# carries the true length and the true width, and it is the geometry that will hurt.
		# The old extra `paint()` lane here was a second, decorative overlay drawn 108 px long
		# against a real zone of hundreds of pixels, so the two disagreed on screen.
	if role == "E05":
		draw_arc(Vector2(0,-12),10,PI,TAU,12,Color(0.7,1,0.4),2)
		if phase == "warn" and lock_frozen:
			# A muzzle glow plus a lane as long as the volley's own damage envelope, drawn only
			# once the aim is FROZEN, because that is the moment the lane is a promise.
			draw_circle(Vector2(0,-20),3+sin(phase_time*18),Color(1,0.6,0.3))
			preload("res://game/effects/CombatTelegraph.gd").paint(self,"line",locked_direction,0,150,volley_clearance(),0,1.0,false,0.0,{ },true,"projectile")
