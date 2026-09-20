extends CharacterBody2D
class_name BaseMonster

@export var is_boss = false
@export var SPEED = 50.0
@export var hurt = 1
@export var HP = 5
@export var knockback_def = 5 #击退抵抗
var path_refresh = 0.0
var cached_step = Vector2.ZERO
var training = false
var flash_time = 0.0
var label_time = 0.0
var critical_total = 0.0
var last_context: Dictionary = {}
var movement_delta: float
var burns: Dictionary = {}
var slow_time = 0.0
var slow_amount = 0.0
var slows: Dictionary = {}
func apply_slow(source: String, amount: float, seconds: float):
	slows[source] = {"amount":amount,"seconds":seconds}
	refresh_slow()
func refresh_slow():
	slow_amount = 0.0; slow_time = 0.0
	for status in slows.values():
		slow_amount += status.amount
		slow_time = maxf(slow_time,status.seconds)
	slow_amount = minf(0.4,slow_amount)*(0.25 if is_boss else 1.0)
var is_elite = false
## Hell Mode's damage axis. Declared on the shared base so EVERY actor has it, including
## E01, which keeps the plain Monster2 script and would otherwise reject the assignment.
## Contact damage uses DemoConfig.CONTACT_DAMAGE_WEIGHT of it; telegraphed attacks use it
## in full.
var damage_scale = 1.0
var variant_damage = 1.0
var displayed_flash = -1.0

func apply_burn(source: String, amount: float, seconds: float, context: Dictionary):
	var saved = context.duplicate(true)
	saved.damage = amount
	saved.depth = 1
	saved.native_attack = false
	saved.crit = 0.0
	saved.erase("burn")
	var old = burns.get(source,{"tick":0.25})
	burns[source] = {"remaining":seconds,"tick":old.tick,"context":saved}

var audio_hit: AudioStreamPlayer2D
@onready var sprite_body = get_node("body")
@onready var anim :AnimatedSprite2D = get_node("body/AnimatedSprite2D")

var target_player:Player = Utils.player
var state_array = []
var hit = false
var is_die = false
var is_flip
var is_atk = false

var death_callback :Callable

func _ready():
	add_to_group("monsters")
	var flash = ShaderMaterial.new()
	flash.shader = load("res://shader/HitFlash.gdshader")
	anim.material = flash
	audio_hit = AudioStreamPlayer2D.new()
	audio_hit.bus = "SFX"
	var node = Node2D.new()
	node.name = "EffectRoot"
	add_child(node)
	name = str(Time.get_ticks_usec())
	audio_hit.stream = load("res://audio/body_hit_finisher_52.wav")
	add_child(audio_hit)

func setData(data):
	SPEED = data['speed']
	hurt = data['hurt']
	HP = data['hp']
	knockback_def = 5

func _process(delta):
	# B11.2 test-only counters (game/diag/B11Probe.gd): how often the status walks ran, and how
	# often they ran over an EMPTY status set. The second number is the whole question - an actor
	# carrying no status at all should not be paying for a walk.
	if B11Probe.enabled:
		B11Probe.status_walks += 1
		if slows.is_empty() and burns.is_empty(): B11Probe.status_walks_empty += 1
	# B11.2. `Dictionary.keys()` builds a fresh Array on every call, and this ran for EVERY actor on
	# EVERY frame whether or not it carried a single status. Measured on the worst-load profile: all
	# 221,172 walks in a 45 s run were over an empty pair of dictionaries, i.e. ~9,800 array
	# constructions per second for nothing. The guard is the same predicate the loops would have
	# evaluated on their first iteration, so which statuses tick, in what order, and for how long is
	# unchanged - including the re-check below, which is why it is still written as a second
	# `is_empty()`: a loop that erased its last entry must still fall through to the decay branch.
	if not slows.is_empty():
		for source in slows.keys():
			slows[source].seconds -= delta
			if slows[source].seconds <= 0: slows.erase(source)
	if not slows.is_empty(): refresh_slow()
	else: slow_time = maxf(0,slow_time-delta)
	if not is_die and not burns.is_empty():
		for source in burns.keys():
			var burn = burns[source]
			var elapsed = minf(delta,burn.remaining)
			burn.remaining -= elapsed
			burn.tick -= elapsed
			while burn.tick <= 0 and not is_die:
				burn.tick += 0.25
				Combat.hit(self,burn.context)
			if burn.remaining <= 0: burns.erase(source)
	flash_time = maxf(0,flash_time-delta)
	# Physics-driven enemy drawings still refresh in their subclasses. Rebuild
	# the contact bracket and shader state only when the visible flash changes.
	var visible_flash = (0.7 if not Combat.reduced_flash else 0.01) if flash_time > 0 else 0.0
	if displayed_flash != visible_flash:
		displayed_flash = visible_flash
		queue_redraw()
		anim.material.set_shader_parameter("flash",0.7 if visible_flash == 0.7 else 0.0)
		anim.scale = Vector2(1.08,0.92) if flash_time > 0 else Vector2.ONE
	label_time -= delta
	if label_time <= 0:
		if idle_frame_num > 0: Utils.showHitLabel(idle_frame_num,self)
		if critical_total > 0: Utils.showHitLabelMore("暴击 " + str(critical_total),self,Vector2(0,-12),Color(1,0.8,0.3))
		idle_frame_num = 0
		critical_total = 0
		label_time = 0.2

