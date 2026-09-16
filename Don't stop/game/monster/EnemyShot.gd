extends CharacterBody2D
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
	"laser":Color(0.45,0.95,1.0)
}
func _ready():
	if get_tree().get_nodes_in_group("enemy_projectiles").size() >= 180:
		set_physics_process(false); queue_free(); return
	add_to_group("combat_transient")
	add_to_group("enemy_projectiles")
	epoch = LevelServer.epoch
	collision_layer = 0
	collision_mask = 2147483649
	add_collision_exception_with(Utils.player)
	for actor in get_tree().get_nodes_in_group("monsters"): add_collision_exception_with(actor)
	var shape = CollisionShape2D.new()
	shape.shape = CircleShape2D.new()
	shape.shape.radius = 3
	add_child(shape)
	z_index = 5
func _draw():
	var ink = INK.get(style,INK.projectile)
	for i in range(1,trail.size()):
		draw_line(to_local(trail[i-1]),to_local(trail[i]),Color(ink.r,ink.g,ink.b,0.1+0.45*i/trail.size()),1.0+1.5*i/trail.size(),true)
	draw_circle(Vector2.ZERO,4,Color(ink.r*0.15,ink.g*0.15,ink.b*0.15))
	draw_circle(Vector2.ZERO,2.8,Color(ink.r,ink.g,ink.b))
	if control > 0.0:
		# Control attacks pulse an outer waveform ring so they never read as plain damage.
		draw_arc(Vector2.ZERO,5.5+1.5*sin(life*22.0),0,TAU,14,Color(ink.r,ink.g,ink.b,0.75),1.4,true)
		draw_arc(Vector2.ZERO,7.5,0,TAU,14,Color(0.95,0.8,1,0.45),1.0,true)
func _physics_process(delta):
	life += delta
	if life > 3.2 or epoch != LevelServer.epoch or (owner_ref and (not is_instance_valid(owner_ref.get_ref()) or owner_ref.get_ref().is_die)):
		queue_free()
		return
	trail.append(global_position)
	if trail.size()>3: trail.pop_front()
	queue_redraw()
	_mirror_into_fog()
	var previous = global_position
	if move_and_collide(velocity*delta):
		queue_free()
		return
	if Geometry2D.get_closest_point_to_segment(Utils.player.global_position,previous,global_position).distance_to(Utils.player.global_position) < 12:
		# Barrage pellets intentionally carry fractional pressure; other attacks keep
		# Hero's existing one-point minimum.
		Utils.player.onHit(damage,owner_ref.get_ref() if owner_ref else null,0.0)
		# Control is applied after the damage so a root can never eat the hit's feedback,
		# and apply_root() itself refuses while the player is immune or already rooted.
		if control > 0.0: Utils.player.apply_root(control)
		preload("res://game/effects/HostileVFX.gd").emit_at(get_tree().current_scene,global_position,14,velocity.normalized(),style)
		queue_free()

## In Hell, an incoming shot that is still outside the lit radius gets its final approach
## mirrored above the fog, so "something is about to arrive" is never information the
## darkness can hide. Bounded to shots inside 1.4x the fair radius, which is the only band
## where the information changes what the player can do.
func _mirror_into_fog() -> void:
	if not ArenaVisibility.fog_active(): return
	var player = Utils.player
	if not is_instance_valid(player): return
	if global_position.distance_to(player.global_position) > ArenaVisibility.fair_radius()*1.4: return
	preload("res://game/map/FogPierce.gd").push_line(global_position,global_position+velocity.normalized()*14.0,INK.get(style,INK.projectile),2.0)
