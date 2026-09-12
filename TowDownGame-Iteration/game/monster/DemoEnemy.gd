extends "res://game/monster/Monster 2/Monster2.gd"

var role = "E02"
var phase = "spawn"
var phase_time = 0.6
var locked_direction = Vector2.ZERO
var contact_cooldown = 0.0

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

func _physics_process(delta):
	if is_die: return
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
		if distance < 17 and contact_cooldown <= 0:
			Utils.player.onHit(1,self)
			contact_cooldown = 0.8
		return
	if phase == "warn":
		if phase_time <= 0:
			if role == "E04":
				phase = "dash"
				phase_time = 0.45
			else:
				var projectile = CharacterBody2D.new()
				projectile.set_script(load("res://game/monster/EnemyShot.gd"))
				projectile.owner_ref = weakref(self)
				projectile.global_position = global_position
				projectile.velocity = locked_direction*85
				get_tree().current_scene.add_child(projectile)
				phase = "recover"
				phase_time = 1.1
		return
	if phase == "dash":
		velocity = locked_direction*240
		move_and_slide()
		if distance < 19 and contact_cooldown <= 0:
			Utils.player.onHit(1,self)
			contact_cooldown = 0.8
		if phase_time <= 0 or get_slide_collision_count() > 0:
			phase = "recover"
			phase_time = 0.8
		return
	if phase == "recover":
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
			draw_line(Vector2.ZERO,locked_direction*100,Color(0.1,0.05,0.02),4)
			draw_line(Vector2.ZERO,locked_direction*100,Color(1,0.5,0.15,0.85),2)
	if role == "E05":
		draw_arc(Vector2(0,-12),10,PI,TAU,12,Color(0.7,1,0.4),2)
		if phase == "warn": draw_circle(Vector2(0,-20),3+sin(phase_time*18),Color(1,0.6,0.3))
