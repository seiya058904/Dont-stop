extends "res://game/monster/Monster 2/Monster2.gd"

var role = "E02"
var phase = "spawn"
var phase_time = 0.6
var locked_direction = Vector2.ZERO
## The point a locked attack was aimed at. DemoEnemy's own attacks aim by direction only, but the
## shared lock writes both, and TacticalEnemy (which extends this class) aims artillery at it.
var locked_point = Vector2.ZERO
var contact_cooldown = 0.0

## ---- B10: bounded tracking lock (the ONE implementation, in the base class) ----------------
##
## WHY. Every locked attack used to freeze `locked_direction` / `locked_point` the instant the
## attack was chosen - i.e. at the START of the warning - with no lead at all. The player moves
## ~106 px/s, so a 0.6-0.75 s warning let them walk 64-80 px out of a fixed line, and a beam lane
## 8 px wide or a 40 px artillery circle was then trivially escaped by any lateral step.
## tests/B10Threat.gd measured the consequence: against a player who simply held ONE direction at
## full speed, every special attack in the game scored exactly 0 hits.
##
## The fix is the brief's own: the aim FOLLOWS the player for the first part of the warning and
## FREEZES for the last part, and the frozen value carries a BOUNDED lead of 0.15-0.35 s of the
## player's own velocity. Never a perfect prediction, and never a lock that persists to the damage
## frame: after the freeze there is still a third to a half of the warning left to step out of.
## The player has to genuinely change direction to break the aim - and still can.
##
## This lives in DemoEnemy because it is the base of BOTH rosters (TacticalEnemy extends it), so
## there is exactly one implementation and the two rosters cannot drift apart.
const LOCK_TRACK_SHARE := 0.55
const LOCK_LEAD_MIN := 0.15
const LOCK_LEAD_MAX := 0.35
## A PROJECTILE gets a different cap, and the reason is not a loophole. A footprint appears
## instantly where it was aimed, so leading one by more than a fraction of a second would be an
## unavoidable hit. A projectile has to FLY and cannot correct in the air, so leading it by its own
## travel time is a lead shot, not a homing shot: a player who changes direction or speed after it
## is fired still walks away from it. Without this, a 120 px/s pellet crossing 150 px arrives
## 1.25 s late while the aim only compensated 0.3 s - so holding ONE direction stayed a complete
## defence, which is exactly the behaviour this round is about.
const PROJECTILE_LEAD_MAX := 1.10
var lock_track := 0.0
var lock_lead := 0.0
var lock_frozen := true

## The player's top speed is read from the build, never assumed; the lead is clamped to it so a
## knockback or a dash cannot turn the prediction into a teleport.
func player_speed_cap() -> float:
	var speed := 110.0
	if is_instance_valid(Utils.player) and Utils.player.SPEED > 0.0:
		speed = float(Utils.player.SPEED)
	return speed

## Lead for a projectile attack. A round has to be aimed where the player will be when the ROUND
## ARRIVES, so the lead is the wind-up still to run PLUS the flight time - not the flight time
## alone. Ignoring the remaining wind-up left the volley about 26 px short against a player who
## kept one direction (the flight was compensated, the 0.34 s of warning left after the lock
## froze was not). Real information only: distance, the attack's own muzzle speed, and its own
## warning length.
func projectile_lead(muzzle_speed: float, warning: float) -> float:
	if not is_instance_valid(Utils.player) or muzzle_speed <= 0.0: return LOCK_LEAD_MIN
	var remaining := maxf(0.0,warning*(1.0-LOCK_TRACK_SHARE))
	var flight := global_position.distance_to(Utils.player.global_position)/muzzle_speed
	return clampf(remaining+flight,LOCK_LEAD_MIN,PROJECTILE_LEAD_MAX+remaining)

## Take a fresh lock at the start of a warning. `warning` is the full warning length in seconds and
## `cap` the largest lead this kind of attack may carry (see PROJECTILE_LEAD_MAX).
func begin_lock(warning: float, lead: float, cap := LOCK_LEAD_MAX) -> void:
	lock_track = maxf(0.05,warning)*LOCK_TRACK_SHARE
	lock_lead = clampf(lead,LOCK_LEAD_MIN,maxf(LOCK_LEAD_MIN,cap))
	lock_frozen = lock_track <= 0.0

