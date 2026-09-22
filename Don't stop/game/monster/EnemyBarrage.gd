extends Node

var owner_ref: WeakRef
var heading = Vector2.RIGHT
var kind = "fan"
var count = 9
var waves = 2
var interval = 0.22
var speed = 135.0
var spread = 0.8
var shift = 0.08
var elapsed = 0.0
var next_wave = 0
var next_due = 0.0
var epoch = 0
var style = "projectile"
var deferred_seconds = 0.0
var damage := 0.18
var bounces := 0
var planned := 0

func angles() -> Array:
	var result = []
	for i in count:
		var angle = lerpf(-spread,spread,float(i)/maxi(1,count-1))
		if kind == "ring":
			angle = TAU*i/count
			# A 64px chord at R=80 leaves 40px beyond the combined hit threshold.
			# Gap width is angular, so denser rings never shrink it to three slots.
			if absf(wrapf(angle,-PI,PI)) < 0.42: continue
		result.append(angle+shift*next_wave)
	return result

func _ready():
	add_to_group("combat_transient")
	epoch = LevelServer.epoch
	var actor = owner_ref.get_ref() if owner_ref else null
	planned = angles().size()*waves
	if is_instance_valid(actor): actor.actions["barrage_planned"] = actor.actions.get("barrage_planned",0)+planned

func _physics_process(delta):
	var actor = owner_ref.get_ref() if owner_ref else null
	if not is_instance_valid(actor) or actor.is_die or epoch != LevelServer.epoch or LevelServer.state != "COMBAT":
		if is_instance_valid(actor): actor.actions["barrage_cancelled_owner"] = actor.actions.get("barrage_cancelled_owner",0)+planned
		planned = 0
		queue_free(); return
	elapsed += delta
	if elapsed < next_due: return
	var directions = angles()
	var live = preload("res://game/monster/EnemyShot.gd").live_count
	# One synchronous wave is atomic: no await or competing spawn in this loop.
	# Keep the measured 180 ceiling until higher capacity has been demonstrated.
	if live+directions.size() > preload("res://game/monster/EnemyShot.gd").capacity_limit:
		deferred_seconds += delta
		actor.remember("barrage_deferred")
		if deferred_seconds > 4.0:
			actor.actions["barrage_cancelled_pellets"] = actor.actions.get("barrage_cancelled_pellets",0)+planned
			planned = 0
			actor.remember("barrage_cancelled_capacity"); queue_free()
		return
	deferred_seconds = 0.0
	actor.actions["barrage_requested"] = actor.actions.get("barrage_requested",0)+directions.size()
	actor.actions["barrage_admitted"] = actor.actions.get("barrage_admitted",0)+directions.size()
	var emitted = 0
	for angle in directions:
		# Only alternating waves reflect; ordinary waves retain wall expiry.
		var reflections = bounces if next_wave%2 == 0 else 0
		var ink = style if reflections > 0 or style != "ricochet" else "laser"
		if actor.shot(heading.rotated(angle),speed,damage,false,ink,reflections): emitted += 1
	actor.remember("barrage_wave")
	actor.actions["barrage_projectiles"] = actor.actions.get("barrage_projectiles",0)+emitted
	planned -= directions.size()
	next_wave += 1
	next_due = elapsed+interval
	if next_wave >= waves: queue_free()

func _exit_tree():
	var actor = owner_ref.get_ref() if owner_ref else null
	if planned > 0 and is_instance_valid(actor):
		actor.actions["barrage_cancelled_owner"] = actor.actions.get("barrage_cancelled_owner",0)+planned
	planned = 0
