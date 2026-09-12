extends Node2D
class_name BaseGun


const particles_pre = preload("res://game/hero/gpu_particles_2d.tscn")

## 武器ID
@export var weapon_id = 0 #枪械ID
@export var image:Texture #枪械图片
@export var weapon_name:String = "Gun" #枪械名称
@export_enum("ASSAULT_RIFLES","SUBMACHINE_GUNSRELOAD","MACHINE_GUNS","SNIPER_RIFLES","SHOTGUNS","LASER_WEAPONS") var weapon_type = "ASSAULT_RIFLES"
@export var bullet_scene : PackedScene #子弹模板
@export var damage = 0.0 #子弹伤害
@export var bullet_speed = 200 #子弹速度
@export var fire_rate = 5.0 #开火速率
@export var bullets_max_count = 10 #子弹数量
@export var change_speed = 1.0 #换弹时间
@export var recoil_duration = 0.2
@export var knockback_speed = 50 #击退速度
@export var knockback_time = 0.1 #击退持续时间
@export var time_scale = 0.1 #帧冻结时间倍数
@export var freeze_frame = 3 #帧冻结帧数
@export var recoil = 0 #后坐力大小
@export var shake_vector = Vector2.ZERO #屏幕晃动大小
@export var reload_stream :AudioStream = load("res://audio/bullet/GUNMech_Insert Clip_01.wav")

var attachments = {
	"Optics" = null,
	"Muzzle" = null,
	"Barrel" = null,
	"Underbarrel" = null,
	"Ammunition" = null,
	"Stock" = null,
	"Tactical" = null,
	"Perks" = null
}

@onready var anim_player:AnimationPlayer = $AnimationPlayer
@onready var gun_tip = $GunTip
@onready var audio = $AudioStreamPlayer2D
@onready var timer = $shoot_timer
@onready var gun_image = $Sprite2D

var base_stats: Dictionary = {}
var effective: Dictionary = {}
var action_generation = 0
var tags: Array = ["projectile"]
var attachments_node = Node.new()
var attachments_dict = {}
var tween:Tween
var direction:Vector2 #朝向
var player:Player #使用玩家
var is_use = false #是否正在使用
var can_shoot = true #是否可以射击
var bullets_count = 0: #剩余子弹
	set(value):
		bullets_count = value
		if is_use:
			PlayerData.emit_signal("onWeaponBulletsChange",bullets_count,bullets_max_count)
var is_reloading = false #是否正在换子弹
var change_timer = Timer.new()
var audio_reload_ammo = AudioStreamPlayer.new()

func _init():
	add_child(attachments_node)
	add_child(change_timer)
	add_child(audio_reload_ammo)
	change_timer.one_shot = true
	change_timer.timeout.connect(self.reload_over)

func _ready() -> void:
	add_to_group("guns")
	base_stats = {"damage":damage,"magazine":bullets_max_count,"reload":change_speed,"rate":fire_rate,"impulse":knockback_speed}
	tags = DemoConfig.weapon_tags(weapon_id)
	audio.bus = "SFX"
	audio.max_polyphony = 4
	audio_reload_ammo.bus = "SFX"
	PlayerData.onPlayerFireRateChange.connect(self.onPlayerFireRateChange)
	bullets_count = bullets_max_count
	audio_reload_ammo.stream = reload_stream
	gun_image.texture = image
	set_use(false)
	updateGun()

func onPlayerFireRateChange(_rate):
	updateGun()

func updateGun():
	if base_stats.is_empty() or Demo.loading: return
	effective = EffectiveStats.calculate(self, attachments_dict.values())
	bullets_max_count = effective.magazine
	if bullets_count > bullets_max_count:
		PlayerData.player_ammo += bullets_count - bullets_max_count
		bullets_count = bullets_max_count
	timer.wait_time = 1.0 / effective.rate
	if is_use: PlayerData.onWeaponBulletsChange.emit(bullets_count,bullets_max_count)

func addAttachMent(am:BaseAttachment) -> bool:
	if not am.can_equip(self): return false
	if am.gun == self: return true
	cancel_actions()
	if is_instance_valid(am.gun): am.gun.removeAttachMent(am)
	if attachments_dict.has(am.am_type): removeAttachMent(attachments_dict[am.am_type])
	attachments_dict[am.am_type] = am
	am.reparent(attachments_node)
	am.gun = self
	updateGun()
	Demo.changed.emit()
	Demo.save_camp()
	return true

