extends CharacterBody2D
class_name Player
@onready var anim = $body/AnimatedSprite2D
@onready var body = $body
@onready var gun_root = $body/GunRoot
@onready var reward_root = $RewardRoot
@onready var dash_part = $body/DashParticles2D
const dash_obj = preload("res://game/hero/DashObj.tscn")
const level_up_effect = preload("res://game/hero/effect/LevelUpEffect.tscn")

var gun = null

var root_remaining = 0.0
var cc_immunity = 0.0
var root_epoch = -1
var incoming_percentage = false

func apply_root(seconds = 0.45) -> bool:
	if is_dead or LevelServer.state != "COMBAT" or root_remaining > 0 or cc_immunity > 0: return false
	root_remaining = clampf(seconds,0.4,0.5); root_epoch = LevelServer.epoch
	is_dash = false; dash_part.emitting = false
	Utils.showHitLabel("束缚",self)
	return true

func _draw():
	if root_remaining > 0:
		draw_arc(Vector2(0,4),12,0,TAU,24,Color(0.65,0.8,1),2)
		draw_line(Vector2(-9,4),Vector2(9,4),Color(0.65,0.8,1),1)

func on_percentage_hit(fraction: float, attacker = null):
	# Percentage is resolved from current maximum HP and follows defense/rewards.
	incoming_percentage = true
	onHit(PlayerData.player_hp_max*clampf(fraction,0,0.35),attacker,0.0)
	incoming_percentage = false

var SPEED = 100.0
var is_run = false
var is_dead = false #是否死亡
var is_shoot = false #是否在射击
var is_hit = false
var is_knockback = false #后坐力
var knockback_speed = 0 #后坐力速度
var is_dash = false
var look_dir = null

func _init() -> void:
	PlayerData.onHpChange.connect(self.onHpChange)
	PlayerData.onPlayerResurrect.connect(self.onPlayerResurrect)
	Utils.onGameStart.connect(self.onGameStart)

func _ready():
	set_physics_process(false)
	set_process(false)
	PlayerData.onPlayerLevelChange.connect(self.onPlayerLevelChange)
	PlayerData.playerWeaponListChange.connect(self.playerWeaponListChange)
	Utils.player = self
	#PlayerData.add_attachment(preload("res://game/attachments/UniversalExtendedMagazines.tscn").instantiate())
	#PlayerData.add_attachment(preload("res://game/attachments/ExtendedRifleMagazine.tscn").instantiate())
	#PlayerData.add_attachment(preload("res://game/attachments/QuickExpansionMagazine.tscn").instantiate())
	#PlayerData.add_attachment(preload("res://game/attachments/ShotgunShellPouch.tscn").instantiate())
	#PlayerData.add_attachment(preload("res://game/attachments/SubmachineGunMagazine.tscn").instantiate())
	#PlayerData.add_attachment(preload("res://game/attachments/MachineGunMagazine.tscn").instantiate())

func updateHero():
	SPEED = 100 * PlayerData.player_speed

func onPlayerLevelChange(level):
	if Demo.loading: return
	var ins = level_up_effect.instantiate()
	add_child(ins)

func onGameStart():
	set_physics_process(true)
	set_process(true)

func onPlayerResurrect():
	is_dead = false
	if anim:
		anim.play("idle")

func changeWeapon(weapon_id):
	var next = PlayerData.player_weapon_list.get(int(weapon_id))
	if next == null or next == gun: return
	if is_instance_valid(gun): gun.set_use(false)
	next.set_use(true)

func playerWeaponListChange():
	for weapon_id in PlayerData.player_weapon_list:
		if !gun_root.has_node(str(weapon_id)):
			var local_gun = PlayerData.player_weapon_list[weapon_id] as BaseGun
			local_gun.name = str(weapon_id)
			gun_root.add_child(local_gun)
			local_gun.setOwner(self)
			if gun == null and not Demo.loading:
				gun = local_gun
				gun.set_use(true)

func _input(event: InputEvent) -> void:
	if get_tree().paused or is_dead or not Utils.is_game_start: return
	if Input.is_action_just_pressed("dash") && !is_dash and root_remaining <= 0:
		is_dash = true
		dash_part.emitting = true
		anim.play("dash")
		await get_tree().create_timer(0.06).timeout
		is_dash = false
		dash_part.emitting = false

