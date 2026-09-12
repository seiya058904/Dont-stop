extends CharacterBody2D
class_name Bullet

const bullet_shell = preload("res://game/bullets/BulletShell.tscn")

@export var bullet_impact:PackedScene
@export var bullet_smoke:PackedScene

@export var hurt = 1
@export var speed = 600
@export var knockback_speed = 50
@export var knockback_time = 0.1

@onready var light2d:PointLight2D = $PointLight2D

var player:Player
var gun:BaseGun

var timer: Timer
var queue_time = 0
var context: Dictionary = {}
var hit_ids: Array[int] = []
var has_split = false
func _ready():
	add_to_group("combat_transient")
	if get_tree().get_nodes_in_group("projectile_lights").size() < 16:
		add_to_group("projectile_lights")
	else:
		light2d.enabled = false
	set_physics_process(false)
	get_tree().create_tween().set_ease(Tween.EASE_OUT_IN).tween_property(self,"scale",Vector2(1.2,1.2),0.1).from(Vector2(0.5,1.5))
	timer = Timer.new()
	add_child(timer)
	timer.timeout.connect(self._on_timer_timeout)
	timer.start(0.05)
	z_index = 0

func setOnwer(player):
	self.player = player

func start(local:Vector2,pos:Vector2):
	global_position = local
	velocity = local.direction_to(pos)

func fire():
	queue_redraw()
	velocity = Vector2(speed * 2, 0).rotated(rotation)
	set_physics_process(true)

	if get_tree().get_nodes_in_group("shell_vfx").size() < 48:
		var ins = bullet_shell.instantiate()
		ins.add_to_group("shell_vfx")
		ins.global_position = global_position - Vector2(10,0) * velocity.normalized()
		get_tree().root.add_child(ins)
		ins.start(velocity / 2)
	if light2d.enabled: create_tween().tween_property(light2d,"energy",0.3,0.2)

func _physics_process(delta):
	#if Utils.freeze_frame:
	#	delta = 0.0
	var collisionResult = move_and_collide(velocity * delta)
	if collisionResult:
		var coller = collisionResult.get_collider()
		if coller is BaseMonster:
			if not coller.get_instance_id() in hit_ids:
				hit_ids.append(coller.get_instance_id())
				coller.hitFlash(collisionResult,self)
			if not has_split and context.get("shards",0) > 0 and context.get("depth",0) == 0:
				has_split = true
				Combat.fragments(global_position,velocity.angle(),context,coller,speed)
			if hit_ids.size() <= context.get("pierce",0):
				add_collision_exception_with(coller)
				return
			#coller.position += collisionResult.get_remainder()
			#player.cameraSnake()
		#else:
		bulletSmoke(collisionResult)
		queue_free()

func _on_timer_timeout():
	z_index = 1
	queue_time += 0.05
	if queue_time > 2*context.get("range_mul",1.0):
		queue_free()

func bulletSmoke(collisionResult):
	var ins = bullet_smoke.instantiate()
	get_parent().add_child(ins)
	ins.global_position = collisionResult.get_position()
	ins.rotation = collisionResult.get_normal().angle()

	#var imapct = bullet_impact.instantiate()
	#get_parent().add_child(imapct)
	#imapct.global_position = collisionResult.get_position()
	#imapct.rotation = collisionResult.get_normal().angle()

func _draw():
	var tier = int(context.get("tier",1))
	if tier < 2: return
	var color = Color("d9a2ff") if tier == 5 else Color("83cddd")
	color.a = 0.55
	draw_line(Vector2(-4-tier*2,0),Vector2.ZERO,color,1.0+tier*0.15)
