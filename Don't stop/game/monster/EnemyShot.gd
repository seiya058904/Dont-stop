extends CharacterBody2D
static var live_count := 0
const CAPACITY := 180
static var capacity_limit := CAPACITY
static var _fog_cache_frame := -1
static var _fog_cache_active := false
static var _fog_cache_radius := 4096.0
var registered := false
var _ink_dirty := false
var _body_ink: Node2D
var _trail_ink := PackedVector2Array()
var _fog_position := Vector2.ZERO
var _fog_tip := Vector2.ZERO
var bounces_left := 0
var bounces_done := 0
var lifetime := 3.2
var owner_ref: WeakRef
var life = 0.0
var epoch = 0
var trail: Array[Vector2] = []
var damage = 1.0
## B批: the shot carries its family so the ink matches the warning that preceded it, and an
## optional control payload. `control` is the ONLY new mechanic a projectile gained, and it
## goes through Hero.apply_root() rather than a second stun system, so CC immunity, the
## epoch reset and the "still able to aim/fire/reload" contract all keep working.
var style = "projectile"
var control = 0.0
const INK = {
	"projectile":Color(1,0.55,0.15),
	"root":Color(0.78,0.42,1.0),
	"poison":Color(0.4,1,0.6),
	"laser":Color(0.45,0.95,1.0),
	"ricochet":Color(1.0,0.4,0.8)
}
func _enter_tree():
	if live_count >= capacity_limit:
		set_physics_process(false); queue_free(); return
	live_count += 1
	registered = true

func _ready():
	# B11.2 test-only counter (game/diag/B11Probe.gd): kept so the AFTER run can report the burst
	# cost as zero rather than merely absent.
	if B11Probe.enabled: B11Probe.shot_created += 1
	if not registered:
		set_physics_process(false); queue_free(); return
	if bounces_left > 0:
		bounces_left = clampi(bounces_left,1,2)
		lifetime = 5.2
	add_to_group("combat_transient")
	add_to_group("enemy_projectiles")
	epoch = LevelServer.epoch
	collision_layer = 0
	# Walls, and only walls. Every body that can block a shot carries layer 32: the arena's own
	# static geometry does (`CombatArena._ready`, 2147483648) and so do the town and snow building
	# slabs, whose published layer is 2147483649 = 1 + 32. Neither the hero (25 = 1+8+16) nor a
	# monster (3 = 1+2) carries layer 32.
	#
	# The old mask asked for layer 1 as well, which is the layer the hero AND every monster share,
	# and then spent one collision exception per live monster - plus one for the player - undoing it
	# again. Measured on the worst-load profile: 83 exceptions per shot, 26,846 physics-server pair
	# insertions in a 45 s run, all of it arriving in bursts the moment a barrage is fired.
	#
	# Nothing about the hit changes. The projectile never produced damage through this body's
	# contact - `_physics_process` measures the distance from the player to the segment the shot
	# travelled this frame, and applies the hit itself. This mask only ever decided what STOPPED the
	# shot, which is the map. `tests/B11ShotLayer.gd` asserts all four halves of that contract.
	collision_mask = 2147483648
	var shape = CollisionShape2D.new()
	shape.shape = CircleShape2D.new()
	shape.shape.radius = 3
	add_child(shape)
	z_index = 5
	_body_ink = Node2D.new()
	_body_ink.draw.connect(_draw_body)
	add_child(_body_ink)

func _exit_tree():
	if registered:
		live_count -= 1
		registered = false

func _draw():
	var started := Time.get_ticks_usec() if B11Probe.enabled else 0
	_draw_ink()
	if B11Probe.enabled: B11Probe.cost("enemy_shot_draw",started)

func _draw_ink():
	var ink = INK.get(style,INK.projectile)
	# B11.2 visual isolation (test-only): the projectile BODY always draws - only the decorative
	# trail segments are switchable, because the body is what the player actually dodges.
	if not B11Probe.iso_trails:
		for i in range(1,_trail_ink.size()):
			draw_line(_trail_ink[i-1],_trail_ink[i],Color(ink.r,ink.g,ink.b,0.1+0.45*i/_trail_ink.size()),1.0+1.5*i/_trail_ink.size(),true)

# Geometry and ink are fixed for the projectile lifetime except control pulses.
# Retain its body commands; only the moving trail needs rebuilding each frame.
func _draw_body() -> void:
	var ink = INK.get(style,INK.projectile)
	_body_ink.draw_circle(Vector2.ZERO,4,Color(ink.r*0.15,ink.g*0.15,ink.b*0.15))
	_body_ink.draw_circle(Vector2.ZERO,2.8,Color(ink.r,ink.g,ink.b))
	if style in ["laser","ricochet"]:
		_body_ink.draw_polyline(PackedVector2Array([Vector2(-5,0),Vector2(0,-4),Vector2(5,0),Vector2(0,4),Vector2(-5,0)]),Color(ink,0.9),1)
	elif style == "poison":
		for side in [-1,1]: _body_ink.draw_rect(Rect2(Vector2(side*4,-1),Vector2(2,2)),Color(ink,0.85))
	if control > 0.0:
		# Control attacks pulse an outer waveform ring so they never read as plain damage.
		_body_ink.draw_arc(Vector2.ZERO,5.5+1.5*sin(life*22.0),0,TAU,14,Color(ink.r,ink.g,ink.b,0.75),1.4,true)
		_body_ink.draw_arc(Vector2.ZERO,7.5,0,TAU,14,Color(0.95,0.8,1,0.45),1.0,true)