func removeAttachMent(am:BaseAttachment):
	if am.gun != self: return
	cancel_actions()
	attachments_dict.erase(am.am_type)
	am.reparent(PlayerData)
	am.gun = null
	updateGun()
	Demo.changed.emit()
	Demo.save_camp()

func cancel_actions():
	action_generation += 1
	change_timer.stop()
	is_reloading = false
	can_shoot = true
	if is_instance_valid(timer): timer.stop()
	if is_instance_valid(audio): audio.stop()
	audio_reload_ammo.stop()
	for effect in find_children("*","GPUParticles2D",true,false): effect.emitting = false
	if is_instance_valid(anim_player): anim_player.stop()

func damage_context(depth = 0) -> Dictionary:
	return {"gun":self,"damage":effective.damage,"crit":effective.crit,"impulse":effective.impulse,"impulse_time":knockback_time,"depth":depth,"epoch":LevelServer.epoch}

#子弹装填完毕
func reload_over():
	if not is_reloading or not is_use: return
	var ammo = bullets_max_count - bullets_count
	if PlayerData.player_ammo < ammo:
		ammo = PlayerData.player_ammo
		PlayerData.player_ammo = 0
	else:
		PlayerData.player_ammo -= ammo
	bullets_count += ammo
	PlayerData.emit_signal("onWeaponChangeAnim",weapon_id,Utils.GUN_CHANGE_TYPE.RELOAD)
	is_reloading = false

#设置枪械所属
func setOwner(player):
	self.player = player

func _process(delta):
	if Utils.freeze_frame:
		delta = 0.0
	var mouse_pos = get_global_mouse_position()
	direction = (mouse_pos - gun_tip.global_position).normalized()

	if is_use and not player.is_dead and Demo.fire_released and Input.mouse_mode == Input.MOUSE_MODE_CONFINED_HIDDEN && Input.is_action_pressed("shoot") and can_shoot and !is_reloading:
		can_shoot = false
		timer.start()
		if bullets_count > 0:
			_shoot()
		else:
			reload_ammo()

	if is_use && Input.is_action_pressed("reload"):
		reload_ammo()

#设置是否正在使用
func set_use(use:bool):
	cancel_actions()
	change_timer.stop()
	is_reloading = false
	is_use = use
	set_physics_process(is_use)
	set_process(is_use)
	visible = is_use
	if player && is_use:
		player.gun = self
		PlayerData.emit_signal("onWeaponChangeAnim",weapon_id,Utils.GUN_CHANGE_TYPE.CHANGE)
		if bullets_count == 0 and not Demo.loading:
			reload_ammo()
	PlayerData.emit_signal("onWeaponChanged")

#开火
func fire(bullet:Bullet,is_bullet = true,is_play = true):
	if not is_use or player.is_dead or get_tree().paused or bullets_count <= 0:
		bullet.queue_free()
		return
	if is_bullet:
		bullets_count -= 1
		if bullets_count < 0:
			can_shoot = false
			bullet.queue_free()
			return

	bullet.speed = bullet_speed
	bullet.hurt = effective.damage
	bullet.context = damage_context()
	bullet.knockback_speed = effective.impulse
	bullet.knockback_time = knockback_time
	bullet.gun = self
	if is_bullet:
		bullet.fire()
	if recoil > 0 && is_bullet:
		player.set_knockback(recoil)
	if is_play:
		audio.play()

#切换子弹
func reload_ammo():
	if PlayerData.player_ammo == 0:
		Utils.showToast("AMMO_OUT")
		return
	if !is_reloading && change_timer.is_stopped() && bullets_count < bullets_max_count:
		is_reloading = true
		var local_speed = effective.reload
		anim_player.speed_scale = 1 / local_speed
		change_timer.start(local_speed)
		audio_reload_ammo.play()
		playReload()

#播放切换动画
func playReload():
	anim_player.play("reload")

func _physics_process(delta):
	if Utils.freeze_frame:
		delta = 0.0
	#if Utils.freeze_frame:
		#if Engine.get_physics_frames() % freeze_frame == 0:
			# 暂停一帧
		#	Utils.freeze_frame = false
			# 将时间比例设置为1
		#	Engine.time_scale = 1
		#	return

func _shoot() -> void:
	call_deferred("_shootAnim")

func _shootAnim():
	if not is_use or player.is_dead or get_tree().paused: return
	player.cameraSnake(shake_vector * direction)
	var ins = particles_pre.instantiate()
	ins.position = gun_tip.position
	add_child(ins)
