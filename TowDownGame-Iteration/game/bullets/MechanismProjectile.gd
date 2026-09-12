extends Bullet

var spec: Dictionary = {}
var age = 0.0
var remaining_bounces = 0
var visited: Array[int] = []
var target_ref: WeakRef
var finished = false
var last_wall_age = -1.0

func _ready():
	super._ready()
	timer.stop()
	remaining_bounces = mini(4,int(spec.get("bounces",0)))

func lock_target():
	if spec.get("mode","") != "missile": return
	var nearest = 260.0
	for target in get_tree().get_nodes_in_group("monsters"):
		var offset = target.global_position-global_position
		if target.is_die or absf(velocity.angle_to(offset)) > spec.get("lock_angle",0.65): continue
		if offset.length() < nearest and Combat.clear_line(global_position,target.global_position):
			nearest = offset.length()
			target_ref = weakref(target)
	if target_ref:
		Combat.trace([global_position,target_ref.get_ref().global_position],Color(1,0.7,0.25),1.0)

func _physics_process(delta):
	if finished: return
	age += delta
	if age >= 2.0 or context.get("epoch",-1) != LevelServer.epoch:
		finished = true
		queue_free()
		return
	if target_ref:
		var target = target_ref.get_ref()
		if is_instance_valid(target) and not target.is_die:
			var turn = clampf(velocity.angle_to(target.global_position-global_position),-spec.get("turn",2.2)*delta,spec.get("turn",2.2)*delta)
			velocity = velocity.rotated(turn)
			rotation = velocity.angle()
		else: target_ref = null
	var collision = move_and_collide(velocity*delta)
	if not collision: return
	var target = collision.get_collider()
	if spec.get("mode","") in ["rocket","missile"]:
		finished = true
		Combat.explosion_context(global_position,context.get("radius",24.0),context)
		queue_free()
		return
	if target is BaseMonster:
		if not target.get_instance_id() in visited:
			visited.append(target.get_instance_id())
			Combat.hit(target,context)
		if spec.get("shards",0) > 0 and context.get("depth",0) == 0: split()
		finished = true
		queue_free()
	elif remaining_bounces > 0 and age-last_wall_age > 0.02:
		remaining_bounces -= 1
		last_wall_age = age
		velocity = velocity.bounce(collision.get_normal())
		rotation = velocity.angle()
		global_position += collision.get_normal()*0.8
		Combat.trace([collision.get_position(),global_position+velocity.normalized()*12],Color(1,0.7,0.3),2.0)
	else:
		finished = true
		queue_free()

func split():
	var count = mini(3,int(spec.get("shards",0)))
	for i in count:
		var shard = load("res://game/bullets/SmpBullet.tscn").instantiate()
		shard.set_script(load("res://game/bullets/MechanismProjectile.gd"))
		shard.spec = {"mode":"fragment"}
		shard.context = context.duplicate(true)
		shard.context.depth = 1
		shard.context.damage *= 0.35
		shard.context.crit = 0.0
		shard.hurt = shard.context.damage
		shard.speed = speed
		shard.player = player
		get_tree().current_scene.add_child(shard)
		shard.global_position = global_position
		shard.rotation = velocity.angle()+(i-(count-1)*0.5)*0.28
		for id in visited:
			var victim = instance_from_id(id)
			if is_instance_valid(victim): shard.add_collision_exception_with(victim)
		shard.fire()

func _draw():
	var mode = spec.get("mode","")
	var color = Color(1,0.65,0.2) if mode in ["rocket","missile"] else Color(0.4,0.9,1)
	draw_line(Vector2(-9,0),Vector2.ZERO,color,2 if mode != "fragment" else 1)
	if mode == "ricochet": draw_arc(Vector2.ZERO,4,0,TAU,8,color,1)