# Several physics steps may precede one display frame. Only the last trail
# state can be presented; keep every sweep, reflection and lifetime step, but
# submit that final drawing once instead of rebuilding it between substeps.
func _process(_delta):
	if _ink_dirty and not is_queued_for_deletion():
		_ink_dirty = false
		var points := PackedVector2Array()
		for point in trail: points.append(to_local(point))
		var changed := points.size() != _trail_ink.size()
		if not changed:
			for i in points.size():
				# Ignore only world-to-local float cancellation below 0.0001
				# logical pixels; compare to retained ink, so errors never accumulate.
				if points[i].distance_squared_to(_trail_ink[i]) > 0.00000001:
					changed = true; break
		if changed:
			_trail_ink = points
			queue_redraw()
		if control > 0.0 and is_instance_valid(_body_ink): _body_ink.queue_redraw()
		_mirror_into_fog()

static func _refresh_fog_cache() -> void:
	var frame := Engine.get_process_frames()
	if frame == _fog_cache_frame:
		return
	_fog_cache_frame = frame
	_fog_cache_active = ArenaVisibility.fog_active()
	_fog_cache_radius = ArenaVisibility.fair_radius() if _fog_cache_active else 4096.0

func _physics_process(delta):
	var started := Time.get_ticks_usec() if B11Probe.enabled else 0
	_step(delta)
	if B11Probe.enabled: B11Probe.cost("enemy_shot_step",started)

func _step(delta):
	life += delta
	if life > lifetime or epoch != LevelServer.epoch or not is_instance_valid(Utils.player) or (owner_ref and (not is_instance_valid(owner_ref.get_ref()) or owner_ref.get_ref().is_die)):
		queue_free()
		return
	trail.append(global_position)
	if trail.size()>3: trail.pop_front()
	_ink_dirty = true
	_fog_position = global_position
	_fog_tip = global_position+velocity.normalized()*14.0
	var remaining = velocity*delta
	for iteration in 4:
		var previous = global_position
		var collision = move_and_collide(remaining)
		# Check the travelled subsegment BEFORE the wall: a later wall must not erase a hit.
		if hit_segment(previous,global_position): return
		if collision == null: return
		var normal = collision.get_normal()
		if bounces_left <= 0 or normal.length_squared() < 0.5 or collision.get_travel().length_squared() < 0.000001:
			queue_free(); return
		bounces_left -= 1; bounces_done += 1
		velocity = velocity.bounce(normal)
		remaining = collision.get_remainder().bounce(normal)
		trail.clear()
		preload("res://game/effects/HostileVFX.gd").emit_at(get_tree().current_scene,global_position,8,normal,"ricochet")
		if remaining.length_squared() < 0.000001: return
	queue_free()

func hit_segment(previous: Vector2, current: Vector2) -> bool:
	var player_position := Utils.player.global_position
	# The exact segment test below is still authoritative. This conservative AABB
	# reject only skips segments that cannot possibly enter the 12 px hit radius,
	# avoiding a Geometry2D call for shots already outside the player's lane.
	var margin := 12.0
	if player_position.x < minf(previous.x,current.x)-margin or player_position.x > maxf(previous.x,current.x)+margin or player_position.y < minf(previous.y,current.y)-margin or player_position.y > maxf(previous.y,current.y)+margin:
		return false
	if Geometry2D.get_closest_point_to_segment(player_position,previous,current).distance_to(player_position) < margin:
		# Barrage pellets intentionally carry fractional pressure; other attacks keep
		# Hero's existing one-point minimum.
		# The tag carries the shot's FAMILY, not just "a projectile": a 23-pellet artillery ring
		# and a single aimed pellet are different balance questions, and the attacker alone
		# cannot tell them apart because the barrage reports the boss as its owner.
		Utils.player.onHit(damage,owner_ref.get_ref() if owner_ref else null,0.0,
			("control_shot:" if control > 0.0 else "shot:")+style)
		# Control is applied after the damage so a root can never eat the hit's feedback,
		# and apply_root() itself refuses while the player is immune or already rooted.
		if control > 0.0: Utils.player.apply_root(control)
		preload("res://game/effects/HostileVFX.gd").emit_at(get_tree().current_scene,global_position,14,velocity.normalized(),style)
		queue_free()
		return true
	return false

## In Hell, an incoming shot that is still outside the lit radius gets its final approach
## mirrored above the fog, so "something is about to arrive" is never information the
## darkness can hide. Bounded to shots inside 1.4x the fair radius, which is the only band
## where the information changes what the player can do.
func _mirror_into_fog() -> void:
	# Every live shot used to resolve the same scene/state query independently. Fog
	# is a frame-wide rendering state, so share one snapshot per process frame while
	# preserving the exact active gate and current fair-radius value.
	_refresh_fog_cache()
	if not _fog_cache_active: return
	var player = Utils.player
	if not is_instance_valid(player): return
	if _fog_position.distance_to(player.global_position) > _fog_cache_radius*1.4: return
	if B11Probe.enabled: B11Probe.shot_fog_mirrors += 1
	preload("res://game/map/FogPierce.gd").push_line(_fog_position,_fog_tip,INK.get(style,INK.projectile),2.0,_fog_cache_active)