func _physics_process(delta):
	if training: return
	#if Engine.get_physics_frames() % 60 :
	if is_atk || is_die:
		return
	if hit:
		move_and_slide()
	elif target_player != null:
		var next_path_position = target_player.global_position
		path_refresh -= delta
		if is_instance_valid(LevelServer.town):
			if path_refresh <= 0 or global_position.distance_to(cached_step) < 5:
				cached_step = LevelServer.town.path_step(global_position,target_player.global_position)
				path_refresh = 0.2
			next_path_position = cached_step
		#var next_path_position = navigationAgent2D.get_next_path_position()
		var current_agent_position: Vector2 = global_position
		var new_velocity: Vector2 = current_agent_position.direction_to(next_path_position) * SPEED * (1.0-slow_amount if slow_time > 0 else 1.0)
		_on_velocity_computed(new_velocity)

	if velocity != Vector2.ZERO:
		anim.play("run")
		if velocity.x > 0:
			flip_h(false)
		elif velocity.x < 0 && scale.x == 1:
			flip_h(true)
	else:
		anim.play("idle")

func _on_velocity_computed(safe_velocity: Vector2) -> void:
	if state_array.has(Utils.STATE_TYPE.STUN):
		anim.play("idle")
		return
	velocity = safe_velocity
	move_and_slide()

func flip_h(flip:bool):
	if is_flip == flip:
		return
	is_flip = flip
	var x_axis = sprite_body.global_transform.x
	sprite_body.global_transform.x.x = (-1 if flip else 1) * abs(x_axis.x)

func hitFlash(_collision, bullet:Bullet):
	var context = bullet.context.duplicate()
	context.damage = bullet.hurt
	context.impact_origin = bullet.global_position-bullet.velocity.normalized()*10
	Combat.hit(self,context)

var idle_frame_num = 0.0
func onHit(hit_num, _is_show_label = true, _is_death_effect = true):
	Combat.hit(self,{"damage":hit_num,"depth":Combat.dispatch_depth,"epoch":LevelServer.epoch})

func receive_damage(amount: float, critical: bool, context: Dictionary):
	if is_die: return
	last_context = context
	if critical: critical_total += amount
	else: idle_frame_num += amount
	flash_time = 0.08
	Combat.sound(audio_hit.stream,global_position)
	var impulse = context.get("impulse",0.0)-knockback_def
	if impulse > 0 and not training and not is_boss:
		velocity = Utils.player.global_position.direction_to(global_position)*impulse
		hit = true
		get_tree().create_timer(context.get("impulse_time",0.1), false).timeout.connect(func(): hit = false)
	if training:
		HP = 1000
		return
	HP -= amount
	if HP <= 0: onDie()

func onDie(is_death_effect = true):
	if is_die or training: return
	is_die = true
	get_tree().call_group("reward","target_removed",self)
	Combat.kill_events += 1
	Demo.on_kill(self,last_context)
	PlayerData.player_exp += 1
	if death_callback:
		death_callback.call(self)
	var nodes = get_tree().get_nodes_in_group("reward")
	var temp_hurt = 0
	if is_death_effect and last_context.get("depth",0) == 0:
		for node in nodes:
			if node.connect_kill:
				node.call("onKill",self)
	set_physics_process(false)
	for item in get_node("EffectRoot").get_children():
		item.queue_free()
	get_node("CollisionShape2D").call_deferred("set_disabled",true)
	anim.play("die")
	get_tree().create_tween().tween_property(get_node("UndeadShadow"),"scale",Vector2.ZERO,0.3)
	await get_tree().create_timer(0.5, false).timeout
	queue_free()

func setDeathCallBack(death_callback:Callable):
	self.death_callback = death_callback

func addEffect(node):
	get_node("EffectRoot").add_child(node)

func _draw():
	if not is_die and get_meta("variant_applied",false):
		var giant = get_meta("giant",false)
		var tier = int(get_meta("enchantment",0))
		var color = Color("eeb65d") if giant else (Color("8fed74") if tier == 1 else Color("ed77c9"))
		var center = Vector2(0,-18 if giant else -9)
		var radius = 23.0 if giant else 13.0
		draw_arc(center,radius,0,TAU,12,color,1.0)
		for rune in (2 if tier == 2 else 1):
			draw_line(center+Vector2(-3+rune*6,-radius-4),center+Vector2(-3+rune*6,-radius),color,2)
		var fraction = clampf(HP/maxf(1.0,float(get_meta("initialized_hp",HP))),0,1)
		draw_line(center+Vector2(-radius,-radius-7),center+Vector2(-radius+radius*2*fraction,-radius-7),color,2)
	# Compact contact bracket remains visible with flash and shake disabled.
	if flash_time > 0 and not is_die:
		var tier = int(last_context.get("tier",1))
		if tier >= 3:
			var color = Color(0.8,0.55,1,0.5) if tier == 5 else Color(0.4,0.8,1,0.45)
			draw_arc(Vector2(0,-8),9+tier,-1.3,1.3,8,color,1.3)
		draw_arc(Vector2(0,-8),10,-0.6,0.6,5,Color(1,0.85,0.5),1)
		draw_arc(Vector2(0,-8),10,PI-0.6,PI+0.6,5,Color(1,0.85,0.5),1)
