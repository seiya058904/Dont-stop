extends "res://game/guns/AlienRifle.gd"

var charging = false
var charge_time = 0.0
var sustained = false

func _process(delta):
	var spec = WeaponCatalog.definition(weapon_id)
	if spec.mode == "rail":
		direction = (get_global_mouse_position()-gun_tip.global_position).normalized()
		var allowed = is_use and not player.is_dead and Demo.fire_released and Input.mouse_mode == Input.MOUSE_MODE_CONFINED_HIDDEN and not get_tree().paused
		handle_charge(allowed and Input.is_action_pressed("shoot"),delta)
		if Input.is_action_pressed("reload"): reload_ammo()
	else:
		super._process(delta)
		if not Input.is_action_pressed("shoot"): sustained = false
	queue_redraw()

func handle_charge(pressed: bool, delta: float):
	if pressed and can_shoot and not is_reloading and bullets_count > 0:
		charging = true
		charge_time = minf(WeaponCatalog.definition(weapon_id).charge,charge_time+delta)
	elif charging:
		charging = false
		if not get_tree().paused and is_use and not player.is_dead:
			_shoot()
			can_shoot = false
			timer.start()
		charge_time = 0.0

func cancel_actions():
	super.cancel_actions()
	charging = false
	charge_time = 0.0
	sustained = false
	queue_redraw()

func reload_ammo():
	charging = false
	charge_time = 0.0
	sustained = false
	super.reload_ammo()

func _draw():
	if charging:
		draw_arc(gun_tip.position,5+charge_time*5,0,TAU,18,Color(0.7,0.9,1),1)

func _shoot():
	if not is_use or player.is_dead or get_tree().paused or bullets_count <= 0 or is_reloading: return
	var spec = WeaponCatalog.definition(weapon_id)
	var context = damage_context()
	context.radius = effective.radius
	bullets_count -= 1
	Combat.attacks += 1
	if spec.mode in ["prism","rail","cone","thermal"]:
		if spec.mode == "prism":
			for angle in [-0.10,0.0,0.10]: Combat.beam(self,gun_tip.global_position,direction.rotated(angle),context,1)
		elif spec.mode == "rail":
			context.damage *= 1.0+1.5*minf(1.0,charge_time/spec.charge)
			Combat.beam(self,gun_tip.global_position,direction,context,6)
		else:
			if spec.mode == "thermal":
				sustained = true
				context.burn = spec.burn
			Combat.cone(self,gun_tip.global_position,direction,context)
		audio.play()
		_shootAnim()
		return
	var count = int(spec.get("count",1))
	for i in count:
		var angle = (i-(count-1)*0.5)*spec.get("fan",0.0)*effective.spread
		var shot_direction = direction.rotated(angle)
		var bullet = bullet_scene.instantiate()
		bullet.set_script(load("res://game/bullets/MechanismProjectile.gd"))
		bullet.spec = spec.duplicate(true)
		bullet.context = context.duplicate(true)
		bullet.hurt = context.damage
		bullet.speed = bullet_speed
		bullet.player = player
		bullet.gun = self
		get_tree().current_scene.add_child(bullet)
		bullet.global_position = gun_tip.global_position
		bullet.rotation = shot_direction.angle()
		bullet.fire()
		bullet.lock_target()
	audio.play()
	_shootAnim()
