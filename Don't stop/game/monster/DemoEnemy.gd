extends "res://game/monster/Monster 2/Monster2.gd"

var role = "E02"
var phase = "spawn"
var phase_time = 0.6
var locked_direction = Vector2.ZERO
var contact_cooldown = 0.0
## Set by M5Content.spawn() from HellMode. Telegraphed attacks use the full axis; raw body
## contact uses DemoConfig.CONTACT_DAMAGE_WEIGHT of it, because contact is the one source
## the player cannot dodge and scaling it fully turns a fogged Hell wave into chip damage.
var damage_scale := 1.0

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
			Utils.player.onHit(contact_damage(),self)
			contact_cooldown = 0.8
		return
	if phase == "warn":
		if phase_time <= 0:
			if role == "E04":
				phase = "dash"
				phase_time = 0.45
			else:
				var count = 5 if LevelServer.level>=6 else 1
				if is_elite: count += 3
				for i in count:
					var spread = 0.2
					shot(locked_direction.rotated((i-(count-1)*0.5)*spread),95 if count>1 else 85,1.0,true,"projectile")
				phase = "recover"
				phase_time = 1.1
		return
	if phase == "dash":
		velocity = locked_direction*240
		move_and_slide()
		if distance < 19 and contact_cooldown <= 0:
			Utils.player.onHit(contact_damage(),self)
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
		locked_direction = global_position.direction_to(Utils.player.global_position)
		phase = "warn"
		phase_time = 0.6 if role == "E04" else 0.75

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