func _physics_process(delta):
	if root_epoch != LevelServer.epoch: root_remaining = 0.0; cc_immunity = 0.0
	cc_immunity = maxf(0,cc_immunity-delta)
	if root_remaining > 0:
		root_remaining = maxf(0,root_remaining-delta)
		if root_remaining == 0: cc_immunity = 1.2
	queue_redraw()
	if is_dead:
		return
	if Utils.freeze_frame:
		delta = 0.0
	var direction = Input.get_vector("left", "right", "up", "down")
	if is_knockback:
		if direction != Vector2.ZERO && SPEED < knockback_speed:
			velocity = (SPEED - knockback_speed) * global_position.direction_to(get_global_mouse_position())
		else:
			velocity = -knockback_speed * global_position.direction_to(get_global_mouse_position())
	else:
		velocity = direction * SPEED
	if is_dash:
		velocity = direction * 600
	if root_remaining > 0: velocity = Vector2.ZERO
	move_and_slide()
	changeAnim(direction)
	$PointLight2D2.look_at(get_global_mouse_position())
	if gun:
		gun.look_at(get_global_mouse_position())
		setGunLookat(get_global_mouse_position())

func set_knockback(knockback_speed):
	self.knockback_speed = knockback_speed
	is_knockback = true
	await get_tree().create_timer(0.05, false).timeout
	is_knockback = false
	self.knockback_speed = 0

func setGunLookat(dir):
	if dir != null:
		look_dir = gun.global_position + (dir * 1000)
		if dir.x > position.x && body.scale.x != 1:
			body.scale.x = 1
		elif dir.x < position.x && body.scale.x != -1:
			body.scale.x = -1
	else:
		look_dir = null

func changeAnim(direction):
	if is_dash:
		showDash()
		return
	if direction != Vector2.ZERO:
		is_run = true
		if (direction.x > 0 && body.scale.x != 1) || (direction.x < 0 && body.scale.x != -1):
			animPlay("run_back",-1.0,true)
		else:
			animPlay("run")
	else:
		is_run = false
		animPlay("idle")
	gunAnim()

func animPlay(anim_name,speed = 1.0,is_back = false):
	if anim.animation != anim_name:
		anim.play(anim_name,speed,is_back)

func gunAnim():
	if is_shoot:
		pass
	if is_run:
		$GPUParticles2D.emitting = true
		#gun_player.play("run")
	elif !is_run:
		#gun_player.stop()
		$GPUParticles2D.emitting = false

signal incoming_hit(raw: float, applied: float, boss: bool)

func onHit(hurt, attacker = null, minimum_pressure = 1.0):
	if is_dead or LevelServer.state != "COMBAT" or get_tree().paused: return
	if Demo.shield_hit(hurt):
		Utils.showHitLabel("护盾",self)
		return
	hurt = maxf(minimum_pressure,hurt)
	var nodes = get_tree().get_nodes_in_group("reward")
	var temp_hurt = 0
	for node in nodes:
		if node.connect_beforePlayerHit:
			var num = node.call("beforePlayerHit",hurt)
			temp_hurt += num
	for node in nodes:
		if node.has_method("incoming"): temp_hurt += node.incoming(hurt,incoming_percentage)
	hurt += temp_hurt
	hurt = maxf(0,hurt)
	var raw_pressure = hurt
	var boss_source = is_instance_valid(attacker) and attacker.get("is_boss") == true
	if is_instance_valid(attacker) and not incoming_percentage:
		hurt *= DemoConfig.BOSS_INCOMING if boss_source else DemoConfig.NORMAL_INCOMING
	incoming_hit.emit(raw_pressure,hurt,boss_source)
	PlayerData.player_hp -= hurt
	for node in nodes:
		if node.has_method("received"): node.received()
	Utils.showHitLabel(hurt,self)
	get_tree().call_group("control","hit")
	#Utils.freeze_frame = true
	Utils.freezeFrame(0.1)
	for node in nodes:
		if node.connect_afterPlayerHit:
			node.call("afterPlayerHit",hurt)

func onHpChange(hp,max_hp):
	if hp <= 0:
		Demo.stop_attacks()
		is_dead = true
		anim.play("die")

func cameraSnake(step):
	get_tree().call_group("camera","shootShake",step)

func showDash():
	var dash = dash_obj.instantiate()
	dash.texture = anim.sprite_frames.get_frame_texture(anim.animation,anim.frame)
	dash.global_position = global_position
	dash.flip_h = body.scale.x != 1
	get_tree().root.call_deferred("add_child",dash)

func addEquip(equip):
	if $EquipRoot.get_child_count() > 0:
		var child = $EquipRoot.get_child(0)
		$EquipRoot.remove_child(child)
		EquipServer.addEquipOnFloor(child,global_position)
	$EquipRoot.add_child(equip)