## Aim at a point, optionally leading the player's own velocity by `lead` seconds. Real
## information only: the player's position and velocity, and this actor's own attack state.
func aim_at(point: Vector2, lead: float) -> void:
	if not is_instance_valid(Utils.player): return
	var aim := point
	if lead > 0.0:
		aim = point+Utils.player.velocity.limit_length(player_speed_cap())*lead
	locked_point = aim
	locked_direction = global_position.direction_to(aim)

## One step of the lock. While tracking it follows the player's CURRENT position with no lead; at
## the freeze it applies the bounded lead once. `refresh_zones()` is what lets a subclass carry
## footprints that are already on the ground along with the lock.
func step_lock(delta: float) -> void:
	if lock_frozen or phase != "warn": return
	lock_track -= delta
	if lock_track > 0.0:
		aim_at(Utils.player.global_position,0.0)
		refresh_zones()
		return
	lock_frozen = true
	aim_at(Utils.player.global_position,lock_lead)
	refresh_zones()

## Overridden by TacticalEnemy, which owns warning footprints that follow the lock.
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
func shot(dir: Vector2, speed_value = 100.0, damage_value = 1.0, muzzle_flash = true, style := "projectile", control := 0.0) -> Node:
	if get_tree().get_nodes_in_group("enemy_projectiles").size() >= 180: return null
	var node = CharacterBody2D.new(); node.set_script(load("res://game/monster/EnemyShot.gd"))
	node.position = global_position; node.velocity = dir*speed_value; node.owner_ref = weakref(self)
	node.damage = damage_value; node.style = style; node.control = control
	get_tree().current_scene.add_child(node)
	if muzzle_flash: preload("res://game/effects/HostileVFX.gd").emit_at(get_tree().current_scene,global_position,12,dir,style)
	return node

func _physics_process(delta):
	if is_die or not is_instance_valid(Utils.player) or Utils.player.is_dead or LevelServer.state != "COMBAT": return
	phase_time -= delta
	contact_cooldown = maxf(0,contact_cooldown-delta)
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
				# B10: the charge is now SIZED TO ARRIVE. It used to run a fixed 0.45 s at 240 px/s =
				# 108 px, while its own engage gate opens anywhere inside 170 px - so from most of
				# its own firing range the dash simply stopped short of the player.
				# tests/B10Threat.gd measured exactly 0 hits per trial against a player who never
				# moved at all, which is the clearest possible statement that it had no threat.
				phase_time = clampf((distance+22.0)/240.0,0.3,0.85)
			else:
				var count = 5 if LevelServer.level>=6 else 1
				if is_elite: count += 3
				# B10: 85/95 -> 120, and the centre pellet leads with the lock's bounded lead.
				# Still slower than the player (106), so a read-and-move answer keeps working; it
				# is just no longer free to ignore.
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
		move_and_slide()
		if distance < 19 and contact_cooldown <= 0:
			Utils.player.onHit(contact_damage(),self,1.0,"contact")
			contact_cooldown = 0.8
		if phase_time <= 0 or get_slide_collision_count() > 0:
			if role == "E04" and is_elite:
				# Elite charge is a two-step: the second dash re-locks onto the player.
				is_elite = true
				locked_direction = global_position.direction_to(Utils.player.global_position)
				phase = "warn"; phase_time = 0.4
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
		if role == "E04":
			# A charge is a footprint: a bounded fraction-of-a-second lead is all it may carry.
			begin_lock(0.6,0.25)
		else:
			# A pellet volley leads by its own flight time: it cannot correct in the air, so
			# this punishes a player who keeps one direction and is still walkable-away-from.
			begin_lock(0.75,projectile_lead(145.0,0.75),PROJECTILE_LEAD_MAX+0.75)

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
		if phase == "warn":
			preload("res://game/effects/CombatTelegraph.gd").paint(self,"charge",locked_direction,0,108,19,0,1-phase_time/0.6,false,0.0,{ },true,"charge")
	if role == "E05":
		draw_arc(Vector2(0,-12),10,PI,TAU,12,Color(0.7,1,0.4),2)
		if phase == "warn":
			draw_circle(Vector2(0,-20),3+sin(phase_time*18),Color(1,0.6,0.3))
			# A short projectile-family lane makes the muzzle direction readable, so the
			# volley is never a surprise in fog.
			preload("res://game/effects/CombatTelegraph.gd").paint(self,"line",locked_direction,0,150,10,0,clampf(1.0-phase_time/0.75,0,1),false,0.0,{ },true,"projectile")
