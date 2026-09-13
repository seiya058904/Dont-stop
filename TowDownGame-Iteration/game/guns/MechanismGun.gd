extends "res://game/guns/AlienRifle.gd"

var charging = false
var charge_time = 0.0
var sustained = false
var spin = 0.0
var thermal_clock = 0.0
var resting_position = Vector2.ZERO

func projectile_count() -> int:
	var spec=WeaponCatalog.definition(weapon_id)
	return 3 if spec.mode=="prism" else int(spec.get("count",1))

func _ready():
	resting_position = position
	var spec = WeaponCatalog.definition(weapon_id)
	damage = spec.damage
	fire_rate = spec.rate
	bullets_max_count = spec.magazine
	change_speed = spec.reload
	bullet_speed = spec.speed
	super._ready()

func _shootAnim():
	if not is_use or player.is_dead or get_tree().paused: return
	# Recoil always returns to the scene anchor, not an intermediate tween position.
	position = resting_position
	super._shootAnim()

func drive_spin(pressed: bool, delta: float):
	var spec = WeaponCatalog.definition(weapon_id)
	spin = clampf(spin+delta/maxf(0.1,effective.warmup)*(1.0 if pressed else -1.5),0,1)
	timer.wait_time = 1.0/minf(spec.max_rate,effective.rate*lerpf(0.25,1.0,spin))

func _process(delta):
	var spec = WeaponCatalog.definition(weapon_id)
	if spec.mode == "thermal":
		direction = (get_global_mouse_position()-gun_tip.global_position).normalized()
		if is_use and Input.is_action_pressed("reload"): reload_ammo()
	elif spec.mode == "rail":
		direction = (get_global_mouse_position()-gun_tip.global_position).normalized()
		var allowed = is_use and not player.is_dead and Demo.fire_released and Utils.is_gameplay_mouse_mode() and not get_tree().paused
		handle_charge(allowed and Input.is_action_pressed("shoot"),delta)
		if Input.is_action_pressed("reload"): reload_ammo()
	else:
		if spec.mode == "rotary": drive_spin(Input.is_action_pressed("shoot") and Demo.fire_released and not is_reloading,delta)
		super._process(delta)
		if not Input.is_action_pressed("shoot"): sustained = false
	queue_redraw()

func _physics_process(delta):
	if WeaponCatalog.definition(weapon_id).mode != "thermal": return
	var allowed = is_use and not player.is_dead and Demo.fire_released and Utils.is_gameplay_mouse_mode() and not get_tree().paused
	handle_thermal(allowed and Input.is_action_pressed("shoot"),delta)

func handle_thermal(pressed: bool, delta: float):
	if not pressed or not is_use or player.is_dead or get_tree().paused or is_reloading:
		thermal_clock = 0.0
		sustained = false
		return
	thermal_clock += delta
	while thermal_clock+0.000001 >= 0.1:
		thermal_clock -= 0.1
		if bullets_count <= 0:
			reload_ammo()
			return
		_shoot()

func handle_charge(pressed: bool, delta: float):
	if pressed and bullets_count <= 0 and not is_reloading:
		reload_ammo()
		return
	if pressed and can_shoot and not is_reloading and bullets_count > 0:
		charging = true
		charge_time = minf(effective.warmup,charge_time+delta)
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
	spin = 0.0
	thermal_clock = 0.0
	queue_redraw()

func reload_ammo():
	thermal_clock = 0.0
	charging = false
	charge_time = 0.0
	sustained = false
	super.reload_ammo()

func _draw():
	if charging:
		draw_arc(gun_tip.position,5+charge_time*5,0,TAU,18,Color(0.7,0.9,1),1)
	if spin > 0:
		draw_arc(gun_tip.position,4,spin*TAU,spin*TAU+PI,8,Color(1,0.8,0.4),1)

func _shoot():
	if not is_use or player.is_dead or get_tree().paused or bullets_count <= 0 or is_reloading: return
	var spec = WeaponCatalog.definition(weapon_id)
	var context = shot_context()
	context.radius = effective.radius
	bullets_count -= 1
	Combat.attacks += 1
	if spec.mode in ["prism","rail","cone","thermal"]:
		if spec.mode == "prism":
			for i in projectile_count(): Combat.beam(self,gun_tip.global_position,direction.rotated((i-(projectile_count()-1)*0.5)*0.1),context,1)
		elif spec.mode == "rail":
			context.damage *= 1.0+1.5*minf(1.0,charge_time/effective.warmup)
			Combat.beam(self,gun_tip.global_position,direction,context,mini(8,effective.pierce+1))
		else:
			if spec.mode == "thermal":
				sustained = true
				context.burn = spec.burn
			Combat.cone(self,gun_tip.global_position,direction,context)
		audio.play()
		_shootAnim()
		return
	var count = projectile_count()
	for i in count:
		var angle = (i-(count-1)*0.5)*spec.get("fan",0.0)*effective.spread
		var shot_direction = direction.rotated(angle)
		var bullet = bullet_scene.instantiate()
		bullet.set_script(load("res://game/bullets/MechanismProjectile.gd"))
		bullet.spec = spec.duplicate(true)
		for key in ["bounces","pierce","shards","shard_ratio","bounce_retention","turn","lock_angle"]: bullet.spec[key] = effective[key]
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
